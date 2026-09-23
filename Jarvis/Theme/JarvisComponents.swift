//
//  JarvisComponents.swift
//  JARVIS
//
//  Reusable presentation components shared by the dashboard and the
//  feature screens. Keeping them here avoids duplicated styling logic
//  and keeps individual views focused on layout.
//

import SwiftUI

// MARK: - Card container

/// A titled card with an optional trailing accessory view.
struct JarvisCard<Content: View, Accessory: View>: View {
    let title: String
    let symbolName: String?
    let isElevated: Bool
    let isHighlighted: Bool
    let padding: CGFloat
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        symbolName: String? = nil,
        isElevated: Bool = false,
        isHighlighted: Bool = false,
        padding: CGFloat = JarvisTheme.Spacing.loose,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbolName = symbolName
        self.isElevated = isElevated
        self.isHighlighted = isHighlighted
        self.padding = padding
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.accent)
                }
                Text(title)
                    .font(JarvisTheme.Typography.title(15))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Spacer(minLength: JarvisTheme.Spacing.tight)
                accessory
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(elevated: isElevated, highlighted: isHighlighted)
    }
}

extension JarvisCard where Accessory == EmptyView {
    init(
        title: String,
        symbolName: String? = nil,
        isElevated: Bool = false,
        isHighlighted: Bool = false,
        padding: CGFloat = JarvisTheme.Spacing.loose,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            symbolName: symbolName,
            isElevated: isElevated,
            isHighlighted: isHighlighted,
            padding: padding,
            content: content,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Small pieces

/// Uppercase caption used above grouped content.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(JarvisTheme.Typography.caption(10))
            .tracking(1.1)
            .foregroundStyle(JarvisTheme.Palette.textTertiary)
    }
}

/// Small rounded status chip with an optional symbol.
struct StatusChip: View {
    let text: String
    var symbolName: String?
    var tint: Color = JarvisTheme.Palette.accent

    var body: some View {
        HStack(spacing: 5) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(JarvisTheme.Typography.caption(10))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

/// Circular progress ring used by the focus timer and homework progress.
struct RingProgress: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = JarvisTheme.Palette.accent

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(JarvisTheme.Palette.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    AngularGradient(
                        colors: [tint, tint.opacity(0.65), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .jarvisGlow(tint, radius: 8, opacity: 0.4)
        }
    }
}

/// Horizontal metric bar with a label, a value caption, and a ratio.
struct MetricBar: View {
    let label: String
    let valueText: String
    let fraction: Double
    var tint: Color = JarvisTheme.Palette.accent

    private var clamped: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
                Spacer(minLength: 6)
                Text(valueText)
                    .font(JarvisTheme.Typography.caption(11))
                    .monospacedDigit()
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(JarvisTheme.Palette.stroke.opacity(0.7))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.8), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, proxy.size.width * clamped))
                        .jarvisGlow(tint, radius: 6, opacity: 0.35)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Placeholder used when a list has no content.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: JarvisTheme.Spacing.tight) {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
            Text(title)
                .font(JarvisTheme.Typography.headline(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
            if let message {
                Text(message)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JarvisTheme.Spacing.loose)
    }
}

/// Square icon button used for row level actions.
struct IconActionButton: View {
    let symbolName: String
    var tint: Color = JarvisTheme.Palette.accent
    var helpText: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(helpText ?? "")
    }
}

/// Colored dot with a soft glow, used for status indicators.
struct StatusDot: View {
    var color: Color = JarvisTheme.Palette.success
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .jarvisGlow(color, radius: 6, opacity: 0.6)
    }
}

// MARK: - Button styles

/// Filled accent button used for primary actions.
struct JarvisPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTheme.Typography.headline(12))
            .foregroundStyle(JarvisTheme.Palette.canvas)
            .padding(.horizontal, JarvisTheme.Spacing.regular)
            .padding(.vertical, 9)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .fill(JarvisTheme.accentGradient)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .jarvisGlow(radius: configuration.isPressed ? 6 : 14, opacity: 0.32)
    }
}

/// Quiet outlined button used for secondary actions.
struct JarvisSecondaryButtonStyle: ButtonStyle {
    var tint: Color = JarvisTheme.Palette.accent
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTheme.Typography.headline(12))
            .foregroundStyle(tint)
            .padding(.horizontal, JarvisTheme.Spacing.regular)
            .padding(.vertical, 9)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }
}

/// Destructive outlined button.
struct JarvisDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTheme.Typography.headline(12))
            .foregroundStyle(JarvisTheme.Palette.danger)
            .padding(.horizontal, JarvisTheme.Spacing.regular)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .fill(JarvisTheme.Palette.danger.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .strokeBorder(JarvisTheme.Palette.danger.opacity(0.32), lineWidth: 1)
            )
    }
}

extension ButtonStyle where Self == JarvisPrimaryButtonStyle {
    /// Filled accent button style.
    static var jarvisPrimary: JarvisPrimaryButtonStyle { JarvisPrimaryButtonStyle() }
    /// Filled accent button style stretched to the available width.
    static var jarvisPrimaryWide: JarvisPrimaryButtonStyle { JarvisPrimaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == JarvisSecondaryButtonStyle {
    /// Quiet outlined button style.
    static var jarvisSecondary: JarvisSecondaryButtonStyle { JarvisSecondaryButtonStyle() }
    /// Quiet outlined button style stretched to the available width.
    static var jarvisSecondaryWide: JarvisSecondaryButtonStyle {
        JarvisSecondaryButtonStyle(fullWidth: true)
    }
}

extension ButtonStyle where Self == JarvisDangerButtonStyle {
    /// Destructive action button style.
    static var jarvisDanger: JarvisDangerButtonStyle { JarvisDangerButtonStyle() }
}

// MARK: - Text field styling

/// Rounded dark text field background matching the card surfaces.
struct JarvisFieldBackground: ViewModifier {
    var isFocused: Bool = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(JarvisTheme.Typography.body(13))
            .foregroundStyle(JarvisTheme.Palette.textPrimary)
            .padding(.horizontal, JarvisTheme.Spacing.regular)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .fill(JarvisTheme.Palette.canvas.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? JarvisTheme.Palette.accent.opacity(0.5)
                            : JarvisTheme.Palette.stroke,
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    /// Applies the standard JARVIS text field chrome.
    func jarvisField(focused: Bool = false) -> some View {
        modifier(JarvisFieldBackground(isFocused: focused))
    }
}
