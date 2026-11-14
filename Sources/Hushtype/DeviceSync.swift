import AppKit
import Combine
import HushtypeCore
import os

/// Keeps the dictionary and snippets in step with the person's other devices (Macs, iPhone,
/// Android) through the Hushtype sync server. Everything is encrypted on this Mac with a secret
/// only the paired devices know; pairing hands that secret over as a QR code or a typed code.
@MainActor
final class DeviceSync: ObservableObject {
    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    /// Read by iCloud sync, which leaves the dictionary and snippets alone while this is on.
    static let enabledKey = "deviceSyncEnabled"
    private static let ledgerKey = "deviceSyncLedger"
    private static let lastSyncKey = "deviceSyncLast"
    private static let keychainAccount = "device-sync-secret"
    private static let interval: Duration = .seconds(10 * 60)

    @Published private(set) var status: Status = .off
    @Published private(set) var keys: SyncKeys?

    private let settings: SettingsStore
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "app.hushtype.Hushtype", category: "sync")
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var running = false
    private var runAgain = false
    /// True while synced words are written into Settings, so that write doesn't start a sync.
    private var applying = false

    init(settings: SettingsStore) {
        self.settings = settings
        if let secret = Keychain.read(account: Self.keychainAccount).flatMap({ Data(base64Encoded: $0) }) {
            keys = SyncKeys(secret: secret)
        }
        if keys != nil, let last = defaults.object(forKey: Self.lastSyncKey) as? Date { status = .upToDate(last) }
        defaults.set(keys != nil, forKey: Self.enabledKey)

        // Edits sync a couple of seconds after they settle.
        settings.$dictionaryText.map { _ in () }
            .merge(with: settings.$snippets.map { _ in () })
            .dropFirst(2)
            .filter { [weak self] in self?.applying == false }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.syncNow() }
            .store(in: &subscriptions)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        startTimer()
        syncNow()
    }

    var isOn: Bool { keys != nil }

    // MARK: Turning it on and off

    /// Starts a new group with this Mac's words. Other devices join by scanning its code.
    func turnOn() {
        guard keys == nil else { return }
        save(SyncKeys.generate())
        syncNow()
    }

    /// Joins the group another device started. Throws, leaving sync off, when the code is wrong or
    /// the server can't be reached.
    func join(code: String) async throws {
        guard let joined = SyncKeys(pairingCode: code) else {
            throw PairingError.notACode
        }
        status = .syncing
        let ledger = loadLedger().reconciled(terms: settings.vocabulary, snippets: settings.snippets)
        do {
            let merged = try await SyncClient(keys: joined).sync(ledger, joining: true)
            save(joined)
            apply(merged, startedFrom: ledger)
            finished()
        } catch {
            status = keys == nil ? .off : status
            throw error
        }
    }

    /// Stops syncing on this Mac. Its words stay; the other devices keep syncing with each other.
    func turnOff() {
        Keychain.delete(account: Self.keychainAccount)
        defaults.removeObject(forKey: Self.ledgerKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
        defaults.set(false, forKey: Self.enabledKey)
        keys = nil
        status = .off
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
        defaults.set(true, forKey: Self.enabledKey)
    }

    // MARK: Syncing

    func syncNow() {
        guard let keys else { return }
        if running {
            runAgain = true
            return
        }
        running = true
        status = .syncing
        let ledger = loadLedger().reconciled(terms: settings.vocabulary, snippets: settings.snippets)
        Task {
            defer {
                running = false
                if runAgain {
                    runAgain = false
                    syncNow()
                }
            }
            do {
                let merged = try await SyncClient(keys: keys).sync(ledger)
                guard self.keys == keys else { return }
                apply(merged, startedFrom: ledger)
                finished()
            } catch {
                guard self.keys == keys else { return }
                log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Writes the merged words into Settings without losing edits made while the request was out:
    /// those are folded in with newer timestamps and go up on the next round.
    private func apply(_ merged: SyncVocabulary, startedFrom ledger: SyncVocabulary) {
        let current = ledger.reconciled(terms: settings.vocabulary, snippets: settings.snippets)
        let final = SyncVocabulary.merge(local: current, remote: merged)
        saveLedger(final)

        let words = final.dictionary(keepingOrderOf: settings.vocabulary)
        let snippets = final.snippetList(keepingOrderOf: settings.snippets)
        applying = true
        if words != settings.vocabulary { settings.dictionaryText = words.joined(separator: "\n") }
        if snippets != settings.snippets { settings.snippets = snippets }
        DispatchQueue.main.async { [weak self] in self?.applying = false }
        if final != merged { runAgain = true }
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
