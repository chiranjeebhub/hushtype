import AppKit
import SwiftUI

// Building blocks for the Settings window: quiet cards with hairline borders, monochrome glyphs,
// and Hushtype violet as the one accent.

extension Color {
    static let hushViolet = Color(red: 0.55, green: 0.47, blue: 1.0)
    static let hushIndigo = Color(red: 0.23, green: 0.18, blue: 0.66)
    /// The cursor in the app icon.
    static let hushMint = Color(red: 0.49, green: 0.94, blue: 0.77)
}

extension Color {
    /// The window's ground: a deep, slightly violet charcoal in dark mode, the system window
    /// colour in light mode.
    static let settingsBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.11, green: 0.105, blue: 0.125, alpha: 1)
            : NSColor.windowBackgroundColor
    })
}

extension ShapeStyle where Self == LinearGradient {
    /// The app icon's indigo, for the few places that carry the brand.
    static var hushBrand: LinearGradient {
        LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1.0), .hushIndigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Page structure

/// One settings pane: a large title, a sentence saying what the pane is for, then its sections.
struct SettingsPage<Content: View>: View {
    let pane: SettingsPane
    /// Home opens straight on its hero instead of a title.
    var showsHeader = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pane.title)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                    Text(pane.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 22)
                }
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// The quiet rounded button used throughout Settings, in place of the system's tinted one.
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return configuration.label
            .font(small ? .caption : .callout)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, small ? 9 : 11)
            .padding(.vertical, small ? 3 : 5)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
}

/// A small uppercase heading above a card, with optional text on the right.
struct SectionLabel<Trailing: View>: View {
    let title: String
    /// The first thing on a page sits right under the page header.
    var isFirst = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            Spacer()
            trailing.font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.top, isFirst ? 0 : 24)
        .padding(.bottom, 8)
        .padding(.horizontal, 2)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String, isFirst: Bool = false) {
        self.init(title: title, isFirst: isFirst) { EmptyView() }
    }
}

/// The rounded surface every group of rows sits on, with hairlines between rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        Divider().opacity(0.6).padding(.horizontal, 16)
                    }
                    subview
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

extension View {
    /// The card fill and hairline border, optionally lit in the accent.
    func cardSurface(cornerRadius: CGFloat = 12, highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(highlighted ? Color.hushViolet.opacity(0.08) : Color.primary.opacity(0.035)))
            .overlay(shape.strokeBorder(highlighted ? Color.hushViolet.opacity(0.6) : Color.primary.opacity(0.08),
                                        lineWidth: highlighted ? 1 : 0.5))
    }
}

// MARK: - Rows

/// A monochrome symbol in a soft square, leading a row. `brand` fills it with the app's gradient.
struct Glyph: View {
    let symbol: String
    var brand = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Icon(symbol, size: 15)
            .foregroundStyle(brand ? Color.hushMint : Color.primary)
            .frame(width: 28, height: 28)
            .background {
                if brand { shape.fill(.hushBrand) } else { shape.fill(Color.primary.opacity(0.06)) }
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(brand ? 0 : 0.08), lineWidth: 0.5))
            .shadow(color: brand ? Color.hushViolet.opacity(0.35) : .clear, radius: 6, y: 3)
    }
}

/// A row with an optional glyph, a title, a short subtitle, an ⓘ for the long explanation, and a
/// control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var info: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { Glyph(symbol: symbol) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if let info { InfoButton(text: info) }
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

/// A settings row whose control is a switch.
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var info: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, symbol: symbol, info: info) {
            Toggle(title, isOn: $isOn.animation(.easeInOut(duration: 0.2)))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// An ⓘ that shows a longer explanation in a popover, and as a tooltip on hover.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Icon("info", size: 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help(text)
        .accessibilityLabel("More information")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
    }
}

/// A tinted note with an action, for advice that only applies to the current choice.
struct Callout<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            Icon(symbol, size: 17).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action.controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }
}

/// A green "Allowed"-style status pill.
struct StatusPill: View {
    let text: String
    var color: Color = .green
    var symbol = "checkmark"

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.5))
    }
}

// MARK: - Keys

extension TriggerKey {
    var keyGlyph: String {
        switch self {
        case .fn: return "🌐"
        case .rightOption: return "⌥"
        case .rightCommand: return "⌘"
        }
    }

    var keyCaption: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "option"
        case .rightCommand: return "command"
        }
    }

    var choiceName: String {
        switch self {
        case .fn: return "Fn / Globe"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        }
    }

    var choiceHint: String {
        switch self {
        case .fn: return "Bottom-left key"
        case .rightOption: return "Recommended"
        case .rightCommand: return "Right of the space bar"
        }
    }

    /// How the key is named in a sentence: "Hold Right ⌥ to talk".
    var shortName: String {
        switch self {
        case .fn: return "Fn"
        case .rightOption: return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        }
    }
}

/// A large, physical-looking keycap.
struct BigKeycap: View {
    let glyph: String
    let caption: String
    var glowing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        VStack(spacing: 0) {
            Text(glyph).font(.system(size: 20))
            Text(caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .frame(width: 64, height: 54)
        .background(shape.fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.24)],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.03)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.55), radius: 0, y: 3)
        .shadow(color: glowing ? Color.hushViolet.opacity(0.4) : .black.opacity(0.25), radius: glowing ? 10 : 7,
                y: glowing ? 0 : 5)
    }
}

/// A small keycap for shortcut hints.
struct KeyChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.31), Color(white: 0.23)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1.5)
    }
}

/// A choosable dictation key: keycap, name and hint, lit in violet when selected.
struct KeyChoiceTile: View {
    let key: TriggerKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                BigKeycap(glyph: key.keyGlyph, caption: key.keyCaption, glowing: selected)
                VStack(spacing: 2) {
                    Text(key.choiceName).font(.callout.weight(.medium))
                    Text(key.choiceHint).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .cardSurface(cornerRadius: 14, highlighted: selected)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Layout

/// Lays children out left to right, wrapping onto new lines, like tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
