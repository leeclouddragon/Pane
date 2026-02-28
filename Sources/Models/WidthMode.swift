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
    /// Text zoom level: 0.5 … 2.0, default 1.0. Persisted via UserDefaults.
    var zoomLevel: CGFloat {
        didSet { UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel") }
    }

    static let zoomMin: CGFloat = 0.5
    static let zoomMax: CGFloat = 2.0
    static let zoomStep: CGFloat = 0.1
    static let zoomDefault: CGFloat = 1.0

    init() {
        let stored = UserDefaults.standard.double(forKey: "zoomLevel")
        self.zoomLevel = stored > 0 ? CGFloat(stored) : Self.zoomDefault
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel + Self.zoomStep, Self.zoomMax)
    }
    func zoomOut() {
        zoomLevel = max(zoomLevel - Self.zoomStep, Self.zoomMin)
    }
    func zoomReset() {
        zoomLevel = Self.zoomDefault
    }
}
