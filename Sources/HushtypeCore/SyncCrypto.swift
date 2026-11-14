import CryptoKit
import Foundation

/// The secret a group of devices shares, and everything derived from it. One device makes the
/// secret; the others get it by scanning its QR code or typing its pairing code. The server only
/// ever sees the group id, a token that lets it check writes, and data it can't decrypt.
///
/// sync-server/README.md describes the format for the Android app; keep the two in step.
public struct SyncKeys: Equatable, Sendable {
    /// 32 random bytes.
    public let secret: Data

    public init?(secret: Data) {
        guard secret.count == 32 else { return nil }
        self.secret = secret
    }

    public static func generate() -> SyncKeys {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = generator.next() }
        return SyncKeys(secret: Data(bytes))!
    }

    private func derive(_ label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                               salt: Data("hushtype-sync-v1".utf8),
                               info: Data(label.utf8),
                               outputByteCount: 32)
    }

    private static func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// Names the group on the server: 32 lowercase hex characters.
    public var groupID: String {
        Self.bytes(derive("group-id")).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Sent as a bearer token. The server keeps only its SHA-256, set by the first write.
    public var authToken: String { Self.base64URL(Self.bytes(derive("auth"))) }

    private var encryptionKey: SymmetricKey { derive("encryption") }

    // MARK: Pairing code

    /// What the QR code holds and what people type on a Mac: "HT1-" and the secret in Crockford
    /// base32, in groups of four.
    public var pairingCode: String {
        let body = Self.crockford(secret)
        var groups: [String] = []
        var rest = Substring(body)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return "HT1-" + groups.joined(separator: "-")
    }

    /// Reads a pairing code, forgiving case, spaces, dashes and look-alike letters (O for 0, I and L
    /// for 1). Nil when it isn't one.
    public init?(pairingCode: String) {
        var cleaned = pairingCode.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.hasPrefix("HT1") else { return nil }
        cleaned.removeFirst(3)
        guard let data = Self.decodeCrockford(cleaned), data.count == 32 else { return nil }
        self.init(secret: data)
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func crockford(_ data: Data) -> String {
        var output = ""
        var buffer: UInt32 = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[Int((buffer >> UInt32(bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 { output.append(alphabet[Int((buffer << UInt32(5 - bits)) & 31)]) }
        return output
    }

    static func decodeCrockford(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        var buffer: UInt32 = 0
        var bits = 0
        for character in text {
            let normalized: Character
            switch character {
            case "O": normalized = "0"
            case "I", "L": normalized = "1"
            default: normalized = character
            }
            guard let value = alphabet.firstIndex(of: normalized) else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> UInt32(bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return Data(bytes)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Sealing

    /// Format version 1: one byte 0x01, the 12-byte nonce, the ciphertext, the 16-byte tag. The
    /// group id is bound in as associated data, so a blob can't be moved to another group.
    public func seal(_ vocabulary: SyncVocabulary) throws -> Data {
        let plain = try JSONEncoder().encode(vocabulary)
        let box = try AES.GCM.seal(plain, using: encryptionKey, authenticating: Data(groupID.utf8))
        guard let combined = box.combined else { throw SyncError.badData }
        return Data([1]) + combined
    }

    public func open(_ blob: Data) throws -> SyncVocabulary {
        guard blob.count > 1 + 12 + 16, blob.first == 1 else { throw SyncError.badData }
        do {
            let box = try AES.GCM.SealedBox(combined: blob.dropFirst())
            let plain = try AES.GCM.open(box, using: encryptionKey, authenticating: Data(groupID.utf8))
            return try JSONDecoder().decode(SyncVocabulary.self, from: plain)
        } catch {
            throw SyncError.badData
        }
    }
}

public enum SyncError: LocalizedError, Equatable, Sendable {
    /// The pairing code doesn't match any devices yet.
    case noSuchGroup
    /// The server refused the token.
    case unauthorized
    /// Couldn't decrypt or read what the server sent.
    case badData
    case tooLarge
    case server(Int)
    case offline

    public var errorDescription: String? {
        switch self {
        case .noSuchGroup: return "No device is using that pairing code. Check it, or start sync on the other device first."
        case .unauthorized: return "The sync server didn't accept this device. Pair it again."
        case .badData: return "The synced data couldn't be read. Pair this device again."
        case .tooLarge: return "Your dictionary and snippets are too large to sync."
        case .server(let status): return "The sync server had a problem (\(status)). Hushtype will try again."
        case .offline: return "Couldn't reach the sync server. Hushtype will try again."
        }
    }
}
