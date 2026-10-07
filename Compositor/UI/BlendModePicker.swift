import SwiftUI
import AppKit

struct BlendModePicker: NSViewRepresentable {
    let session: EditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        // Grouped as Photoshop groups them — darkening, lightening, contrast, comparative, component —
        // with a line between, so a long list stays readable.
        for (index, group) in LayerBlendMode.groups.enumerated() {
            if index > 0 { button.menu?.addItem(.separator()) }
            for mode in group { button.addItem(withTitle: Self.title(for: mode)) }
        }
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel("混合模式")
        // A capsule like the SwiftUI buttons and menus (`roundedControls`), which don't reach this AppKit pop-up.
        button.borderShape = .capsule
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = session.canEditAppearance
        if !context.coordinator.tracking {
            button.selectItem(withTitle: Self.title(for: session.activeLayer?.blendMode ?? .normal))
        }
    }
    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        if coordinator.tracking { coordinator.session.previewBlendMode(nil, for: nil) }
        button.menu?.delegate = nil
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        let session: EditorSession
        var tracking = false
        private var layerID: UUID?
        private var highlightedMode: LayerBlendMode?
        init(session: EditorSession) { self.session = session }
        func menuWillOpen(_ menu: NSMenu) {
            tracking = true
            layerID = session.activeLayerID
            highlightedMode = nil
        }
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            // AppKit briefly reports no highlighted item while dismissing the menu.
            // Keep the last preview alive until the selection action has committed so
            // the canvas never flashes back to the layer's previous mode.
            guard let mode = item.flatMap({ BlendModePicker.mode(forTitle: $0.title) }) else { return }
            highlightedMode = mode
            session.previewBlendMode(mode, for: layerID)
        }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            // A chosen item's action runs as the menu finishes closing. Clearing on the
            // next turn lets that action replace the preview with the committed mode;
            // when the menu was cancelled, this simply restores the original mode.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.tracking else { return }
                self.session.previewBlendMode(nil, for: nil)
            }
        }
        @objc func choose(_ button: NSPopUpButton) {
            guard session.activeLayerID == layerID,
                  let mode = highlightedMode ?? button.selectedItem.flatMap({ BlendModePicker.mode(forTitle: $0.title) }) else { return }
            session.setLayerBlendMode(mode)
            button.selectItem(withTitle: BlendModePicker.title(for: mode))
            highlightedMode = nil
            session.refreshCanvasPreview?()
        }
    }

    /// Chinese menu titles. The raw values stay English: `LayerBlendMode` is Codable and written
    /// into project files, so only the display text is translated here.
    static func title(for mode: LayerBlendMode) -> String {
        switch mode {
        case .normal: return "正常"
        case .darken: return "变暗"
        case .multiply: return "正片叠底"
        case .colorBurn: return "颜色加深"
        case .linearBurn: return "线性加深"
        case .lighten: return "变亮"
        case .screen: return "滤色"
        case .colorDodge: return "颜色减淡"
        case .linearDodge: return "线性减淡（添加）"
        case .overlay: return "叠加"
        case .softLight: return "柔光"
        case .hardLight: return "强光"
        case .vividLight: return "亮光"
        case .linearLight: return "线性光"
        case .pinLight: return "点光"
        case .hardMix: return "实色混合"
        case .difference: return "差值"
        case .exclusion: return "排除"
        case .subtract: return "减去"
        case .divide: return "划分"
        case .hue: return "色相"
        case .saturation: return "饱和度"
        case .color: return "颜色"
        case .luminosity: return "明度"
        }
    }
    static func mode(forTitle title: String) -> LayerBlendMode? {
        LayerBlendMode.allCases.first { self.title(for: $0) == title }
    }
}
