// Renders the stills the edit needs, in the system sans and the brand tokens only.
// The local ffmpeg has no text filter, so captions, the end card's lines and the device mask are
// drawn here as transparent PNGs and overlaid by assemble.sh.
//
//   xcrun swift render.swift text  out.png W H SIZE WEIGHT TOKEN "Line one\nLine two"
//   xcrun swift render.swift mask  out.png W H RADIUS        (white rounded rect on black)
//   xcrun swift render.swift ring  out.png W H RADIUS WIDTH TOKEN  (rounded outline, transparent)
//   xcrun swift render.swift hex   TOKEN                     (prints the dark value, for ffmpeg)
//
// WEIGHT: regular | medium | semibold | bold. TOKEN: a key of design/tokens.json "colors" (dark).
import AppKit

let args = CommandLine.arguments
let here = URL(fileURLWithPath: args[0]).deletingLastPathComponent()
// AARU_TOKENS when compiled elsewhere (assemble.sh sets it); else next to the script.
let tokensURL = ProcessInfo.processInfo.environment["AARU_TOKENS"].map { URL(fileURLWithPath: $0) }
    ?? here.appendingPathComponent("../../design/tokens.json").standardized

func token(_ name: String) -> NSColor {
    let data = try! Data(contentsOf: tokensURL)
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let colors = json["colors"] as! [String: Any]
    guard let entry = colors[name] as? [String: Any] else { fatalError("no token \(name)") }
    if let hex = entry["dark"] as? String { return color(hex) }
    // A derived token: another token at an alpha ({"of": "accent", "alpha": 0.3}).
    guard let derived = entry["dark"] as? [String: Any], let base = derived["of"] as? String,
          let alpha = derived["alpha"] as? Double else { fatalError("no token \(name)") }
    return token(base).withAlphaComponent(alpha)
}

func color(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: 1
    )
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: w, height: h))
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func weight(_ name: String) -> NSFont.Weight {
    switch name {
    case "medium": .medium
    case "semibold": .semibold
    case "bold": .bold
    default: .regular
    }
}

switch args[1] {
case "text":
    let (out, w, h, size) = (args[2], Int(args[3])!, Int(args[4])!, CGFloat(Double(args[5])!))
    let font = NSFont.systemFont(ofSize: size, weight: weight(args[6]))
    let text = args[8].replacingOccurrences(of: "\\n", with: "\n")
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = size * 0.18
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: token(args[7]), .paragraphStyle: style,
        .kern: size >= 48 ? -size * 0.012 : 0,
    ])
    let rep = canvas(w, h) { _ in
        let bounds = attributed.boundingRect(
            with: NSSize(width: CGFloat(w) * 0.88, height: CGFloat(h)), options: [.usesLineFragmentOrigin]
        )
        let rect = NSRect(
            x: (CGFloat(w) - CGFloat(w) * 0.88) / 2, y: (CGFloat(h) - bounds.height) / 2,
            width: CGFloat(w) * 0.88, height: bounds.height
        )
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin])
    }
    save(rep, out)
case "mask":
    let (out, w, h, r) = (args[2], Int(args[3])!, Int(args[4])!, CGFloat(Double(args[5])!))
    let rep = canvas(w, h) { cg in
        cg.setFillColor(NSColor.black.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        cg.setFillColor(NSColor.white.cgColor)
        cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        cg.fillPath()
    }
    save(rep, out)
case "ring":
    let (out, w, h, r, lw) = (args[2], Int(args[3])!, Int(args[4])!, CGFloat(Double(args[5])!), CGFloat(Double(args[6])!))
    let rep = canvas(w, h) { cg in
        cg.setStrokeColor(token(args[7]).cgColor)
        cg.setLineWidth(lw)
        let inset = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: lw / 2, dy: lw / 2)
        cg.addPath(CGPath(roundedRect: inset, cornerWidth: r, cornerHeight: r, transform: nil))
        cg.strokePath()
    }
    save(rep, out)
case "hex":
    let c = token(args[2]).usingColorSpace(.sRGB)!
    print(String(format: "0x%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255))))
default:
    fatalError("unknown command \(args[1])")
}
