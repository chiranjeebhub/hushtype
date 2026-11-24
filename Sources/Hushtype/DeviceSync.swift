import AppKit
import Combine
import HushtypeCore
import os

/// Keeps the dictionary and snippets in step with the person's other devices, two ways at once:
/// - iCloud, when "Sync with iCloud" is on: Macs and iPhones on the same Apple ID, no pairing.
/// - The Hushtype sync server, once paired: any device, Android too. Everything is encrypted on
///   this Mac with a secret only the paired devices know; pairing hands it over as a QR code.
/// Both hold the same per-word record (`SyncVocabulary`), so each round merges whatever both say.
@MainActor
final class DeviceSync: ObservableObject {
    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    private static let ledgerKey = "deviceSyncLedger"
    private static let lastSyncKey = "deviceSyncLast"
    private static let legacyImportedKey = "deviceSyncImportedLegacyICloud"
    private static let keychainAccount = "device-sync-secret"
    private static let interval: Duration = .seconds(10 * 60)

    @Published private(set) var status: Status = .off
    @Published private(set) var keys: SyncKeys?

    private let settings: SettingsStore
    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private let log = Logger(subsystem: "app.hushtype.Hushtype", category: "sync")
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var runAgain = false
    /// True while synced words are written into Settings, so that write doesn't start a sync.
    private var applying = false

