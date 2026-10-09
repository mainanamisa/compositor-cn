import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// The Layers panel's width, remembered across launches.
    @AppStorage("layersPanelWidth") private var layersPanelWidth = 252.0
    /// The tool last chosen within the rail's repair group (Spot Healing / Remove / Clone Stamp), so its slot
    /// keeps showing it, as Photoshop's grouped tools do.
    @AppStorage("repairTool") private var lastRepairTool = NavigationTool.spotHealing.rawValue
    /// Same for the navigation group (Hand / Zoom).
    @AppStorage("navigationTool") private var lastNavigationTool = NavigationTool.hand.rawValue
    @Bindable var session: EditorSession
    var applicationDelegate: CompositorApplicationDelegate? = nil
    @Environment(\.openWindow) private var openWindow
    @State private var canvasFrame: CGRect = .zero
    @State private var levelsPanel = FloatingPanelController(name: "levelsPanel")
    @State private var adjustmentPanel = FloatingPanelController(name: "adjustmentPanel")
    @State private var selectionAmountPanel = FloatingPanelController(name: "selectionAmountPanel")
    @State private var colorRangePanel = FloatingPanelController(name: "colorRangePanel")
    @State private var filterPanel = FloatingPanelController(name: "filterPanel")
    @State private var effectsPanel = FloatingPanelController(name: "effectsPanel")
    @State private var isDropTargeted = false
    /// The window's width, so the tab strip can use the toolbar's free space.
    @State private var windowWidth: CGFloat = 1180
    /// A layer dragged from this canvas's own tab has nowhere to go, so the canvas doesn't light up for it.
    private var acceptsDrop: Bool {
        guard let workspace = applicationDelegate?.workspace else { return true }
        return workspace.canReceiveDrag(into: workspace.current.id)
    }
    // Extracted from `body`: as one expression the type checker times out (Xcode 26.1).
    @ViewBuilder private var toolHeaders: some View {
        Group {
            if session.tool == .move {
                TransformInspector(session: session).id(session.activeLayerID)
                Divider()
            }
            if session.tool.isBrushTool {
                BrushControls(session: session)
                Divider()
            }
            if session.tool.isSelectionTool {
                LassoControls(session: session)
                Divider()
            }
            if session.tool == .gradient {
                GradientControls(session: session)
                Divider()
            }
            if session.tool == .type {
                TypeControls(session: session)
                Divider()
            }
            if session.tool == .shape {
                ShapeControls(session: session)
                Divider()
            }
            if session.tool == .eyedropper {
                HStack(spacing: 16) {
                    Text("吸管").font(ToolHeaderStyle.titleFont)
                    Toggle("取样环", isOn: $session.showsSampleRing).toggleStyle(.checkbox)
                    Spacer()
                }.padding(.horizontal, 18).toolHeaderBar()
                Divider()
            }
            if session.tool == .hand || session.tool == .zoom {
                NavigationToolHeader(session: session)
                Divider()
            }
            if session.tool == .crop {
                CropControls(session: session)
                Divider()
            }
            // No tool (A) keeps the header, so the canvas doesn't jump.
            if session.tool == .idle {
                HStack(spacing: 16) {
                    Text("请选择工具").font(ToolHeaderStyle.titleFont)
                    Spacer()
                }.padding(.horizontal, 18).toolHeaderBar()
                Divider()
            }
        }
    }

    @ViewBuilder private var editorStack: some View {
        VStack(spacing: 0) {
            if !session.canvasOnly { toolHeaders }
            HStack(spacing: 0) {
                if !session.canvasOnly {
                    toolRail
                    Divider()
                }
                VStack(spacing: 0) {
                    if session.showsRulers, session.document != nil, !session.canvasOnly {
                        HStack(spacing: 0) {
                            CanvasRulerCorner()
                            CanvasRulerView(session: session, axis: .horizontal)
                                .frame(height: CanvasRuler.thickness)
                        }
                    }
                    HStack(spacing: 0) {
                        if session.showsRulers, session.document != nil, !session.canvasOnly {
                            CanvasRulerView(session: session, axis: .vertical)
                                .frame(width: CanvasRuler.thickness)
                        }
                        ZStack {
                            EditorCanvas(session: session)
                            if session.document == nil { welcome }
                            if let layer = session.maskAloneLayer {
                                // At the foot of the canvas, clear of the transform box's rotation handle.
                                MaskAloneBadge(session: session, layer: layer).fixedSize()
                                    .padding(.bottom, 14)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("editor")) } action: { canvasFrame = $0 }
                    }
                }
                if !session.canvasOnly {
                    PanelResizeEdge(width: $layersPanelWidth, range: LayersPanel.widths)
                    LayersPanel(session: session, width: layersPanelWidth)
                }
            }
            if !session.canvasOnly {
                Divider()
                // Keeps its own height however short the window gets; the tools scroll instead.
                statusBar.fixedSize(horizontal: false, vertical: true)
                    .modifier(WidthReader(width: $windowWidth))
            }
        }
    }

    // Split again for 1.1: the chain outgrew the type checker once more.
    @ViewBuilder private var editorChrome: some View {
        editorStack
        .background(Color(white: 0.14))
        .background {
            if let applicationDelegate, applicationDelegate.projects.workspace == nil {
                ProjectWindowBridge(controller: applicationDelegate.projects).frame(width: 0, height: 0)
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .coordinateSpace(name: "editor")
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, ProjectWorkspace.layerType], isTargeted: $isDropTargeted) { providers, location in
            guard session.levels == nil, !session.isProjectBusy, !session.showsNewDocument, !session.showsImporter, session.renamingLayerID == nil else { return false }
            let point: CGPoint?
            if let document = session.document, canvasFrame.contains(location) {
                point = session.viewport.documentPoint(
                    from: CGPoint(x: location.x - canvasFrame.minX, y: location.y - canvasFrame.minY),
                    documentSize: document.size)
            } else { point = nil }
            if let workspace = applicationDelegate?.workspace {
                let destination = workspace.current.id
                guard workspace.canSwitch, workspace.canReceiveDrag(into: destination) else { return false }
                Task { await workspace.receiveProviders(providers, into: destination, at: point) }
            } else {
                Task { await ImageFileDrop.importProviders(providers, into: session, at: point) }
            }
            return true
        }
        .overlay {
            if isDropTargeted, acceptsDrop {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: max(0, canvasFrame.width - 6), height: max(0, canvasFrame.height - 6))
                    .position(x: canvasFrame.midX, y: canvasFrame.midY)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { applicationDelegate?.showEditor = { openWindow(id: "editor") } }
        .preferredColorScheme(.dark)
        // Canvas Only (F): the canvas runs up under where the title bar was, so no gray strip is left across the top.
        // The toolbar itself is hidden and shown by the window (see `toggleCanvasOnly`), which lays its buttons out
        // again properly; hidden here instead, it came back with the tabs over the window buttons.
        .ignoresSafeArea(.container, edges: session.canvasOnly ? .top : [])
        .navigationTitle(session.projectURL?.deletingPathExtension().lastPathComponent ?? "未命名")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { requestNewCanvas() } label: { Label("新建画布", systemImage: "plus") }
                    .help("新建画布 (⌘N)").accessibilityIdentifier("newCanvasToolbar")
                    .disabled(session.isImporting || session.showsBusy || session.levels != nil)
                    .modifier(NewProjectDropTarget(workspace: applicationDelegate?.workspace))
            }
            ToolbarSpacer(.fixed, placement: .navigation)
            if let workspace = applicationDelegate?.workspace {
                ToolbarItem(placement: .navigation) {
                    ProjectTabStrip(workspace: workspace)
                        // As wide as the toolbar allows: the window less the traffic lights and New button before it
                        // and the zoom controls after it. Bounded, so adding tabs never pushes those aside; the
                        // strip scrolls instead.
                        .frame(width: max(200, windowWidth - 352), height: 34, alignment: .center)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            // Absorb all remaining navigation-toolbar width before the zoom controls.
            // Without this spacer, the growing tab strip pushes the primary actions left.
            ToolbarSpacer(.flexible, placement: .navigation)
            ToolbarItem(placement: .primaryAction) {
                Button("适应") { session.fit() }.help("使画布适应窗口 (⌘0)")
                    .accessibilityIdentifier("fitCanvas").disabled(session.document == nil)
                    .padding(.horizontal, 4)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("100%") { session.zoom(to: 1) }.help("实际像素 (⌘1)")
                    .accessibilityIdentifier("actualPixels").disabled(session.document == nil)
                    .padding(.horizontal, 4)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 0) {
                    Button { session.zoomKeyboard(by: 1) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }.help("放大 (⌘+)").disabled(session.document == nil)
                    Button { session.zoomKeyboard(by: -1) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }.help("缩小 (⌘−)").disabled(session.document == nil)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    var body: some View {
        editorChrome
        .onChange(of: session.levels == nil) { _, closed in
            if closed { levelsPanel.close() }
            else {
                levelsPanel.onClose = { session.cancelLevels() }
                levelsPanel.show(title: "色阶", content: LevelsSheet(session: session))
            }
        }
        .onChange(of: session.colorRange == nil) { _, closed in
            if closed { colorRangePanel.close() }
            else {
                colorRangePanel.onClose = { session.cancelColorRange() }
                colorRangePanel.show(title: "色彩范围", content: ColorRangeSheet(session: session))
            }
        }
        .onChange(of: session.hueSaturation == nil) { _, closed in
            if closed { adjustmentPanel.close() }
            else {
                adjustmentPanel.onClose = { session.cancelHueSaturation() }
                adjustmentPanel.show(title: "色相/饱和度", content: HueSaturationSheet(session: session))
            }
        }
        .onChange(of: session.effectsEditing) { _, selection in
            if let selection {
                effectsPanel.onClose = { session.finishEffectsEditing(commit: false) }
                effectsPanel.show(title: selection.kind.displayName, content: EffectsSheet(session: session, kind: selection.kind))
            } else { effectsPanel.close() }
        }
        .onChange(of: session.document?.layers) { _, layers in
            if let editing = session.effectsEditing,
               layers?.first(where: { $0.id == editing.layerID })?.effects?.contains(editing.kind) != true {
                if let picker = session.colorPicker, case .effect = picker.target { session.closeColorPicker(commit: false) }
                session.effectsEditing = nil
                session.effectsEditingOriginal = nil
            }
        }
        .onChange(of: session.selectionAmountOperation) { _, operation in
            if let operation {
                selectionAmountPanel.onClose = { session.selectionAmountOperation = nil }
                selectionAmountPanel.show(title: operation.displayName + "选区",
                    content: SelectionAmountSheet(session: session, operation: operation))
            } else { selectionAmountPanel.close() }
        }
        // Last Filter applies without the panel.
        .onChange(of: session.filterEdit == nil || session.filterEdit?.repeating == true) { _, closed in
            if closed { filterPanel.close() }
            else {
                filterPanel.onClose = { session.cancelFilter() }
                let placement: FloatingPanelPlacement = session.filterEdit?.kind == .cameraRaw ? .dockedToMainWindowRight : .automatic
                filterPanel.show(title: session.filterEdit?.kind.displayName ?? "滤镜", content: FilterSheet(session: session),
                                 placement: placement)
            }
        }
        .onChange(of: session.document == nil) { _, empty in
            if !empty { session.canvasFocusRequest += 1 }
        }
        .fileImporter(isPresented: $session.showsImporter,
                      allowedContentTypes: UTType.importableImages, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await session.importImages(urls) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { session.importError = error.localizedDescription }
            }
        }
        .alert("导入未能完成", isPresented: Binding(
            get: { session.importError != nil }, set: { if !$0 { session.importError = nil } })) {
                // No cancel role: an alert with only a cancel button gets a second OK of its own.
                Button("好") { session.importError = nil }
            } message: { Text(session.importError ?? "") }
        .alert("无法绘画", isPresented: Binding(get: { session.brushError != nil },
            set: { if !$0 { session.brushError = nil } })) {
                Button("好") { session.brushError = nil }
            } message: { Text(session.brushError ?? "") }
        .alert("无法裁剪", isPresented: Binding(get: { session.cropError != nil },
            set: { if !$0 { session.cropError = nil } })) {
                Button("好") { session.cropError = nil }
            } message: { Text(session.cropError ?? "") }
        .sheet(isPresented: Binding(get: { RemoveModelStore.shared.stage != nil },
            set: { if !$0 { RemoveModelStore.shared.cancel() } })) {
                RemoveModelSheet(store: RemoveModelStore.shared)
            }
    }
    private func requestNewCanvas() {
        if let applicationDelegate { Task { await applicationDelegate.projects.newCanvas() } }
        else { session.clearProject() }
    }
    private var toolRail: some View {
        // Scrolls when the window is too short for every tool, rather than pushing the bars above and below away.
        IndicatorlessScrollView {
        VStack(spacing: 10) {
            ForEach(Self.toolSlots) { slot in
                toolButton(slot)
            }
            ColorPaletteControls(session: session).padding(.top, 8)
        }
        .padding(.top, 16).padding(.bottom, 12)
        .frame(width: 56)
        }
        .frame(width: 56)
    }
    /// One rail slot; the button itself lives in ToolSlotButton so each slot owns the state of its
    /// long-press flyout. Clicking activates the group's tool in use; right-clicking or pressing and
    /// holding lists the group's modes and sibling tools, each with its key — the modes that used to
    /// hide behind Tab or Shift-key presses become visible choices.
    private func toolButton(_ slot: ToolSlot) -> some View {
        ToolSlotButton(session: session, slot: slot, representative: representativeTool(for: slot),
                       onSelect: { selectSlot(slot) }, onPick: { selectFlyout($0) })
    }
    /// What a slot's button shows and activates: the group's tool when it's in hand, else the group's last-used
    /// choice for the groups of distinct tools, else the group's default.
    private func representativeTool(for slot: ToolSlot) -> NavigationTool {
        if slot.tools.contains(session.tool) { return session.tool }
        if slot.tools.contains(.spotHealing) { return NavigationTool(rawValue: lastRepairTool) ?? .spotHealing }
        if slot.tools.contains(.hand) { return NavigationTool(rawValue: lastNavigationTool) ?? .hand }
        return slot.tools[0]
    }
    private func selectSlot(_ slot: ToolSlot) {
        let tool = representativeTool(for: slot)
        session.selectTool(tool)
        rememberGroupChoice(tool)
    }
    private func selectFlyout(_ item: ToolSlot.FlyoutItem) {
        session.selectTool(item.tool)
        // Only once the tool is in hand, as its own Tab or key would switch it.
        if session.tool == item.tool { item.setup(session) }
        rememberGroupChoice(item.tool)
    }
    private func rememberGroupChoice(_ tool: NavigationTool) {
        if tool == .spotHealing || tool == .remove || tool == .cloneStamp { lastRepairTool = tool.rawValue }
        if tool == .hand || tool == .zoom { lastNavigationTool = tool.rawValue }
    }
    private var welcome: some View {
        NewCanvasSheet(session: session,
            onCreate: { session.createNewProject(width: $0, height: $1, resolution: $2, background: $3) },
            onOpen: { Task { await applicationDelegate?.projects.open() } },
            onOpenRecent: { url in Task { await applicationDelegate?.projects.open(url) } })
    }
    private var statusBar: some View {
        HStack(spacing: 16) {
            if let document = session.document {
                Text(session.viewport.zoom, format: .percent.precision(.fractionLength(0...1)))
                    .frame(width: 62, alignment: .leading).accessibilityIdentifier("zoomStatus")
                Text("\(document.width) × \(document.height) px").accessibilityIdentifier("canvasDimensions")
                Text("sRGB · 透明")
            } else { Text("就绪") }
            Spacer()
            if session.showsBusy {
                ProgressView().controlSize(.mini)
                Text(session.busyLabel ?? "正在处理…")
            } else if session.isImporting {
                ProgressView().controlSize(.mini)
                Text("正在导入图像…")
            } else {
                Text(session.tool == .marquee ? (session.marqueeKind == .ellipse ? "拖出椭圆选区 · Shift 添加 · Option 减去 · 拖动中再按 Shift 为正圆 · 在选区内拖动可移动 · Delete 清除 · ⌘D 取消选择" : "拖出矩形选区 · Shift 添加 · Option 减去 · 拖动中再按 Shift 为正方形 · 在选区内拖动可移动 · ⌘拖动移动像素 · Delete 清除 · ⌘D 取消选择") : session.tool == .wand ? (session.wandMode == .object ? "单击对象以选中其轮廓 · Tab 切换魔棒 · Shift 添加 · Option 减去 · 在选区内拖动可移动 · ⌘拖动移动像素 · Delete 清除 · ⌘D 取消选择" : "单击以选中相近颜色 · Tab 切换对象选择 · Shift 添加 · Option 减去 · 在选区内拖动可移动 · ⌘拖动移动像素 · Delete 清除 · ⌘D 取消选择") : session.tool == .lasso ? (session.lassoKind == .freehand ? "拖动以创建选区 · 在选区内拖动可移动 · Shift 添加 · Option 减去 · Delete 清除 · ⌥⌫/⌘⌫ 填充 · ⌘D 取消选择" : "单击放置顶点 · 单击起点、双击或按 Enter 闭合 · Delete 删除顶点 · Escape 取消") : session.tool == .brush ? (session.brushMode == .erase ? "拖动以擦除" : "拖动以绘画") + " · [ ] 调整大小 · Shift-[ ] 调整硬度 · 1–0 不透明度 · Escape 取消 · 空格键平移" : session.tool == .blur ? (session.blurMode == .blur ? "拖动以柔化" : session.blurMode == .smudge ? "拖动以涂抹" : "拖动以推移像素") + " · [ ] 调整大小 · Shift-[ ] 调整硬度 · 1–0 强度 · 空格键平移" : session.tool == .cloneStamp ? "Option-单击设置取样源 · 拖动以仿制 · [ ] 调整大小 · Shift-[ ] 调整硬度 · 1–0 不透明度 · 空格键平移" : session.tool == .spotHealing ? "在瑕疵上拖动以修复 · [ ] 调整大小 · Shift-[ ] 调整硬度 · Escape 取消 · 空格键平移" : session.tool == .remove ? "在要移除的内容上涂抹，松开后自动补全 · [ ] 调整大小 · Escape 取消 · 空格键平移" : session.tool == .type ? "拖出文本框 · 单击文字进行编辑 · 拖动文本框手柄调整大小 · ⌘Return 完成 · Escape 取消" : session.tool == .shape ? "拖动以在新图层上绘制形状 · Shift \(session.shapeKind == .line ? "45°" : session.shapeKind == .rectangle ? "正方形" : "正圆") · Option 从中心绘制 · Shift-U 或 Tab 切换下一个形状 · Escape 取消 · 空格键平移" : session.tool == .gradient ? "拖动以绘制 · 拖动端点调整 · Shift 45° · 1–0 不透明度 · Enter 应用 · Escape 取消" : session.tool == .crop ? "拖动以裁剪 · Enter 应用 · Escape 取消 · 空格键平移" : session.tool == .move ? "拖动以移动 · 拖动手柄调整大小 · 拖动圆环旋转 · 1–0 图层不透明度 · 空格键平移" : session.tool == .hand ? "拖动以平移 · 双指捏合缩放" : session.tool == .idle ? "未选择工具 · 按工具对应的按键选择工具 · 空格键平移" : "单击放大 · Option-单击缩小 · 左右拖动平滑缩放 · 空格键平移")
            }
        }
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
        .padding(.horizontal, 18).frame(height: 30)
        .accessibilityElement(children: .contain)
    }
}

/// One slot in the tool rail: the tools it stands for, and the right-click flyout listing the group's modes
/// and sibling tools. A single-tool slot has no flyout.
private struct ToolSlot: Identifiable {
    struct FlyoutItem: Identifiable {
        let name: String
        let key: String
        let tool: NavigationTool
        /// The mode the item switches the tool to; a no-op for items that are just a sibling tool.
        var setup: (EditorSession) -> Void = { _ in }
        let isActive: (EditorSession) -> Bool
        var id: String { name }
    }
    let tools: [NavigationTool]
    let flyout: [FlyoutItem]
    var id: String { tools.map(\.rawValue).joined() }
}

/// One button in the tool rail: activates its slot's tool, and when the slot groups several, right-click
/// or press-and-hold pops the group's flyout next to the button.
private struct ToolSlotButton: View {
    @Bindable var session: EditorSession
    let slot: ToolSlot
    let representative: NavigationTool
    let onSelect: () -> Void
    let onPick: (ToolSlot.FlyoutItem) -> Void
    @State private var flyoutShown = false
    /// Set while the mouse is held on the button; a timer opens the flyout when the hold runs long.
    /// (A plain LongPressGesture never fires here — SwiftUI Buttons on macOS swallow the press.)
    @State private var pressStart: Date?

    var body: some View {
        let selected = slot.tools.contains(session.tool)
        Button(action: onSelect) {
            toolIcon(representative)
                .frame(width: 36, height: 36)
                .background(selected ? Color.white.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selected ? Color.white.opacity(0.14) : .clear)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !slot.flyout.isEmpty {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(slot.flyout.isEmpty ? representative.label : "\(representative.label) · 右键或长按选择同类工具").accessibilityLabel(representative.label)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !slot.flyout.isEmpty, pressStart == nil, !flyoutShown else { return }
                pressStart = .now
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if pressStart != nil { flyoutShown = true }
                }
            }
            .onEnded { _ in pressStart = nil })
        .popover(isPresented: $flyoutShown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(slot.flyout) { item in
                    Button {
                        onPick(item)
                        flyoutShown = false
                    } label: {
                        Label("\(item.name) (\(item.key))", systemImage: item.isActive(session) ? "checkmark" : "")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            .padding(.vertical, 6)
        }
        .contextMenu {
            ForEach(slot.flyout) { item in
                Button { onPick(item) } label: {
                    Label("\(item.name) (\(item.key))", systemImage: item.isActive(session) ? "checkmark" : "")
                }
            }
        }
    }

    @ViewBuilder
    private func toolIcon(_ tool: NavigationTool) -> some View {
        if tool == .gradient { GradientToolIcon().frame(width: 18, height: 18) }
        else if tool == .cloneStamp { CloneStampToolIcon().frame(width: 18, height: 18) }
        else if tool == .lasso, session.lassoKind == .polygonal { PolygonalLassoToolIcon().frame(width: 18, height: 18) }
        else if tool == .wand, session.wandMode == .object { ObjectSelectionToolIcon().frame(width: 18, height: 18) }
        // "textformat" has a Chinese variant (格式) that Apple swaps in when the app localizes to
        // zh-Hans; the type tool keeps the Latin "Aa" instead.
        else if tool == .type { Text("Aa").font(.system(size: 16, weight: .medium)) }
        // The Marquee's icon follows its shape: a dashed circle in Ellipse mode.
        else { Image(systemName: tool == .marquee && session.marqueeKind == .ellipse ? "circle.dashed" : session.symbol(for: tool)).font(.system(size: 17)) }
    }
}

extension ContentView {
    /// The rail's slots, top to bottom. Related tools share a slot the way Photoshop groups them: a mode pair
    /// (the Marquee's two shapes), or distinct tools with one job (the repair tools).
    static private let toolSlots: [ToolSlot] = [
        ToolSlot(tools: [.move], flyout: []),
        ToolSlot(tools: [.marquee], flyout: [
            ToolSlot.FlyoutItem(name: "矩形选框", key: "M", tool: .marquee, setup: { $0.marqueeKind = .rectangle }) { $0.tool == .marquee && $0.marqueeKind == .rectangle },
            ToolSlot.FlyoutItem(name: "椭圆选框", key: "M", tool: .marquee, setup: { $0.marqueeKind = .ellipse }) { $0.tool == .marquee && $0.marqueeKind == .ellipse },
        ]),
        ToolSlot(tools: [.lasso], flyout: [
            ToolSlot.FlyoutItem(name: "套索", key: "L", tool: .lasso, setup: { $0.lassoKind = .freehand }) { $0.tool == .lasso && $0.lassoKind == .freehand },
            ToolSlot.FlyoutItem(name: "多边形套索", key: "L", tool: .lasso, setup: { $0.lassoKind = .polygonal }) { $0.tool == .lasso && $0.lassoKind == .polygonal },
        ]),
        ToolSlot(tools: [.wand], flyout: [
            ToolSlot.FlyoutItem(name: "魔棒", key: "W", tool: .wand, setup: { $0.wandMode = .wand }) { $0.tool == .wand && $0.wandMode == .wand },
            ToolSlot.FlyoutItem(name: "对象选择", key: "W", tool: .wand, setup: { $0.wandMode = .object }) { $0.tool == .wand && $0.wandMode == .object },
        ]),
        ToolSlot(tools: [.crop], flyout: []),
        ToolSlot(tools: [.brush], flyout: [
            ToolSlot.FlyoutItem(name: "画笔", key: "B", tool: .brush, setup: { $0.brushMode = .paint }) { $0.tool == .brush && $0.brushMode == .paint },
            ToolSlot.FlyoutItem(name: "橡皮擦", key: "E", tool: .brush, setup: { $0.brushMode = .erase }) { $0.tool == .brush && $0.brushMode == .erase },
        ]),
        ToolSlot(tools: [.spotHealing, .remove, .cloneStamp], flyout: [
            ToolSlot.FlyoutItem(name: "污点修复画笔", key: "J", tool: .spotHealing) { $0.tool == .spotHealing },
            ToolSlot.FlyoutItem(name: "移除", key: "K", tool: .remove) { $0.tool == .remove },
            ToolSlot.FlyoutItem(name: "仿制图章", key: "S", tool: .cloneStamp) { $0.tool == .cloneStamp },
        ]),
        ToolSlot(tools: [.blur], flyout: [
            ToolSlot.FlyoutItem(name: "液化", key: "R", tool: .blur, setup: { $0.blurMode = .liquify }) { $0.tool == .blur && $0.blurMode == .liquify },
            ToolSlot.FlyoutItem(name: "模糊", key: "R", tool: .blur, setup: { $0.blurMode = .blur }) { $0.tool == .blur && $0.blurMode == .blur },
            ToolSlot.FlyoutItem(name: "涂抹", key: "R", tool: .blur, setup: { $0.blurMode = .smudge }) { $0.tool == .blur && $0.blurMode == .smudge },
        ]),
        ToolSlot(tools: [.gradient], flyout: []),
        ToolSlot(tools: [.shape], flyout: [
            ToolSlot.FlyoutItem(name: "矩形", key: "U", tool: .shape, setup: { $0.shapeKind = .rectangle }) { $0.tool == .shape && $0.shapeKind == .rectangle },
            ToolSlot.FlyoutItem(name: "椭圆", key: "U", tool: .shape, setup: { $0.shapeKind = .ellipse }) { $0.tool == .shape && $0.shapeKind == .ellipse },
            ToolSlot.FlyoutItem(name: "直线", key: "U", tool: .shape, setup: { $0.shapeKind = .line }) { $0.tool == .shape && $0.shapeKind == .line },
        ]),
        ToolSlot(tools: [.type], flyout: []),
        ToolSlot(tools: [.eyedropper], flyout: []),
        ToolSlot(tools: [.hand, .zoom], flyout: [
            ToolSlot.FlyoutItem(name: "抓手", key: "H", tool: .hand) { $0.tool == .hand },
            ToolSlot.FlyoutItem(name: "缩放", key: "Z", tool: .zoom) { $0.tool == .zoom },
        ]),
    ]
}

/// A panel's divider that resizes the panel to its right: drag left to widen, right to narrow, within `range`.
private struct PanelResizeEdge: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var startWidth: Double?

    var body: some View {
        Divider().overlay {
            Color.clear.frame(width: 8).contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(range.upperBound, max(range.lowerBound, (start - value.translation.width).rounded()))
                    }
                    .onEnded { _ in startWidth = nil })
                .help("拖动以调整面板宽度")
        }
    }
}

