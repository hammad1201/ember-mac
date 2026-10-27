import SwiftUI

/// Burgundy theme: wine and rose for structure, champagne as the warm accent.
enum Theme {
    static let deepWine = Color(red: 0.22, green: 0.03, blue: 0.09)
    static let burgundy = Color(red: 0.50, green: 0.08, blue: 0.19)
    static let wine = Color(red: 0.66, green: 0.13, blue: 0.26)
    static let rose = Color(red: 0.88, green: 0.38, blue: 0.50)
    static let blush = Color(red: 0.97, green: 0.70, blue: 0.76)
    static let champagne = Color(red: 0.95, green: 0.80, blue: 0.58)
    static let crimson = Color(red: 0.93, green: 0.16, blue: 0.24)
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .nominal: "No throttling"
        case .fair: "Warm, not throttling"
        case .serious: "Throttling"
        case .critical: "Heavily throttled"
        @unknown default: ""
        }
    }

    /// Softened status colours that sit well against burgundy.
    var color: Color {
        switch self {
        case .nominal: Color(red: 0.55, green: 0.86, blue: 0.68)
        case .fair: Theme.champagne
        case .serious: Color(red: 0.98, green: 0.58, blue: 0.32)
        default: Theme.crimson
        }
    }

    var symbol: String {
        switch self {
        case .nominal: "checkmark.seal.fill"
        case .fair: "thermometer.medium"
        case .serious: "exclamationmark.triangle.fill"
        default: "flame.fill"
        }
    }
}
