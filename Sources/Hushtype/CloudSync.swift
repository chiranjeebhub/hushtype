import Combine
import Foundation
import HushtypeCore

/// Mirrors the settings that follow a person, not a Mac, through iCloud key-value storage: the
/// dictionary, snippets and style choices. The dictation key, microphone, login item and history
/// stay on each Mac, and so does "keep history", since turning it off erases that Mac's history.
/// This Mac's copy stays the source of truth; iCloud carries changes between Macs.
@MainActor
final class CloudSync {
    private let settings: SettingsStore
    private let controller: DictationController
    private var isEnabled = false
    private let store = NSUbiquitousKeyValueStore.default
    private var subscriptions: Set<AnyCancellable> = []
    private var observer: NSObjectProtocol?
    /// Set while remote values are applied, so they aren't echoed straight back.
    private var applyingRemote = false

    private enum Key {
        static let dictionary = "dictionary"
        static let snippets = "snippets"
        static let cleanupEnabled = "cleanupEnabled"
        static let useContext = "useContext"
        static let language = "language"
        static let soundsEnabled = "soundsEnabled"
        static let handsFree = "handsFree"
        static let learnFromCorrections = "learnFromCorrections"
    }

    init(settings: SettingsStore, controller: DictationController) {
        self.settings = settings
        self.controller = controller
        settings.$iCloudSync
            .removeDuplicates()
            .sink { [weak self] on in self?.apply(enabled: on) }
            .store(in: &subscriptions)
    }

    private var watching: Set<AnyCancellable> = []

    private func apply(enabled: Bool) {
        watching.removeAll()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard enabled else {
            if isEnabled { keepKeysOnThisMac() }
            isEnabled = false
            return
        }
        isEnabled = true
        if settings.syncAPIKey { settings.setKeySyncing(true) }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pull(merging: false) }
        }
        store.synchronize()
        // Combine what's already in iCloud with this Mac's settings, then send the result back up.
        pull(merging: true)
        pushAll()

        watch(settings.$dictionaryText) { [weak self] _ in self?.pushDictionary() }
        watch(settings.$snippets) { [weak self] _ in self?.pushSnippets() }
        watch(settings.$cleanupEnabled) { [weak self] in self?.push($0, Key.cleanupEnabled) }
        watch(settings.$useContext) { [weak self] in self?.push($0, Key.useContext) }
        watch(settings.$language) { [weak self] in self?.push($0, Key.language) }
        watch(settings.$soundsEnabled) { [weak self] in self?.push($0, Key.soundsEnabled) }
        watch(settings.$handsFree) { [weak self] in self?.push($0, Key.handsFree) }
        watch(settings.$learnFromCorrections) { [weak self] in self?.push($0, Key.learnFromCorrections) }
    }

    /// Calls `send` for every later change to a setting (not its current value).
    private func watch<Value>(_ publisher: Published<Value>.Publisher, _ send: @escaping (Value) -> Void) {
        publisher
            .dropFirst()
            // @Published fires before the property changes; hop a turn so the store sees the new value.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, !self.applyingRemote else { return }
                send(value)
            }
            .store(in: &watching)
    }

    // MARK: Sending

    private func pushAll() {
        pushDictionary()
        pushSnippets()
        push(settings.cleanupEnabled, Key.cleanupEnabled)
        push(settings.useContext, Key.useContext)
        push(settings.language, Key.language)
        push(settings.soundsEnabled, Key.soundsEnabled)
        push(settings.handsFree, Key.handsFree)
        push(settings.learnFromCorrections, Key.learnFromCorrections)
    }

    private func push(_ value: Bool, _ key: String) { store.set(value, forKey: key) }
    private func push(_ value: String, _ key: String) { store.set(value, forKey: key) }

    private func pushDictionary() {
        store.set(settings.dictionaryText, forKey: Key.dictionary)
    }

    private func pushSnippets() {
        if let data = try? JSONEncoder().encode(settings.snippets) { store.set(data, forKey: Key.snippets) }
    }

    // MARK: Receiving

    /// Applies what's in iCloud. When sync is first turned on, words and snippets are merged so
    /// nothing on either side is lost; after that iCloud's copy replaces this Mac's, so a word
    /// removed on one Mac is removed on the others too.
    private func pull(merging: Bool) {
        applyingRemote = true
        defer {
            // Let the change notifications from these assignments pass before echoing resumes.
            DispatchQueue.main.async { [weak self] in self?.applyingRemote = false }
        }

        if let remote = store.string(forKey: Key.dictionary) {
            if merging {
                settings.addToDictionary(DictationPipeline.vocabulary(from: remote))
            } else if remote != settings.dictionaryText {
                settings.dictionaryText = remote
            }
        }
        if let data = store.data(forKey: Key.snippets),
           let remote = try? JSONDecoder().decode([Snippet].self, from: data) {
            let updated = merging ? SnippetSync.merge(settings.snippets, remote) : remote
            if updated != settings.snippets { settings.snippets = updated }
        }

        // Simple choices take the latest value from iCloud.
        if let value = bool(Key.cleanupEnabled), value != settings.cleanupEnabled { settings.cleanupEnabled = value }
        if let value = bool(Key.useContext), value != settings.useContext { settings.useContext = value }
        if let value = store.string(forKey: Key.language), value != settings.language {
            settings.language = value
            controller.prepareSpeechModel()
        }
        if let value = bool(Key.soundsEnabled), value != settings.soundsEnabled { settings.soundsEnabled = value }
        if let value = bool(Key.handsFree), value != settings.handsFree {
            settings.handsFree = value
            controller.restartHotkey()
        }
        if let value = bool(Key.learnFromCorrections), value != settings.learnFromCorrections {
            settings.learnFromCorrections = value
        }
    }

    /// With sync off, a key kept in iCloud Keychain also gets a copy on this Mac, so it still works
    /// if this Mac later signs out of iCloud.
    private func keepKeysOnThisMac() {
        guard settings.syncAPIKey else { return }
        for service in APIService.allCases {
            if let key = Keychain.read(account: service.rawValue, synced: true) {
                Keychain.write(key, account: service.rawValue)
            }
        }
    }

    private func bool(_ key: String) -> Bool? {
        store.object(forKey: key) as? Bool
    }
}
