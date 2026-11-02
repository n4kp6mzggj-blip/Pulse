import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("Pulse.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let bounds = NSRect(x: 36, y: 36, width: 952, height: 952)
    let background = NSBezierPath(roundedRect: bounds, xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.2, blue: 0.28, alpha: 1), ending: NSColor(srgbRed: 0.055, green: 0.08, blue: 0.12, alpha: 1))!.draw(in: background, angle: -60)
    NSColor.white.withAlphaComponent(0.1).setStroke()
    background.lineWidth = 3
    background.stroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 191, y: 500))
    for point in [NSPoint(x: 336, y: 500), NSPoint(x: 420, y: 693), NSPoint(x: 537, y: 303), NSPoint(x: 640, y: 570), NSPoint(x: 692, y: 500), NSPoint(x: 831, y: 500)] { path.line(to: point) }
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.35, green: 0.9, blue: 0.75, alpha: 0.45)
    shadow.shadowBlurRadius = 30
    shadow.set()
    NSColor(srgbRed: 0.45, green: 0.94, blue: 0.79, alpha: 1).setStroke()
    path.lineWidth = 43
    path.stroke()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    if size <= 512 { try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try png.write(to: iconset.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
