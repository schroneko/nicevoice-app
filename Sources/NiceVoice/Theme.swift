import SwiftUI

enum AppGradient {
    static let primary = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let processing = LinearGradient(
        colors: [.blue, .cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let action = LinearGradient(
        colors: [.orange, .pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let success = LinearGradient(
        colors: [.green, .teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let inactive = LinearGradient(
        colors: [.gray, .secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let secondary = LinearGradient(
        colors: [.secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let secondaryLight = LinearGradient(
        colors: [.secondary.opacity(0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primarySubtle = LinearGradient(
        colors: [.purple.opacity(0.5), .indigo.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let secondarySubtle = LinearGradient(
        colors: [.secondary.opacity(0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let disabled = LinearGradient(
        colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum AppCornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let pill: CGFloat = 100
}

enum AppFontSize {
    static let caption2: CGFloat = 10
    static let caption: CGFloat = 11
    static let footnote: CGFloat = 12
    static let subheadline: CGFloat = 13
    static let body: CGFloat = 14
    static let headline: CGFloat = 15
    static let title3: CGFloat = 18
    static let title2: CGFloat = 20
    static let title: CGFloat = 24
    static let largeTitle: CGFloat = 32
}
