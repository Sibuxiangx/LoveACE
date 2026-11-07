import SwiftUI

/// iPad 横屏（侧栏布局）时为 true，由 AdaptiveRootView 注入。
/// 子页面据此选择双栏或分栏；竖屏和 iPhone 保持单列。
private struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

extension View {
    /// 限制内容的阅读宽度并居中。内容宽度不足时不起作用（iPhone 竖屏）。
    func readableWidth(_ maxWidth: CGFloat) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}
