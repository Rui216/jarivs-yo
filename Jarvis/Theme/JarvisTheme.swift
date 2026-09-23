//
//  JarvisTheme.swift
//  JARVIS
//
//  Central design tokens for the JARVIS interface: a dark navy canvas,
//  layered card surfaces, and a cyan accent used for highlights and glow.
//  Every view reads its colors, radii, spacing, and typography from this
//  file so the visual language stays consistent across screens.
//

import SwiftUI
import AppKit

/// Holds the design tokens used across the application.
enum JarvisTheme {

    // MARK: - Palette

    /// Named colors for the dark navy interface.
    enum Palette {
        /// Deepest background, used behind everything else.
        static let canvas = Color(hex: 0x060A16)
        /// Slightly lifted background used behind the dashboard scroll area.
        static let canvasElevated = Color(hex: 0x0A1122)
        /// Sidebar background.
        static let sidebar = Color(hex: 0x080D1C)
        /// Default card background.
        static let card = Color(hex: 0x0F1A31)
        /// Card background for emphasized content such as the clock card.
        static let cardElevated = Color(hex: 0x14233F)
        /// Hairline border for cards and controls.
        static let stroke = Color(hex: 0x1E2F4F)
        /// Stronger border used for focused or active states.
        static let strokeStrong = Color(hex: 0x2C4A78)

        /// Primary cyan accent.
        static let accent = Color(hex: 0x38D8EE)
        /// Lighter accent for gradients and highlights.
        static let accentBright = Color(hex: 0x7BF0FF)
        /// Deep accent used for gradient tails.
        static let accentDeep = Color(hex: 0x1C8FB0)

        /// Primary text color.
        static let textPrimary = Color(hex: 0xE9F1FC)
        /// Secondary text color for supporting copy.
        static let textSecondary = Color(hex: 0x93A9CC)
        /// Tertiary text color for timestamps and hints.
        static let textTertiary = Color(hex: 0x6076A0)

        /// Positive status color.
        static let success = Color(hex: 0x3DDC97)
        /// Cautionary status color.
        static let warning = Color(hex: 0xF5B94B)
        /// Negative status color.
        static let danger = Color(hex: 0xFF6B6B)
        /// Informational status color.
        static let info = Color(hex: 0x6FA8FF)
        /// Violet highlight used for a few accents.
        static let violet = Color(hex: 0x9B8CFF)
    }

    // MARK: - Metrics

    /// Corner radii used by cards and controls.
    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 12
        static let chip: CGFloat = 8
        static let sidebarItem: CGFloat = 12
    }

    /// Standard spacing steps.
    enum Spacing {
        static let hairline: CGFloat = 4
        static let tight: CGFloat = 8
        static let regular: CGFloat = 14
        static let loose: CGFloat = 20
        static let section: CGFloat = 26
    }

    /// Standard layout sizes.
    enum Layout {
        static let sidebarWidth: CGFloat = 232
        static let sidebarCollapsedWidth: CGFloat = 78
        static let assistantColumnWidth: CGFloat = 372
        static let minimumWindowWidth: CGFloat = 1180
        static let minimumWindowHeight: CGFloat = 760
        static let contentPadding: CGFloat = 24
    }

    // MARK: - Typography

    /// Rounded system typography used throughout the app.
    enum Typography {
        /// Large numerals, for example the main clock.
        static func display(_ size: CGFloat = 56) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// Card titles.
        static func title(_ size: CGFloat = 17) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// Emphasized body copy.
        static func headline(_ size: CGFloat = 14) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// Default body copy.
        static func body(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .rounded)
        }

        /// Supporting copy such as timestamps and hints.
        static func caption(_ size: CGFloat = 11) -> Font {
            .system(size: size, weight: .medium, design: .rounded)
        }

        /// Monospaced text used for terminal style output.
        static func mono(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    // MARK: - Gradients

    /// Background gradient for the whole window.
    static let canvasGradient = LinearGradient(
        colors: [Palette.canvasElevated, Palette.canvas],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent gradient used for filled buttons and progress rings.
    static let accentGradient = LinearGradient(
        colors: [Palette.accentBright, Palette.accent, Palette.accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle top down sheen used on card surfaces.
    static func cardGradient(elevated: Bool) -> LinearGradient {
        let base = elevated ? Palette.cardElevated : Palette.card
        return LinearGradient(
            colors: [base.opacity(0.98), base.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Color helpers

extension Color {
    /// Creates a color from a 24 bit RGB literal, for example `0x38D8EE`.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension NSColor {
    /// AppKit equivalent of the theme colors, used for window chrome.
    convenience init(jarvisHex hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Surface modifiers

/// Applies the layered card surface, hairline border, and soft shadow.
struct JarvisCardSurface: ViewModifier {
    /// Uses the lifted card color when true.
    var isElevated: Bool = false
    /// Draws an accent border when true, used for selected or active cards.
    var isHighlighted: Bool = false
    /// Corner radius override.
    var cornerRadius: CGFloat = JarvisTheme.Radius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(JarvisTheme.cardGradient(elevated: isElevated))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted
                            ? JarvisTheme.Palette.accent.opacity(0.55)
                            : JarvisTheme.Palette.stroke,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isHighlighted
                    ? JarvisTheme.Palette.accent.opacity(0.18)
                    : Color.black.opacity(0.35),
                radius: isHighlighted ? 18 : 12,
                x: 0,
                y: 8
            )
    }
}

/// Applies an accent glow around a view.
struct JarvisGlow: ViewModifier {
    var color: Color = JarvisTheme.Palette.accent
    var radius: CGFloat = 14
    var opacity: Double = 0.35

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

extension View {
    /// Wraps the view in the standard JARVIS card surface.
    func jarvisCard(
        elevated: Bool = false,
        highlighted: Bool = false,
        cornerRadius: CGFloat = JarvisTheme.Radius.card
    ) -> some View {
        modifier(JarvisCardSurface(
            isElevated: elevated,
            isHighlighted: highlighted,
            cornerRadius: cornerRadius
        ))
    }

    /// Adds an accent glow.
    func jarvisGlow(
        _ color: Color = JarvisTheme.Palette.accent,
        radius: CGFloat = 14,
        opacity: Double = 0.35
    ) -> some View {
        modifier(JarvisGlow(color: color, radius: radius, opacity: opacity))
    }
}