    init(settings: SettingsStore) {
        self.settings = settings
        if let secret = Keychain.read(account: Self.keychainAccount).flatMap({ Data(base64Encoded: $0) }) {
            keys = SyncKeys(secret: secret)
        }
        if isOn, let last = defaults.object(forKey: Self.lastSyncKey) as? Date { status = .upToDate(last) }

        // Edits sync a couple of seconds after they settle.
        settings.$dictionaryText.map { _ in () }
            .merge(with: settings.$snippets.map { _ in () })
            .dropFirst(2)
            .filter { [weak self] in self?.applying == false }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.syncNow() }
            .store(in: &subscriptions)
        settings.$iCloudSync
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.isOn { self.status = .off }
                self.syncNow()
            }
            .store(in: &subscriptions)
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncNow() }
            },
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncNow() }
            },
        ]
        cloud.synchronize()
        startTimer()
        syncNow()
    }

    /// Paired through the sync server.
    var isPaired: Bool { keys != nil }
    /// Syncing words through iCloud.
    var usesICloud: Bool { settings.iCloudSync }
    var isOn: Bool { isPaired || usesICloud }

    // MARK: Pairing

    /// Starts a new group with this Mac's words. Other devices join by scanning its code.
    func turnOn() {
        guard keys == nil else { return }
        save(SyncKeys.generate())
        syncNow()
    }

    /// Joins the group another device started. Throws, leaving pairing off, when the code is
    /// wrong or the server can't be reached.
    func join(code: String) async throws {
        guard let joined = SyncKeys(pairingCode: code) else {
            throw PairingError.notACode
        }
        status = .syncing
        let ledger = localLedger()
        do {
            let merged = try await SyncClient(keys: joined).sync(ledger, joining: true)
            save(joined)
            apply(merged, startedFrom: ledger)
            finished()
        } catch {
            status = isOn ? .failed(error.localizedDescription) : .off
            throw error
        }
    }

    /// Unpairs this Mac. Its words stay; the other devices keep syncing with each other, and
    /// iCloud keeps syncing if it's on.
    func turnOff() {
        Keychain.delete(account: Self.keychainAccount)
        keys = nil
        if !usesICloud {
            defaults.removeObject(forKey: Self.ledgerKey)
            defaults.removeObject(forKey: Self.lastSyncKey)
            status = .off
        }
    }

    enum PairingError: LocalizedError {
        case notACode
        var errorDescription: String? {
            "That isn't a Hushtype pairing code. It starts with HT1 and has 13 groups of four."
        }
    }

    private func save(_ new: SyncKeys) {
        Keychain.write(new.secret.base64EncodedString(), account: Self.keychainAccount)
        keys = new
    }

    // MARK: Syncing

    func syncNow() {
        guard isOn else { return }
        if running {
            runAgain = true
            return
        }
        running = true
        status = .syncing
        let keys = self.keys
        let iCloud = usesICloud
        if iCloud { importLegacyICloudOnce() }
        // `local` is what this device's words say. `start` adds what iCloud holds, and goes to the
        // server. Applying has to reconcile against `local`: against `start`, words that just came
        // from iCloud aren't in Settings yet and would look removed here, and be deleted everywhere.
        let local = localLedger()
        let fromICloud = iCloud ? CloudVocabulary.read(from: cloud) : nil
        let start = fromICloud.map { SyncVocabulary.merge(local: local, remote: $0) } ?? local
        Task {
            defer {
                running = false
                if runAgain {
                    runAgain = false
                    syncNow()
                }
            }
            var merged = start
            var failure: Error?
            if let keys {
                do {
                    merged = try await SyncClient(keys: keys).sync(start)
                } catch {
                    failure = error
                }
            }
            guard self.keys == keys, usesICloud == iCloud else { return }
            apply(merged, startedFrom: local)
            if let failure {
                log.error("Sync failed: \(failure.localizedDescription, privacy: .public)")
                status = .failed(failure.localizedDescription)
            } else {
                finished()
            }
        }
    }

    /// This Mac's record, updated with edits made since the last round.
    private func localLedger() -> SyncVocabulary {
        loadLedger().reconciled(terms: settings.vocabulary, snippets: settings.snippets)
    }

    /// Writes the merged words into Settings without losing edits made while the request was out:
    /// those are folded in with newer timestamps and go up on the next round. Then iCloud gets the
    /// result.
    private func apply(_ merged: SyncVocabulary, startedFrom ledger: SyncVocabulary) {
        let current = ledger.reconciled(terms: settings.vocabulary, snippets: settings.snippets)
        let final = SyncVocabulary.merge(local: current, remote: merged).compacted()
        saveLedger(final)
        if usesICloud { CloudVocabulary.write(final, to: cloud) }

        let words = final.dictionary(keepingOrderOf: settings.vocabulary)
        let snippets = final.snippetList(keepingOrderOf: settings.snippets)
        applying = true
        if words != settings.vocabulary { settings.dictionaryText = words.joined(separator: "\n") }
        if snippets != settings.snippets { settings.snippets = snippets }
        DispatchQueue.main.async { [weak self] in self?.applying = false }
        if isPaired, final != merged { runAgain = true }
    }

    /// Hushtype 0.3.7 and earlier kept the whole dictionary as one iCloud value. Its words are
    /// added here once, so nothing an older Mac synced is lost.
    private func importLegacyICloudOnce() {
        guard !defaults.bool(forKey: Self.legacyImportedKey) else { return }
        defaults.set(true, forKey: Self.legacyImportedKey)
        let legacy = CloudVocabulary.legacy(from: cloud)
        applying = true
        if !legacy.terms.isEmpty { settings.addToDictionary(legacy.terms) }
        let known = Set(settings.snippets.map(\.id))
        let missing = legacy.snippets.filter { !known.contains($0.id) }
        if !missing.isEmpty { settings.snippets += missing }
        DispatchQueue.main.async { [weak self] in self?.applying = false }
    }

    private func finished() {
        let now = Date()
        defaults.set(now, forKey: Self.lastSyncKey)
        status = .upToDate(now)
    }

    private func startTimer() {
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.syncNow()
            }
        }
    }

    private func loadLedger() -> SyncVocabulary {
        defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(SyncVocabulary.self, from: $0) }
            ?? SyncVocabulary()
    }

    private func saveLedger(_ ledger: SyncVocabulary) {
        defaults.set(try? JSONEncoder().encode(ledger), forKey: Self.ledgerKey)
    }
}