extension View {
    /// Bordered buttons and pop-up menus drawn as capsules throughout the app. Borderless and plain buttons (the tool
    /// rail, the Layers panel footer) have no border to shape, so they're unaffected.
    func roundedControls() -> some View { buttonBorderShape(.capsule) }
}

extension View {
    /// Return or Escape in a property field gives up its focus and hands it back to the canvas, so a tool's key
    /// works straight away instead of typing into the field.
    func releasesFocusOnCommit(_ session: EditorSession) -> some View {
        onSubmit { session.canvasFocusRequest += 1 }
            .onExitCommand { session.canvasFocusRequest += 1 }
    }
}

/// What a field's key monitor reads. The monitor outlives the view value that installed it, so reading the value
/// and applying the step go through here, refreshed on every redraw.
@MainActor final class ArrowStepper {
    var editing = false
    var value: () -> Double = { 0 }
    var change: (Double) -> Void = { _ in }
    private var monitor: Any?

    /// Takes Up and Down while the field holds focus: one step, or ten with Shift.
    func listen(step: Double) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only while a field really is being edited: a field left behind (its tool bar swapped out, say) must not
            // keep taking Up and Down from the canvas, where they nudge the layer.
            guard let self, self.editing, event.keyCode == 126 || event.keyCode == 125,
                  NSApp.keyWindow?.firstResponder is NSTextView else { return event }
            let amount = step * (event.modifierFlags.contains(.shift) ? 10 : 1)
            self.change(self.value() + (event.keyCode == 126 ? amount : -amount))
            return nil
        }
    }
    func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        editing = false
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

