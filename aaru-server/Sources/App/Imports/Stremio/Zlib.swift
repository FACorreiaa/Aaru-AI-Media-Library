import CZlib
import Foundation

/// Inflates zlib-wrapped data (RFC 1950), with a ceiling so a hostile input cannot balloon.
enum Zlib {
    struct Failure: Error, Equatable {}

    static func inflate(_ input: Data, limit: Int = 1 << 20) throws -> Data {
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure()
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        var source = [UInt8](input)
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var status = Z_OK
        source.withUnsafeMutableBufferPointer { buffer in
            stream.next_in = buffer.baseAddress
            stream.avail_in = uInt(buffer.count)
            while status == Z_OK, output.count <= limit {
                chunk.withUnsafeMutableBufferPointer { out in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(out.count)
                    status = CZlib.inflate(&stream, Z_NO_FLUSH)
                    if let base = out.baseAddress {
                        output.append(base, count: out.count - Int(stream.avail_out))
                    }
                }
            }
        }
        guard status == Z_STREAM_END, output.count <= limit else { throw Failure() }
        return output
    }
}
