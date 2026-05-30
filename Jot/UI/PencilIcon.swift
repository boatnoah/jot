import AppKit

/// The Jot brand mark: a small colored school pencil (yellow body, red eraser,
/// silver ferrule, wood tip with graphite point) drawn in code. Non-template so
/// it keeps its colors. Shared by the menu bar icon and the Dot's idle header.
enum PencilIcon {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Draw in a fixed 18pt coordinate space, scaled to the requested size.
            ctx.translateBy(x: size / 2, y: size / 2)
            ctx.scaleBy(x: size / 18, y: size / 18)
            ctx.rotate(by: .pi / 4)

            let len: CGFloat = 15
            let h: CGFloat = 5
            let left = -len / 2, right = len / 2
            let top = h / 2, bottom = -h / 2

            let woodEnd = left + 3.5
            let bodyEnd = right - 4.5
            let ferruleEnd = right - 2.8

            // Wood cone (tan).
            ctx.beginPath()
            ctx.move(to: CGPoint(x: left, y: 0))
            ctx.addLine(to: CGPoint(x: woodEnd, y: top))
            ctx.addLine(to: CGPoint(x: woodEnd, y: bottom))
            ctx.closePath()
            ctx.setFillColor(NSColor(calibratedRed: 0.85, green: 0.69, blue: 0.45, alpha: 1).cgColor)
            ctx.fillPath()

            // Graphite point (dark).
            ctx.beginPath()
            ctx.move(to: CGPoint(x: left, y: 0))
            ctx.addLine(to: CGPoint(x: left + 1.6, y: top * 0.45))
            ctx.addLine(to: CGPoint(x: left + 1.6, y: bottom * 0.45))
            ctx.closePath()
            ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor)
            ctx.fillPath()

            // Yellow body.
            ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.05, alpha: 1).cgColor)
            ctx.fill(CGRect(x: woodEnd, y: bottom, width: bodyEnd - woodEnd, height: h))

            // Silver ferrule.
            ctx.setFillColor(NSColor(white: 0.72, alpha: 1).cgColor)
            ctx.fill(CGRect(x: bodyEnd, y: bottom, width: ferruleEnd - bodyEnd, height: h))

            // Red eraser (rounded outer end).
            let eraser = CGRect(x: ferruleEnd, y: bottom, width: right - ferruleEnd, height: h)
            ctx.addPath(CGPath(roundedRect: eraser, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
            ctx.setFillColor(NSColor(calibratedRed: 0.91, green: 0.27, blue: 0.22, alpha: 1).cgColor)
            ctx.fillPath()

            return true
        }
        image.isTemplate = false
        return image
    }
}