/// Up and Down nudge the value in a focused property field, Shift by ten times as much — a text field takes the
/// arrow keys for its insertion point, so they are caught while it holds focus.
private struct ArrowStepping: ViewModifier {
    let step: Double
    let value: () -> Double
    let change: (Double) -> Void
    @FocusState private var focused: Bool
    @State private var stepper = ArrowStepper()
    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, editing in
                stepper.editing = editing
                editing ? stepper.listen(step: step) : stepper.stopListening()
            }
            .onDisappear { stepper.stopListening() }
            .onAppear { refresh() }
            .onChange(of: value()) { _, _ in refresh() }
    }
    private func refresh() {
        stepper.value = value
        stepper.change = change
    }
}

extension View {
    /// Up and Down step this field's value; each field's own binding keeps it in range.
    func arrowSteps(_ step: Double = 1, value: @escaping () -> Double, change: @escaping (Double) -> Void) -> some View {
        modifier(ArrowStepping(step: step, value: value, change: change))
    }
    /// The same, for a field that already owns its focus: it says when it is being edited.
    func arrowSteps(_ step: Double = 1, editing: Bool, stepper: ArrowStepper,
                    value: @escaping () -> Double, change: @escaping (Double) -> Void) -> some View {
        onAppear { stepper.value = value; stepper.change = change }
            .onChange(of: value()) { _, _ in stepper.value = value; stepper.change = change }
            .onChange(of: editing) { _, active in
                stepper.editing = active
                stepper.value = value
                stepper.change = change
                active ? stepper.listen(step: step) : stepper.stopListening()
            }
            .onDisappear { stepper.stopListening() }
    }
}

/// Reports the width it is laid out at. Kept out of the editor's body, whose type-checking is already near its limit.
private struct WidthReader: ViewModifier {
    @Binding var width: CGFloat
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
