import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Runs `body` inside an autorelease pool where the platform has them, and plainly elsewhere.
private func withAutoreleasePool(_ body: () throws -> Void) rethrows {
    #if canImport(ObjectiveC)
    try autoreleasepool(invoking: body)
    #else
    try body()
    #endif
}

/// SHA-256 as 64 lower-case hex characters, for data and for files of any size.
public enum SHA256Hex {
    public static func of(_ data: Data) -> String {
        var hasher = StreamingSHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    /// Streamed, 1 MiB at a time, so a long recording never has to fit in memory.
    public static func ofFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = StreamingSHA256()
        var reachedEnd = false
        while !reachedEnd {
            // Each chunk is released before the next is read. Without the pool, Apple platforms may
            // keep every chunk alive until this function returns, which for a long clip is the whole file.
            try withAutoreleasePool {
                if let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                    hasher.update(chunk)
                } else {
                    reachedEnd = true
                }
            }
        }
        return hasher.finalize()
    }

    public static func isValid(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        guard bytes.count == 64 else { return false }
        return bytes.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }
}

private func hexString(_ bytes: some Sequence<UInt8>) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    for byte in bytes {
        out.append(digits[Int(byte >> 4)])
        out.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: out, as: UTF8.self)
}

#if canImport(CryptoKit)

/// On Apple platforms the system's own implementation does the work.
private struct StreamingSHA256 {
    private var hasher = SHA256()

    mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    mutating func finalize() -> String {
        hexString(hasher.finalize())
    }
}

#else

/// Elsewhere (Linux, for tests and tools): SHA-256 as written in FIPS 180-4.
private struct StreamingSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var pending: [UInt8] = []
    private var totalBytes: UInt64 = 0
    private var schedule = [UInt32](repeating: 0, count: 64)

    mutating func update(_ data: Data) {
        totalBytes += UInt64(data.count)
        pending.append(contentsOf: data)
        var offset = 0
        while pending.count - offset >= 64 {
            compress(blockAt: offset)
            offset += 64
        }
        if offset > 0 {
            pending.removeFirst(offset)
        }
    }

    mutating func finalize() -> String {
        let bitLength = totalBytes * 8
        pending.append(0x80)
        while pending.count % 64 != 56 {
            pending.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            pending.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        var offset = 0
        while offset < pending.count {
            compress(blockAt: offset)
            offset += 64
        }
        var digest = [UInt8]()
        for word in state {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return hexString(digest)
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private mutating func compress(blockAt offset: Int) {
        for index in 0..<16 {
            let base = offset + index * 4
            schedule[index] = (UInt32(pending[base]) << 24) | (UInt32(pending[base + 1]) << 16)
                | (UInt32(pending[base + 2]) << 8) | UInt32(pending[base + 3])
        }
        for index in 16..<64 {
            let w15 = schedule[index - 15]
            let w2 = schedule[index - 2]
            let s0 = Self.rotateRight(w15, 7) ^ Self.rotateRight(w15, 18) ^ (w15 >> 3)
            let s1 = Self.rotateRight(w2, 17) ^ Self.rotateRight(w2, 19) ^ (w2 >> 10)
            schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for index in 0..<64 {
            let bigS1 = Self.rotateRight(e, 6) ^ Self.rotateRight(e, 11) ^ Self.rotateRight(e, 25)
            let choose = (e & f) ^ (~e & g)
            let temp1 = h &+ bigS1 &+ choose &+ Self.k[index] &+ schedule[index]
            let bigS0 = Self.rotateRight(a, 2) ^ Self.rotateRight(a, 13) ^ Self.rotateRight(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = bigS0 &+ majority
            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }
        state[0] = state[0] &+ a
        state[1] = state[1] &+ b
        state[2] = state[2] &+ c
        state[3] = state[3] &+ d
        state[4] = state[4] &+ e
        state[5] = state[5] &+ f
        state[6] = state[6] &+ g
        state[7] = state[7] &+ h
    }
}

#endif
