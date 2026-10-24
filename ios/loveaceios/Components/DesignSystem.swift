import SwiftUI

// MARK: - App Gradients

enum AppGradient {
    static let gpa = LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let courses = LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let balance = LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let electricity = LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let credits = LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let danger = LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let semester = LinearGradient(colors: [.blue, .cyan, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Typography

enum AppFont {
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let heroNumber = Font.system(size: 52, weight: .bold, design: .rounded)
    static let largeNumber = Font.system(size: 36, weight: .bold, design: .rounded)
    static let mediumNumber = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let cardValue = Font.system(size: 22, weight: .bold, design: .rounded)
}

// MARK: - Course Colors

let courseColorPalette: [Color] = [
    Color(red: 0.20, green: 0.55, blue: 0.95),
    Color(red: 0.18, green: 0.72, blue: 0.47),
    Color(red: 0.90, green: 0.50, blue: 0.15),
    Color(red: 0.85, green: 0.30, blue: 0.45),
    Color(red: 0.35, green: 0.65, blue: 0.75),
    Color(red: 0.60, green: 0.40, blue: 0.80),
    Color(red: 0.25, green: 0.70, blue: 0.65),
    Color(red: 0.80, green: 0.60, blue: 0.25),
    Color(red: 0.55, green: 0.55, blue: 0.85),
    Color(red: 0.70, green: 0.35, blue: 0.30),
]

// MARK: - Compat Glass Modifier

extension View {
    @ViewBuilder
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if interactive, let tint {
                self.glassEffect(.regular.interactive().tint(tint), in: .capsule)
            } else if let tint {
                self.glassEffect(.regular.tint(tint), in: .capsule)
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular, in: .capsule)
            }
        } else {
            self.background(.regularMaterial, in: .capsule)
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(.regularMaterial, in: .circle)
        }
    }

    @ViewBuilder
    func glassInteractiveCard(tint: Color? = nil, cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            if let tint {
                self.glassEffect(.regular.interactive().tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Compat Scroll Modifiers

extension View {
    @ViewBuilder
    func compatScrollTransition() -> some View {
        if #available(iOS 17, *) {
            self.scrollTransition(.animated(.snappy)) { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                    .opacity(phase.isIdentity ? 1.0 : 0.5)
                    .blur(radius: phase.isIdentity ? 0 : 1)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func compatScrollTargetLayout() -> some View {
        if #available(iOS 17, *) {
            self.scrollTargetLayout()
        } else {
            self
        }
    }

    @ViewBuilder
    func compatScrollTargetBehavior() -> some View {
        if #available(iOS 17, *) {
            self.scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }
    /// iOS 26 液态玻璃主按钮；低版本回退为 borderedProminent。
    @ViewBuilder
    func compatGlassProminentButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Compat Glass Container

struct CompatGlassContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
    }
}

// MARK: - Glass Stat Card

struct GlassStatCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint.gradient)
            Text(value)
                .font(AppFont.cardValue)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint.opacity(0.15))
    }
}

// MARK: - Glass Badge

struct GlassBadge: View {
    let text: String
    var tint: Color = .blue
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassCapsule(tint: tint.opacity(0.3))
    }
}

// MARK: - Glass Progress Ring

struct GlassProgressRing: View {
    let progress: Double
    var size: CGFloat = 100
    var lineWidth: CGFloat = 8
    var tint: Color = .blue
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(AppFont.metric(size * 0.22))
                    .foregroundStyle(.primary)
                if let label {
                    Text(label)
                        .font(.system(size: size * 0.1))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(4)
        .glassCircle()
    }
}

// MARK: - Glass Section Header

struct GlassSectionHeader: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Score Color Helper

func scoreColor(for score: String) -> Color {
    guard let num = Double(score) else { return .primary }
    if num >= 90 { return .green }
    if num >= 80 { return .blue }
    if num >= 70 { return .orange }
    if num >= 60 { return .yellow }
    return .red
}
