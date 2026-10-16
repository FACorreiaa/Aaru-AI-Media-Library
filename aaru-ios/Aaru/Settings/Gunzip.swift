import Foundation

/// MyAnimeList exports download as `.xml.gz`; the server takes the XML. Apple's `.zlib`
/// decompression is raw DEFLATE (RFC 1951), so the gzip wrapper (RFC 1952) is read here.
enum Gunzip {
    enum Failure: Error, Equatable {
        case notGzip
        case tooLarge
        case corrupt
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    /// The decompressed bytes, refused before inflating when the declared size exceeds `limit`.
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        let bytes = [UInt8](data)
        // Header (10) + trailer (8: CRC32, then the input size mod 2^32).
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw Failure.notGzip }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.corrupt }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 { // FNAME, FCOMMENT: zero-terminated
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw Failure.corrupt }
            offset = end + 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        let trailer = bytes.count - 8
        guard offset < trailer else { throw Failure.corrupt }
        let declared = bytes[trailer + 4 ..< bytes.count].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard declared <= limit else { throw Failure.tooLarge }
        let deflated = Data(bytes[offset ..< trailer]) as NSData
        guard let inflated = try? deflated.decompressed(using: .zlib) as Data else { throw Failure.corrupt }
        guard inflated.count <= limit else { throw Failure.tooLarge }
        return inflated
    }
}
