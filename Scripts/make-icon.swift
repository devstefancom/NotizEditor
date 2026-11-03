// Renders the app icon into an .iconset folder: swift Scripts/make-icon.swift <out.iconset>
// Same style as Knipser, Filmer and FTP Upload: rounded square inset 10 % with 18 % corner radius, soft shadow,
// vertical gradient (here amber, like a note pad) and a white line glyph (a page with lines of text and a cursor).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    // Warm yellow at the top to amber at the bottom.
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.22, alpha: 1),
               ending: NSColor(srgbRed: 0.91, green: 0.50, blue: 0.04, alpha: 1))!.draw(in: shape, angle: -90)
    NSShadow().set()

    NSColor.white.setStroke()
    NSColor.white.setFill()
    // The page
    let page = NSBezierPath(roundedRect: CGRect(x: s * 0.29, y: s * 0.22, width: s * 0.42, height: s * 0.56),
                            xRadius: s * 0.05, yRadius: s * 0.05)
    page.lineWidth = s * 0.045
    page.stroke()
    // Lines of text, the last one shorter with the cursor after it
    let lines = NSBezierPath()
    lines.lineWidth = s * 0.04
    lines.lineCapStyle = .round
    for (y, end) in [(0.65, 0.61), (0.54, 0.61), (0.43, 0.61), (0.32, 0.47)] {
        lines.move(to: CGPoint(x: s * 0.39, y: s * y))
        lines.line(to: CGPoint(x: s * end, y: s * y))
    }
    lines.stroke()
    let cursor = NSBezierPath()
    cursor.lineWidth = s * 0.03
    cursor.lineCapStyle = .round
    cursor.move(to: CGPoint(x: s * 0.535, y: s * 0.27))
    cursor.line(to: CGPoint(x: s * 0.535, y: s * 0.37))
    cursor.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
