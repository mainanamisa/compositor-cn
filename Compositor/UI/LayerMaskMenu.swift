import SwiftUI

/// Adds a mask in one click, as Photoshop's button does: all white, or with a selection, revealing just the
/// selection. Option-click adds the opposite: all black, or hiding the selection.
/// Enable/Disable and Delete live in the layer's context menu.
struct LayerMaskMenu: View {
    let session: EditorSession
    var body: some View {
        Button {
            session.addMask(revealing: NSApp.currentEvent?.modifierFlags.contains(.option) != true)
        } label: { Image(systemName: "rectangle.inset.filled").footerHitArea() }
            .buttonStyle(.borderless)
            .help(session.selection == nil ? "添加图层蒙版（Option 点击添加黑色蒙版）"
                  : "添加显示选区的图层蒙版（Option 点击隐藏选区）")
            .accessibilityLabel("添加图层蒙版")
            .disabled(!session.canEditMask || session.activeLayer?.mask != nil)
    }
}

/// Over the canvas while it shows a mask by itself: whose mask it is, and a way back to the composite besides
/// Option-clicking the thumbnail again. Built in AppKit, as the canvas under it is, so its button gets its clicks.
struct MaskAloneBadge: NSViewRepresentable {
    let session: EditorSession
    let layer: ImageLayer
    func makeNSView(context: Context) -> MaskAloneBadgeView {
        MaskAloneBadgeView { [session] in session.viewsMaskAlone = false }
    }
    func updateNSView(_ view: MaskAloneBadgeView, context: Context) { view.layerName = layer.name }
}

final class MaskAloneBadgeView: NSView {
    var layerName = "" { didSet { name.stringValue = layerName; invalidateIntrinsicContentSize() } }
    private let name = NSTextField(labelWithString: "")
    private let stack: NSStackView
    private let close: () -> Void

    init(close: @escaping () -> Void) {
        self.close = close
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        let title = NSTextField(labelWithString: "图层蒙版")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white
        name.font = .systemFont(ofSize: 12)
        name.textColor = NSColor.white.withAlphaComponent(0.6)
        name.lineBreakMode = .byTruncatingTail
        let button = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "停止查看蒙版") ?? NSImage(),
                              target: nil, action: nil)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        button.toolTip = "重新显示图像（或 Option 点击蒙版缩略图）"
        stack = NSStackView(views: [icon, title, name, button])
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 8)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(closeClicked)
        icon.contentTintColor = .white
        button.contentTintColor = .white
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor), heightAnchor.constraint(equalToConstant: 26),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: stack.fittingSize.width, height: 26) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func closeClicked() { close() }
}
