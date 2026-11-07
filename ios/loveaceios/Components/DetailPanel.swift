import SwiftUI

// MARK: - 列表详情面板
//
// 列表页的详情：iPad 横屏显示在右侧 inspector，列表保持可见，切换条目时面板内容跟着换；
// 竖屏与 iPhone 保持 sheet。两种形式的关闭动作统一用 `@DetailDismiss`。

/// 横屏 inspector 的关闭动作。inspector 不是 presentation，`dismiss` 不能保证关闭它，由修饰器注入。
private struct DetailCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private extension EnvironmentValues {
    var detailClose: (() -> Void)? {
        get { self[DetailCloseKey.self] }
        set { self[DetailCloseKey.self] = newValue }
    }
}

/// 详情面板里的关闭动作，用法与 `@Environment(\.dismiss)` 相同：`dismiss()`。
/// 横屏 inspector 里清除当前 item；sheet 里调用系统 dismiss。
@propertyWrapper
struct DetailDismiss: DynamicProperty {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.detailClose) private var detailClose

    var wrappedValue: () -> Void {
        let close = detailClose
        let systemDismiss = dismiss
        return {
            if let close {
                close()
            } else {
                systemDismiss()
            }
        }
    }
}

extension View {
    /// 列表详情。`item` 非 nil 时展示 `panel(item)`。
    /// 横屏：右侧 inspector；竖屏与 iPhone：sheet。两种形式关闭时都会调用 `onDismiss`。
    func detailPanel<Item: Identifiable, Panel: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder panel: @escaping (Item) -> Panel
    ) -> some View {
        modifier(DetailPanelModifier(item: item, onDismiss: onDismiss, makePanel: panel))
    }
}

private struct DetailPanelModifier<Item: Identifiable, Panel: View>: ViewModifier {
    @Environment(\.wideLayout) private var wideLayout
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let makePanel: (Item) -> Panel

    @ViewBuilder
    func body(content: Content) -> some View {
        if wideLayout {
            content
                .inspector(isPresented: isPresented) {
                    if let item {
                        makePanel(item)
                            .id(item.id)
                            .environment(\.detailClose, { close() })
                    }
                }
                .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
        } else {
            content.sheet(item: $item, onDismiss: onDismiss) { makePanel($0) }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { item != nil },
            set: { if !$0 { close() } }
        )
    }

    private func close() {
        guard item != nil else { return }
        item = nil
        onDismiss?()
    }
}
