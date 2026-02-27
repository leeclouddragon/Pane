import SwiftUI

enum WidthMode: String, CaseIterable {
    case compact  // 768px max
    case normal   // 1120px max
    case wide     // full width - padding

    var maxWidth: CGFloat? {
        switch self {
        case .compact: 768
        case .normal: 1120
        case .wide: nil
        }
    }

    var label: String {
        switch self {
        case .compact: "Compact"
        case .normal: "Normal"
        case .wide: "Wide"
        }
    }

    func next() -> WidthMode {
        switch self {
        case .compact: .normal
        case .normal: .wide
        case .wide: .compact
        }
    }
}

@Observable
final class AppSettings {
    var widthMode: WidthMode = .normal
}
