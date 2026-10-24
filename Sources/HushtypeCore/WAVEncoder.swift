import Foundation

/// Encodes 16-bit PCM samples into a RIFF/WAVE container.
public enum WAVEncoder {
    public static func encode(samples: [Int16], sampleRate: Int = 16_000, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataSize = samples.count * MemoryLayout<Int16>.size

        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLE(UInt32(16))              // fmt chunk size
        data.appendLE(UInt16(1))               // PCM
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(UInt32(dataSize))
        samples.withUnsafeBufferPointer { buffer in
            for sample in buffer { data.appendLE(UInt16(bitPattern: sample)) }
        }
        return data
    }

    /// Converts float samples in [-1, 1] to 16-bit PCM, clipping out-of-range values.
    public static func pcm16(from floats: [Float]) -> [Int16] {
        floats.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
