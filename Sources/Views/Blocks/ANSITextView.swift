import SwiftUI

/// Renders text containing ANSI escape sequences with proper colors in monospaced font.
struct ANSITextView: View {
    let text: String

    @State private var attributed: AttributedString = AttributedString()

    var body: some View {
        Text(attributed)
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: text, initial: true) { attributed = Self.parse(text) }
    }

    /// Returns true if text contains ANSI escape sequences.
    static func containsANSI(_ text: String) -> Bool {
        text.contains("\u{1B}[")
    }

    /// Parse ANSI text into an AttributedString with color/bold/dim attributes.
    static func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var style = ANSIStyle()

        var i = input.startIndex
        var segmentStart = i

        while i < input.endIndex {
            // Detect ESC[ sequence
            if input[i] == "\u{1B}" {
                let next = input.index(after: i)
                if next < input.endIndex && input[next] == "[" {
                    // Flush text before escape
                    if segmentStart < i {
                        result.append(styledSegment(String(input[segmentStart..<i]), style: style))
                    }
                    // Find the terminating 'm'
                    var j = input.index(after: next)
                    while j < input.endIndex && input[j] != "m" {
                        // Bail if we hit a non-CSI character (not digit, not semicolon)
                        if !input[j].isASCII || (!input[j].isNumber && input[j] != ";") {
                            break
                        }
                        j = input.index(after: j)
                    }
                    if j < input.endIndex && input[j] == "m" {
                        let params = String(input[input.index(after: next)..<j])
                        style.apply(params)
                        i = input.index(after: j)
                        segmentStart = i
                        continue
                    }
                }
            }
            i = input.index(after: i)
        }

        // Flush remaining text
        if segmentStart < input.endIndex {
            result.append(styledSegment(String(input[segmentStart...]), style: style))
        }

        return result
    }

    private static func styledSegment(_ text: String, style: ANSIStyle) -> AttributedString {
        var seg = AttributedString(text)

        // Font weight
        if style.bold {
            seg.font = .system(size: 11, weight: .bold, design: .monospaced)
        }

        // Foreground color
        if let fg = style.fg {
            seg.foregroundColor = style.dim ? fg.opacity(0.5) : fg
        } else if style.dim {
            seg.foregroundColor = Color.primary.opacity(0.5)
        }

        // Background color
        if let bg = style.bg {
            seg.backgroundColor = bg
        }

        return seg
    }
}

// MARK: - ANSI Style State

private struct ANSIStyle {
    var fg: Color?
    var bg: Color?
    var bold = false
    var dim = false

    mutating func apply(_ params: String) {
        let codes = params.isEmpty ? [0] : params.split(separator: ";").compactMap { Int($0) }
        var idx = 0
        while idx < codes.count {
            let code = codes[idx]
            switch code {
            case 0:
                fg = nil; bg = nil; bold = false; dim = false
            case 1:
                bold = true
            case 2:
                dim = true
            case 22:
                bold = false; dim = false
            case 30...37:
                fg = Self.standard[code - 30]
            case 38:
                // Extended foreground: 38;5;N or 38;2;R;G;B
                if idx + 1 < codes.count {
                    if codes[idx + 1] == 5, idx + 2 < codes.count {
                        fg = Self.color256(codes[idx + 2])
                        idx += 2
                    } else if codes[idx + 1] == 2, idx + 4 < codes.count {
                        fg = Color(
                            red: Double(codes[idx + 2]) / 255,
                            green: Double(codes[idx + 3]) / 255,
                            blue: Double(codes[idx + 4]) / 255
                        )
                        idx += 4
                    }
                }
            case 39:
                fg = nil
            case 40...47:
                bg = Self.standard[code - 40]
            case 48:
                // Extended background: 48;5;N or 48;2;R;G;B
                if idx + 1 < codes.count {
                    if codes[idx + 1] == 5, idx + 2 < codes.count {
                        bg = Self.color256(codes[idx + 2])
                        idx += 2
                    } else if codes[idx + 1] == 2, idx + 4 < codes.count {
                        bg = Color(
                            red: Double(codes[idx + 2]) / 255,
                            green: Double(codes[idx + 3]) / 255,
                            blue: Double(codes[idx + 4]) / 255
                        )
                        idx += 4
                    }
                }
            case 49:
                bg = nil
            case 90...97:
                fg = Self.bright[code - 90]
            case 100...107:
                bg = Self.bright[code - 100]
            default:
                break
            }
            idx += 1
        }
    }

    // Standard 8 colors (SGR 30-37 / 40-47)
    private static let standard: [Color] = [
        .black,                                          // 0 black
        Color(red: 0.80, green: 0.13, blue: 0.13),      // 1 red
        Color(red: 0.13, green: 0.73, blue: 0.13),      // 2 green
        Color(red: 0.80, green: 0.73, blue: 0.13),      // 3 yellow
        Color(red: 0.20, green: 0.40, blue: 0.87),      // 4 blue
        Color(red: 0.73, green: 0.20, blue: 0.73),      // 5 magenta
        Color(red: 0.13, green: 0.73, blue: 0.73),      // 6 cyan
        Color(white: 0.75),                              // 7 white
    ]

    // Bright 8 colors (SGR 90-97 / 100-107)
    private static let bright: [Color] = [
        Color(white: 0.50),                              // 0 bright black (gray)
        Color(red: 1.00, green: 0.33, blue: 0.33),      // 1 bright red
        Color(red: 0.33, green: 1.00, blue: 0.33),      // 2 bright green
        Color(red: 1.00, green: 1.00, blue: 0.33),      // 3 bright yellow
        Color(red: 0.40, green: 0.53, blue: 1.00),      // 4 bright blue
        Color(red: 1.00, green: 0.33, blue: 1.00),      // 5 bright magenta
        Color(red: 0.33, green: 1.00, blue: 1.00),      // 6 bright cyan
        .white,                                          // 7 bright white
    ]

    // 256-color palette
    private static func color256(_ n: Int) -> Color {
        switch n {
        case 0...7:
            return standard[n]
        case 8...15:
            return bright[n - 8]
        case 16...231:
            // 6x6x6 color cube
            let idx = n - 16
            let r = Double((idx / 36) % 6) / 5.0
            let g = Double((idx / 6) % 6) / 5.0
            let b = Double(idx % 6) / 5.0
            return Color(red: r, green: g, blue: b)
        case 232...255:
            // Grayscale ramp
            let gray = Double((n - 232) * 10 + 8) / 255.0
            return Color(white: gray)
        default:
            return .primary
        }
    }
}
