import AppKit

enum AppIconArtwork {
    static func makeImage(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            draw(in: context, size: size)
        }

        image.unlockFocus()
        return image
    }

    /// Menu bar template image: monochrome pixel apple silhouette.
    static func makeMenuBarImage() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            context.setFillColor(NSColor.black.cgColor)
            let s = size / 18.0
            func px(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
                context.fill(CGRect(
                    x: CGFloat(x) * s, y: CGFloat(18 - y - h) * s,
                    width: CGFloat(w) * s, height: CGFloat(h) * s
                ))
            }
            // Stem
            px(8, 2, 2, 2)
            // Leaf
            px(10, 2, 2, 1)
            px(11, 3, 2, 1)
            // Apple body
            px(6, 4, 3, 1); px(10, 4, 3, 1) // dimple
            px(5, 5, 9, 1)
            px(4, 6, 11, 5) // rows 6-10
            px(5, 11, 9, 1)
            px(6, 12, 7, 1)
            px(7, 13, 5, 1)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func draw(in context: CGContext, size: CGFloat) {
        let tileRect = CGRect(
            x: size * 0.08,
            y: size * 0.08,
            width: size * 0.84,
            height: size * 0.84
        )
        let artRect = CGRect(
            x: size * 0.18,
            y: size * 0.15,
            width: size * 0.64,
            height: size * 0.64
        )

        drawTile(in: context, rect: tileRect, size: size)
        drawPixelArt(in: context, rect: artRect)
    }

    private static func drawTile(in context: CGContext, rect: CGRect, size: CGFloat) {
        let cornerRadius = rect.width * 0.225
        let shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        let outerPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let innerRect = rect.insetBy(dx: size * 0.01, dy: size * 0.01)
        let innerPath = CGPath(
            roundedRect: innerRect,
            cornerWidth: cornerRadius * 0.9,
            cornerHeight: cornerRadius * 0.9,
            transform: nil
        )

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.045, color: shadowColor)
        context.addPath(outerPath)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.setShouldAntialias(true)
        context.addPath(outerPath)
        context.clip()

        let colors = [Palette.tileTop.color.cgColor, Palette.tileBottom.color.cgColor] as CFArray
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )
        }

        context.setFillColor(Palette.tileSheen.color.withAlphaComponent(0.55).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.24, width: rect.width, height: rect.height * 0.18))
        context.restoreGState()

        context.saveGState()
        context.setShouldAntialias(true)
        context.addPath(innerPath)
        context.setStrokeColor(Palette.tileInnerBorder.color.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(size * 0.006)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setShouldAntialias(true)
        context.addPath(outerPath)
        context.setStrokeColor(Palette.tileOuterBorder.color.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(size * 0.004)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawPixelArt(in context: CGContext, rect: CGRect) {
        let cell = floor(min(rect.width, rect.height) / 32.0)
        let width = cell * 32.0
        let height = cell * 32.0
        let originX = rect.midX - width / 2.0
        let originY = rect.midY - height / 2.0

        context.saveGState()
        context.setShouldAntialias(false)
        context.interpolationQuality = .none

        func pixel(_ x: Int, _ y: Int, _ width: Int = 1, _ height: Int = 1, _ color: Palette) {
            let rect = CGRect(
                x: originX + CGFloat(x) * cell,
                y: originY + CGFloat(32 - y - height) * cell,
                width: CGFloat(width) * cell,
                height: CGFloat(height) * cell
            )
            fill(context, color: color, rect: rect)
        }

        func row(_ y: Int, _ runs: [(x: Int, width: Int, color: Palette)]) {
            for run in runs {
                pixel(run.x, y, run.width, 1, run.color)
            }
        }

        // Stem
        pixel(15, 2, 2, 4, .stem)
        pixel(15, 6, 2, 1, .stemDark)

        // Leaf
        pixel(17, 2, 2, 1, .leafLight)
        pixel(18, 3, 3, 1, .leafLight)
        pixel(19, 4, 3, 1, .leafDark)
        pixel(20, 5, 2, 1, .leafDark)

        // Apple outline
        row(6,  [(x: 9, width: 6, color: .appleShadow), (x: 18, width: 6, color: .appleShadow)])
        row(7,  [(x: 7, width: 19, color: .appleShadow)])
        row(8,  [(x: 6, width: 21, color: .appleShadow)])
        row(9,  [(x: 5, width: 23, color: .appleShadow)])
        for y in 10...17 { row(y, [(x: 5, width: 23, color: .appleShadow)]) }
        row(18, [(x: 6, width: 21, color: .appleShadow)])
        row(19, [(x: 6, width: 21, color: .appleShadow)])
        row(20, [(x: 7, width: 19, color: .appleShadow)])
        row(21, [(x: 8, width: 17, color: .appleShadow)])
        row(22, [(x: 10, width: 13, color: .appleShadow)])
        row(23, [(x: 12, width: 9, color: .appleShadow)])
        row(24, [(x: 14, width: 5, color: .appleShadow)])

        // Apple fill
        row(6,  [(x: 10, width: 5, color: .appleRed), (x: 18, width: 5, color: .appleRed)])
        row(7,  [(x: 8, width: 17, color: .appleRed)])
        row(8,  [(x: 7, width: 19, color: .appleRed)])
        for y in 9...17 { row(y, [(x: 6, width: 21, color: .appleRed)]) }
        row(18, [(x: 7, width: 19, color: .appleRed)])
        row(19, [(x: 7, width: 19, color: .appleRed)])
        row(20, [(x: 8, width: 17, color: .appleRed)])
        row(21, [(x: 9, width: 15, color: .appleRed)])
        row(22, [(x: 11, width: 11, color: .appleRed)])
        row(23, [(x: 13, width: 7, color: .appleRed)])

        // Shading (lower left)
        pixel(6, 13, 2, 5, .appleDark)
        pixel(7, 18, 2, 2, .appleDark)

        // Highlight (upper right)
        pixel(22, 9, 2, 1, .appleHighlight)
        pixel(23, 10, 2, 2, .appleHighlight)
        pixel(22, 12, 1, 1, .appleHighlight)

        // Shine
        pixel(23, 10, 1, 1, .appleShine)

        context.restoreGState()
    }

    private static func fill(_ context: CGContext, color: Palette, rect: CGRect) {
        context.setFillColor(color.color.cgColor)
        context.fill(rect)
    }
}

private enum Palette {
    case stem
    case stemDark
    case leafLight
    case leafDark
    case appleShadow
    case appleRed
    case appleDark
    case appleHighlight
    case appleShine
    case tileTop
    case tileBottom
    case tileSheen
    case tileInnerBorder
    case tileOuterBorder

    var color: NSColor {
        switch self {
        case .stem: return .hex(0x7A4F2A)
        case .stemDark: return .hex(0x5C3A1E)
        case .leafLight: return .hex(0x6A9B43)
        case .leafDark: return .hex(0x46712D)
        case .appleShadow: return .hex(0x8E1F1B)
        case .appleRed: return .hex(0xE03333)
        case .appleDark: return .hex(0xA1231C)
        case .appleHighlight: return .hex(0xF09888)
        case .appleShine: return .hex(0xFAD5CC)
        case .tileTop: return .hex(0xF6F7F2)
        case .tileBottom: return .hex(0xD8DED3)
        case .tileSheen: return .hex(0xFFFFFF)
        case .tileInnerBorder: return .hex(0xC3CDBF)
        case .tileOuterBorder: return .hex(0xFFFFFF)
        }
    }
}

private extension NSColor {
    static func hex(_ value: Int) -> NSColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
