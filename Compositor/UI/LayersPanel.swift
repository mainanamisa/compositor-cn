import SwiftUI

struct LayersPanel: View {
    @Bindable var session: EditorSession
    /// Dragging the panel's left edge sets it, within `widths`.
    var width: CGFloat = 252
    static let widths: ClosedRange<Double> = 202...352

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("图层").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(session.document?.layers.count ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    .accessibilityIdentifier("layerCount")
            }.padding(18)
            Divider()
            LayerAppearanceControls(session: session, layerID: session.activeLayerID).id(session.activeLayerID)
            Divider()
            if let layers = session.document?.layers, !layers.isEmpty {
                NativeLayerList(session: session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 25, weight: .light))
                    Text("还没有图层").font(.callout.weight(.medium))
                    Text(session.document == nil ? "创建画布或导入图像。" : "导入图像或添加空白图层。")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            // No spacing: each button's hit area supplies it (8 pt either side makes the 16 pt gap).
            HStack(spacing: 0) {
                Button { session.addBlankLayer() } label: { FooterIcon(systemName: "plus.square") }
                    .help("新建空白图层（⇧⌘N）").accessibilityLabel("新建空白图层")
                    .accessibilityIdentifier("addBlankLayer").disabled(!session.layersLookEditable)
                Button { session.groupSelectedLayers() } label: { FooterIcon(systemName: "folder.badge.plus") }
                    .help("将所选图层编组（⌘G）").accessibilityLabel("新建组").disabled(!session.layersLookEditable)
                LayerMaskMenu(session: session)
                Menu {
                    ForEach(LayerEffectKind.allCases, id: \.self) { kind in
                        Button(kind.displayName + "…") { session.addEffect(kind) }
                    }
                } label: { Image(systemName: "sparkles").footerHitArea() }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("添加图层效果").accessibilityLabel("图层效果")
                    .accessibilityIdentifier("layerEffects").disabled(!session.layersLookEditable || session.activeLayer?.isGroup != false || session.activeLayer?.asset == nil)
                Menu {
                    ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { session.addAdjustment(kind) }
                    }
                } label: { Image(systemName: "circle.lefthalf.filled").footerHitArea() }
                    .menuStyle(.borderlessButton).fixedSize().help("新建调整图层").disabled(!session.layersLookEditable)
                Spacer()
                Button { session.deleteLayerOrMask() } label: { FooterIcon(systemName: "trash") }
                    .help(session.selectedEffect != nil ? "删除所选效果" : session.isMaskSelected ? "删除图层蒙版" : session.selectedLayerIDs.count > 1 ? "删除选中的多个图层" : "删除所选图层")
                    .accessibilityLabel(session.selectedEffect != nil ? "删除所选效果" : session.isMaskSelected ? "删除图层蒙版" : session.selectedLayerIDs.count > 1 ? "删除选中的多个图层" : "删除所选图层")
                    .accessibilityIdentifier("deleteLayer")
                    .disabled(!session.layersLookEditable || session.activeLayer == nil)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4) // Plus the hit areas' 8 and 12: the original 16.

        }
        .frame(width: width)
        .task(id: session.adjustmentEditingID) {
            if let id = session.adjustmentEditingID { await session.beginAdjustmentEditing(id) }
        }
    }

}

/// A footer button's icon: full strength when the button can be used, and as dim as the footer's menus (Effects,
/// Adjustments) when it can't. A plain button with its own color doesn't dim when disabled, so the footer looked
/// uneven, some disabled icons barely fading and others nearly gone.
struct FooterIcon: View {
    let systemName: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        // Disabled, as dim as the menus' icons (a quarter-strength white, measured): SwiftUI halves a disabled
        // button's own color again, so the button asks for half-strength white.
        Image(systemName: systemName)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white.opacity(0.5)))
            .footerHitArea()
    }
}

extension View {
    /// Makes a small footer icon easier to click. The padding is the clickable area, so the
    /// footer's own spacing is reduced to match and every icon keeps its old position.
    /// (Negative padding to hand the space back does not work: the button then only answers
    /// clicks inside its shrunken frame.)
    func footerHitArea() -> some View {
        padding(.horizontal, 8).padding(.vertical, 12)
            .contentShape(Rectangle())
    }
}

