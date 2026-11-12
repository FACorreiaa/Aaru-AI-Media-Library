// Frames the raw store screenshots (REL-005): the poster's night sky, a caption, the screen.
//
//   xcrun swiftc -O scripts/frame-screenshots.swift -o /tmp/frame-screenshots && /tmp/frame-screenshots
//
// Reads aaru-ios/fastlane/screenshots/raw/<device>/<name>.png and captions.json beside it, and
// writes aaru-ios/fastlane/screenshots/en-US/<device>-<name>.png at the size the store takes
// for that device. Colours come from design/tokens.json; the type is the system sans.

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let shots = root.appendingPathComponent("aaru-ios/fastlane/screenshots")

struct Caption: Decodable {
    let title: String
    let subtitle: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func colour(_ hex: String) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// A token's night value. Some tokens are a tint of another and have no hex of their own.
func night(_ name: String, in colours: [String: Any]) -> String? {
    (colours[name] as? [String: Any])?["dark"] as? String
}

guard let tokenData = try? Data(contentsOf: root.appendingPathComponent("design/tokens.json")),
      let tokens = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
      let colours = tokens["colors"] as? [String: Any],
      let sky = night("night", in: colours), let ink = night("ink", in: colours),
      let muted = night("muted", in: colours), let edge = night("accent", in: colours)
else { fail("Run from the repo root: design/tokens.json was not read.") }

guard let captionData = try? Data(contentsOf: shots.appendingPathComponent("captions.json")),
      let captions = try? JSONDecoder().decode([String: Caption].self, from: captionData)
else { fail("captions.json was not read.") }

/// The store's size for a raw screen: iPhone 6.9", iPad 13" or a 16:10 Mac.
func canvas(for raw: CGSize) -> CGSize {
    if raw.width > raw.height { return CGSize(width: 2880, height: 1800) }
    return raw.width >= 2000 ? CGSize(width: 2064, height: 2752) : CGSize(width: 1320, height: 2868)
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, hex: String) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: colour(hex)) ?? .white,
        .paragraphStyle: style,
        .kern: -size * 0.02,
    ])
}

func frame(_ source: URL, caption: Caption, to target: URL) {
    guard let image = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fail("Not a picture: \(source.path)") }
    let raw = CGSize(width: image.width, height: image.height)
    let size = canvas(for: raw)
    let wide = size.width > size.height
    let unit = size.width / (wide ? 240 : 110)

    guard let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fail("No canvas.") }
    context.setFillColor(colour(sky))
    context.fill(CGRect(origin: .zero, size: size))

    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let margin = unit * 8
    let column = size.width - margin * 2
    let title = text(caption.title, size: unit * 7, weight: .bold, hex: ink)
    let titleHeight = ceil(title.boundingRect(
        with: CGSize(width: column, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin
    ).height)
    var top = size.height - unit * 10
    title.draw(with: CGRect(x: margin, y: top - titleHeight, width: column, height: titleHeight),
               options: .usesLineFragmentOrigin)
    top -= titleHeight
    if let line = caption.subtitle {
        let subtitle = text(line, size: unit * 4, weight: .regular, hex: muted)
        let height = ceil(subtitle.boundingRect(
            with: CGSize(width: column, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin
        ).height)
        top -= unit * 2
        subtitle.draw(with: CGRect(x: margin, y: top - height, width: column, height: height),
                      options: .usesLineFragmentOrigin)
        top -= height
    }
    top -= unit * 6

    // The screen fills what is left, whole, above a bottom margin.
    let bottom = unit * 6
    let scale = min((top - bottom) / raw.height, column / raw.width)
    let fitted = CGSize(width: raw.width * scale, height: raw.height * scale)
    let rect = CGRect(x: (size.width - fitted.width) / 2, y: top - fitted.height,
                      width: fitted.width, height: fitted.height)
    // An iPhone's screen is round at the corners; an iPad's and a Mac window's far less.
    let radius = unit * (wide ? 1.2 : raw.width >= 2000 ? 2 : 5)
    let outline = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    context.restoreGState()
    context.addPath(outline)
    context.setStrokeColor(colour(edge).copy(alpha: 0.5) ?? colour(edge))
    context.setLineWidth(max(2, unit * 0.25))
    context.strokePath()

    guard let made = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: made).representation(using: .png, properties: [:])
    else { fail("Could not draw \(target.lastPathComponent)") }
    do {
        try png.write(to: target)
    } catch {
        fail("Could not write \(target.path): \(error.localizedDescription)")
    }
    print("\(target.lastPathComponent)  \(Int(size.width))×\(Int(size.height))")
}

let files = FileManager.default
let rawFolder = shots.appendingPathComponent("raw")
let out = shots.appendingPathComponent("en-US")
try? files.createDirectory(at: out, withIntermediateDirectories: true)
let devices = (try? files.contentsOfDirectory(atPath: rawFolder.path))?.sorted() ?? []
if devices.isEmpty { fail("Nothing in \(rawFolder.path). Run scripts/store-screenshots.sh first.") }
for device in devices {
    let folder = rawFolder.appendingPathComponent(device)
    let names = (try? files.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".png") }.sorted() ?? []
    for name in names {
        let key = String(name.dropLast(4))
        guard let caption = captions[key] else {
            print("\(device)/\(name): no caption, left out")
            continue
        }
        frame(folder.appendingPathComponent(name), caption: caption,
              to: out.appendingPathComponent("\(device)-\(name)"))
    }
}
