// Génère l'icône de l'app (1024 px) : swift scripts/make_icon.swift out.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Squircle macOS (grille Big Sur : 824 px dans 1024)
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.45, green: 0.27, blue: 0.90, alpha: 1),
])!
gradient.draw(in: shape, angle: -70)

// Reflet doux en haut
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Cartes empilées (historique)
func card(_ r: NSRect, alpha: CGFloat) {
    let p = NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44)
    NSColor.white.withAlphaComponent(alpha).setFill()
    p.fill()
}
card(NSRect(x: 330, y: 300, width: 400, height: 470), alpha: 0.35)
card(NSRect(x: 300, y: 270, width: 400, height: 470), alpha: 0.6)

let front = NSRect(x: 270, y: 240, width: 400, height: 470)
NSGraphicsContext.saveGraphicsState()
let s2 = NSShadow()
s2.shadowColor = NSColor.black.withAlphaComponent(0.25)
s2.shadowBlurRadius = 30
s2.shadowOffset = NSSize(width: 0, height: -12)
s2.set()
card(front, alpha: 1)
NSGraphicsContext.restoreGraphicsState()

// Lignes de texte sur la carte avant
let lineColor = NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.92, alpha: 1)
let widths: [CGFloat] = [300, 250, 280, 170]
for (i, w) in widths.enumerated() {
    let y = front.maxY - 120 - CGFloat(i) * 80
    lineColor.withAlphaComponent(i == 0 ? 1 : 0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: front.minX + 50, y: y, width: w, height: 34), xRadius: 17, yRadius: 17).fill()
}

// Pince du presse-papiers
let clip = NSRect(x: front.midX - 90, y: front.maxY - 40, width: 180, height: 80)
NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.55, alpha: 1).setFill()
NSBezierPath(roundedRect: clip, xRadius: 28, yRadius: 28).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
