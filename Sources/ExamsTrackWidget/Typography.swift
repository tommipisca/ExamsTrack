import SwiftUI

/// Gli stessi caratteri dell'app (vedi `Theme.swift`): nomi degli esami in New York,
/// countdown in SF Pro Compressed Black.
extension Font {
    static func examName(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func countdown(size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
}
