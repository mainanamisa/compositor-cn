import SwiftUI

@main
struct CompositorApp: App {
    @NSApplicationDelegateAdaptor(CompositorApplicationDelegate.self) private var applicationDelegate
    private var session: EditorSession { applicationDelegate.session }
    var body: some Scene {
        Window("Compositor", id: "editor") {
            ProjectWorkspaceView(applicationDelegate: applicationDelegate).roundedControls()
        }
            .defaultSize(width: 1180, height: 780)
            // Files opened from Finder or dropped on the Dock icon go to the app delegate, which imports them into
            // the open window. Left to SwiftUI, each one builds a throwaway window and fades the editor out and back.
            .handlesExternalEvents(matching: [])
            // A first launch fills the screen (without going full screen); after that macOS reopens the window at the
            // size it was left.
            .defaultWindowPlacement { _, context in
                WindowPlacement(size: context.defaultDisplay.visibleRect.size)
            }
            // The project's name is already on its tab, so the toolbar doesn't repeat it as a window title.
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: .undoRedo) {
                    // Dialog text fields keep native text undo; document history
                    // is unavailable while an import or modal edit is active.
                    if session.textDraft != nil || session.levels != nil || session.isProjectBusy || session.showsNewDocument || session.showsImporter || session.renamingLayerID != nil || session.transformEdit?.persistent == true {
                        Button("撤销") {
                            if NSApp.keyWindow?.firstResponder is NSTextView {
                                NSApp.sendAction(NSSelectorFromString("undo:"), to: nil, from: nil)
                            }
                        }
                            .configuredKeyboardShortcut("z")
                        Button("重做") {
                            if NSApp.keyWindow?.firstResponder is NSTextView {
                                NSApp.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil)
                            }
                        }
                            .configuredKeyboardShortcut("z", modifiers: [.command, .shift])
                    } else {
                        Button(session.history.canUndo ? "撤销 \(session.history.undoName)" : "撤销") { session.undo() }
                            .configuredKeyboardShortcut("z").disabled(!session.canUndo)
                        Button(session.history.canRedo ? "重做 \(session.history.redoName)" : "重做") { session.redo() }
                            .configuredKeyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
                    }
                }
                CommandGroup(replacing: .newItem) {
                    Button("新建画布…") {
                        applicationDelegate.showEditor?()
                        Task { await applicationDelegate.projects.newCanvas() }
                    }.configuredKeyboardShortcut("n")
                        .disabled(!applicationDelegate.projects.canStart)
                    Button("打开项目…") {
                        applicationDelegate.showEditor?()
                        Task { await applicationDelegate.projects.open() }
                    }
                        .configuredKeyboardShortcut("o").disabled(!applicationDelegate.projects.canStart)
                    Menu("打开最近项目") {
                        ForEach(RecentProjects.shared.urls, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                applicationDelegate.showEditor?()
                                Task { await applicationDelegate.projects.open(url) }
                            }
                        }
                        Divider()
                        Button("清除菜单") { RecentProjects.shared.clear() }
                            .disabled(RecentProjects.shared.urls.isEmpty)
                    }
                        .disabled(!applicationDelegate.projects.canStart)
                    Button("导入图像…") { session.showsImporter = true }
                        .disabled(session.levels != nil || session.showsBusy || session.isImporting || session.showsNewDocument)
                }
                CommandGroup(replacing: .saveItem) {
                    Button("存储") { Task { await applicationDelegate.projects.save() } }
                        .configuredKeyboardShortcut("s").disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Button("存储为…") { Task { await applicationDelegate.projects.save(asNew: true) } }
                        .configuredKeyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Divider()
                    Button("导出 PNG…") { Task { await applicationDelegate.projects.exportPNG() } }
                        .configuredKeyboardShortcut("e", modifiers: [.command, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Button("导出 JPEG…") { Task { await applicationDelegate.projects.exportJPEG() } }
                        .configuredKeyboardShortcut("s", modifiers: [.command, .option, .shift])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Button("导出为…") { Task { await applicationDelegate.projects.exportAs() } }
                        .configuredKeyboardShortcut("e", modifiers: [.command, .option])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Divider()
                    Button("关闭项目") {
                        if let window = applicationDelegate.projects.window {
                            Task { await applicationDelegate.projects.close(window) }
                        }
                    }.configuredKeyboardShortcut("w").disabled(!applicationDelegate.projects.canStart)
                }
                // Grouped: a commands builder takes at most ten items.
                Group {
                    CommandGroup(after: .toolbar) {
                        // With a dialog's preview open (Export JPEG), these zoom that preview rather than the canvas.
                        Button("适应窗口") {
                            if let preview = session.previewZoom { preview(.fit) } else { session.fit() }
                        }.configuredKeyboardShortcut("0").disabled(session.document == nil)
                        Button("实际像素") {
                            if let preview = session.previewZoom { preview(.actual) } else { session.zoom(to: 1) }
                        }.configuredKeyboardShortcut("1").disabled(session.document == nil)
                        Button("放大") {
                            guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
                            if let preview = session.previewZoom { preview(.zoomIn) } else { session.zoomKeyboard(by: 1) }
                        }
                            .configuredKeyboardShortcut("=").disabled(session.document == nil)
                        Button("缩小") {
                            guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
                            if let preview = session.previewZoom { preview(.zoomOut) } else { session.zoomKeyboard(by: -1) }
                        }
                            .configuredKeyboardShortcut("-").disabled(session.document == nil)
                        Toggle("像素网格（800% 及以上）", isOn: Binding(get: { session.showsPixelGrid },
                                                                              set: { session.showsPixelGrid = $0 }))
                        Toggle("对齐", isOn: Binding(get: { session.snappingEnabled },
                                                     set: { session.snappingEnabled = $0 }))
                        Toggle("显示变换控件", isOn: Binding(get: { session.showsTransformControls },
                                                                          set: { session.showsTransformControls = $0 }))
                            .configuredKeyboardShortcut("h").disabled(session.tool != .move || session.document == nil)
                        Group {
                            Divider()
                            Menu("显示") {
                                Toggle("网格", isOn: Binding(get: { session.showsGrid }, set: { session.showsGrid = $0 }))
                                    .configuredKeyboardShortcut("'").disabled(session.document == nil)
                                Toggle("参考线", isOn: Binding(get: { session.showsGuides }, set: { session.showsGuides = $0 }))
                                    .configuredKeyboardShortcut(";").disabled(session.document == nil)
                            }
                            Button("网格设置…") { Task { await applicationDelegate.projects.gridSettings() } }
                                .disabled(session.document == nil)
                            Toggle("标尺", isOn: Binding(get: { session.showsRulers }, set: { session.showsRulers = $0 }))
                                .configuredKeyboardShortcut("r").disabled(session.document == nil)
                            Divider()
                            Toggle("对齐", isOn: Binding(get: { session.snapEnabled }, set: { session.snapEnabled = $0 }))
                                .configuredKeyboardShortcut(";", modifiers: [.command, .shift]).disabled(session.document == nil)
                            Menu("对齐到") {
                                Toggle("参考线", isOn: Binding(get: { session.snapToGuides }, set: { session.snapToGuides = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("网格", isOn: Binding(get: { session.snapToGrid }, set: { session.snapToGrid = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("图层", isOn: Binding(get: { session.snapToLayers }, set: { session.snapToLayers = $0 }))
                                    .disabled(session.document == nil)
                                Toggle("文档边界", isOn: Binding(get: { session.snapToDocumentBounds },
                                                                        set: { session.snapToDocumentBounds = $0 }))
                                    .disabled(session.document == nil)
                            }
                            Divider()
                            Toggle("锁定参考线", isOn: Binding(get: { session.locksGuides }, set: { session.locksGuides = $0 }))
                                .configuredKeyboardShortcut(";", modifiers: [.command, .option]).disabled(session.document == nil)
                            Button("清除参考线") { session.clearGuides() }
                                .disabled(!session.canClearGuides)
                        }
                    }
                    // ⌘H toggles the Move tool's transform controls instead of hiding the app, so Hide keeps its
                    // place in the app menu without the shortcut.
                    CommandGroup(replacing: .appVisibility) {
                        Button("隐藏 Compositor") { NSApp.hide(nil) }
                        Button("隐藏其他") { NSApp.hideOtherApplications(nil) }
                            .configuredKeyboardShortcut("h", modifiers: [.command, .option])
                        Button("全部显示") { NSApp.unhideAllApplications(nil) }
                    }
                }
                CommandGroup(replacing: .pasteboard) {
                    // Canvas pixels when the canvas has focus; text fields keep their own editing.
                    // Cut, Copy and Paste check when chosen rather than through .disabled: what they depend on
                    // (the pasteboard, the copied pixels, the busy flag) isn't observed, so a disabled state could
                    // go stale — the first Paste after a Copy used to beep until something else refreshed the menu.
                    Button("剪切") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                        else if session.selection != nil, session.canCopyPixels { Task { await session.cutSelection() } }
                        else { NSSound.beep() }
                    }
                        .configuredKeyboardShortcut("x")
                    Button("拷贝") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                        else if session.canCopyPixels || session.canCopyLayer { session.copySelection() }
                        else { NSSound.beep() }
                    }
                        .configuredKeyboardShortcut("c")
                    Button("合并拷贝") { session.copyMergedSelection() }
                        .configuredKeyboardShortcut("c", modifiers: [.command, .shift]).disabled(!session.canCopyMerged)
                    Button("粘贴") {
                        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                        else if applicationDelegate.workspace.pasteCopiedLayer() { }
                        else if session.canPaste { session.paste() }
                        else { NSSound.beep() }
                    }
                        .configuredKeyboardShortcut("v")
                }
                CommandGroup(after: .pasteboard) {
                    Divider()
                    Button("键盘快捷键…") { ShortcutSettings.shared.show() }
                    // Photoshop's fill shortcuts; in a text field they keep their text meaning.
                    Button("用前景色填充") {
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            NSApp.sendAction(#selector(NSResponder.deleteWordBackward(_:)), to: nil, from: nil)
                        } else { Task { await session.fillSelection(with: .foreground) } }
                    }
                        .configuredKeyboardShortcut(.delete, modifiers: .option).disabled(!session.canEditPixels)
                    Button("用背景色填充") {
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                        } else { Task { await session.fillSelection(with: .background) } }
                    }
                        .configuredKeyboardShortcut(.delete, modifiers: .command).disabled(!session.canEditPixels)
                    Button("清除选区像素") { Task { await session.clearSelectedPixels() } }
                        .disabled(session.selection == nil || !session.canEditPixels)
                    Button("内容识别填充…") { session.beginFilter(.contentAwareFill) }
                        .configuredKeyboardShortcut(.delete, modifiers: .shift).disabled(!session.canContentAwareFill)
                }
                CommandMenu("选择") {
                    // A field being edited keeps its own Select All: offer it to the responder chain
                    // first, which covers every kind of text control rather than NSTextView alone,
                    // and select the canvas only when nothing there wanted it.
                    Button("全部") {
                        if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) { return }
                        guard session.document != nil else { return }
                        session.selectAll()
                    }
                        // Never disabled: on macOS this menu item is what binds Cmd-A to selectAll:, so
                        // switching it off takes Select All away from every text field too. With no
                        // document and nothing being edited the action simply does nothing.
                        .configuredKeyboardShortcut("a")
                    Button("取消选择") { session.deselect() }
                        .configuredKeyboardShortcut("d").disabled(session.selection == nil || !session.canEditSelection)
                    Button("反选") { session.invertSelection() }
                        .configuredKeyboardShortcut("i", modifiers: [.command, .shift])
                        .disabled(session.selection == nil || !session.canEditSelection)
                    Button("图层像素") {
                        if let id = session.activeLayerID { session.loadLayerSelection(layerID: id) }
                    }
                        .disabled(session.activeLayer?.asset == nil || !session.canEditSelection)
                    Button("主体") { Task { await session.selectSubject() } }
                        .configuredKeyboardShortcut("a", modifiers: [.command, .option])
                        .disabled(!session.canSelectSubject)
                    Button("色彩范围…") { session.beginColorRange() }
                        .disabled(!session.canSelectColorRange)
                    Button("蒙版黑色区域") {
                        if let id = session.activeLayerID { session.loadMaskSelection(layerID: id) }
                    }
                        .disabled(session.activeLayer?.mask == nil || !session.canEditSelection)
                    Divider()
                    Button("扩展…") { session.promptSelectionAmount(.expand) }
                        .disabled(!session.canModifySelection)
                    Button("收缩…") { session.promptSelectionAmount(.contract) }
                        .disabled(!session.canModifySelection)
                    Button("羽化…") { session.promptSelectionAmount(.feather) }
                        .disabled(!session.canModifySelection)
                }
                CommandMenu("图像") {
                    Button("曲线…") { session.beginFilter(.curves) }
                        .configuredKeyboardShortcut("m").disabled(!session.canAdjustColors || session.hueSaturation != nil)
                    Button("色阶…") { session.beginLevels() }
                        .configuredKeyboardShortcut("l").disabled(!session.canAdjustColors || session.hueSaturation != nil)
                    Button("色相/饱和度…") { session.beginHueSaturation() }
                        .configuredKeyboardShortcut("u").disabled(!session.canAdjustColors)
                    ForEach([FilterKind.blackWhite, .colorBalance, .exposure, .gradientMap, .grain], id: \.self) { kind in
                        Button("\(kind.displayName)…") { session.beginFilter(kind) }
                            .disabled(!session.canAdjustColors || session.hueSaturation != nil)
                    }
                    Button(session.isMaskSelected ? "蒙版反相" : "反相") { Task { await session.invertPixels() } }
                        .configuredKeyboardShortcut("i")
                        .disabled(!session.canInvert)
                    Divider()
                    Button("画布大小…") { Task { await applicationDelegate.projects.canvasSize() } }
                        .configuredKeyboardShortcut("c", modifiers: [.command, .option])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Button("图像大小…") { Task { await applicationDelegate.projects.imageSize() } }
                        .configuredKeyboardShortcut("i", modifiers: [.command, .option])
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Button("裁切…") { Task { await applicationDelegate.projects.trim() } }
                        .disabled(session.document == nil || !applicationDelegate.projects.canStart)
                    Group {
                        Divider()
                        Button("水平翻转画布") { session.flipCanvas(horizontally: true) }
                            .disabled(!session.canEditLayers)
                        Button("垂直翻转画布") { session.flipCanvas(horizontally: false) }
                            .disabled(!session.canEditLayers)
                    }
                }
                CommandMenu("滤镜") {
                    ForEach(FilterKind.allCases.filter { $0 != .contentAwareFill && !$0.isImageAdjustment }, id: \.self) { kind in
                        Button("\(kind.displayName)…") { session.beginFilter(kind) }
                            .disabled(!(kind == .vignette ? session.canVignette : session.canAdjustColors) || session.hueSaturation != nil)
                    }
                }
                CommandMenu("图层") {
                    Menu("新建调整图层") {
                        ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                            Button(kind.displayName + (kind.isEditable ? "…" : "")) { session.addAdjustment(kind) }
                        }
                    }.disabled(!session.canEditLayers || session.document == nil)
                    Button("编辑调整…") {
                        session.adjustmentEditingID = session.activeLayerID
                    }.disabled(!session.canEditLayers || session.activeLayer?.adjustment == nil)
                    Divider()
                    Button(session.canTransformSelection ? "变换选区" : "变换图层") { session.transformCommand() }
                        .configuredKeyboardShortcut("t").disabled(!session.canTransform && !session.canTransformSelection)
                    Button(session.selection == nil ? "复制图层" : "通过拷贝新建图层") { session.layerViaCopy() }
                        .configuredKeyboardShortcut("j").disabled(!session.canCopyPixels && !(session.selection == nil && session.canEditLayers && session.activeLayer != nil))
                    Divider()
                    Button(session.activeLayer?.maskSourceID == nil ? "创建剪贴蒙版" : "释放剪贴蒙版") {
                        if let id = session.activeLayerID { session.toggleClippingMask(id) }
                    }
                    .configuredKeyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(session.activeLayerID.map { !session.canToggleClippingMask($0) } ?? true)
                    Divider()
                    Button("图层编组") { session.groupSelectedLayers() }
                        .configuredKeyboardShortcut("g").disabled(!session.canEditLayers)
                    Button("取消图层编组") { session.ungroupLayers() }
                        .configuredKeyboardShortcut("g", modifiers: [.command, .shift]).disabled(!session.canUngroupLayers)
                    Button("移出组") { session.moveActiveLayerOutOfGroup() }
                        .disabled(!session.canEditLayers || session.activeLayer?.parentID == nil)
                    Button("新建空白图层") { session.addBlankLayer() }
                        .configuredKeyboardShortcut("n", modifiers: [.command, .shift]).disabled(!session.canEditLayers)
                    Button("重命名图层…") { session.renamingLayerID = session.activeLayerID }
                        .disabled(!session.canEditLayers || session.activeLayer == nil)
                    Button(session.activeLayer?.isVisible == false ? "显示图层" : "隐藏图层") {
                        if let id = session.activeLayerID { session.toggleLayerVisibility(id) }
                    }.disabled(!session.canEditLayers || session.activeLayer == nil)
                    Divider()
                    Button("上移图层") { session.moveActiveLayer(by: 1) }
                        .configuredKeyboardShortcut("]").disabled(!session.canMoveActiveLayer(by: 1))
                    Button("下移图层") { session.moveActiveLayer(by: -1) }
                        .configuredKeyboardShortcut("[").disabled(!session.canMoveActiveLayer(by: -1))
                    Group {
                        Button(mergeMenuTitle(session.mergeTitle)) { session.mergeLayers() }
                            .configuredKeyboardShortcut("e").disabled(!session.canMergeLayers)
                        Divider()
                        Button("水平翻转图层") { session.flipLayers(horizontally: true) }
                            .disabled(!session.canTransform)
                        Button("垂直翻转图层") { session.flipLayers(horizontally: false) }
                            .disabled(!session.canTransform)
                    }
                    Divider()
                    Button(session.selectedEffect != nil ? "删除" + session.selectedEffect!.kind.displayName : session.isMaskSelected && session.activeLayer?.mask != nil ? "删除图层蒙版" : session.selectedLayerIDs.count > 1 ? "删除多个图层" : "删除图层") {
                        session.deleteLayerOrMask()
                    }
                        .disabled(!session.canEditLayers || session.activeLayer == nil)
                }
            }
    }
}

/// The ⌘E menu title: `mergeTitle` doubles as the undo name and stays English, so the menu maps it here.
private func mergeMenuTitle(_ title: String) -> String {
    switch title {
    case "Merge Layers": return "合并图层"
    case "Merge Group": return "合并组"
    default: return "向下合并"
    }
}

// Chinese display names for menus and panel titles; the raw values stay English because
// AdjustmentKind is Codable and stored in project files, and the others double as undo names.
extension FilterKind {
    var displayName: String {
        switch self {
        case .gaussianBlur: return "高斯模糊"
        case .motionBlur: return "动感模糊"
        case .addNoise: return "添加杂色"
        case .vignette: return "暗角"
        case .bloomGlow: return "泛光/辉光"
        case .dither: return "抖动"
        case .tonalContrast: return "色调对比度"
        case .lensCorrection: return "镜头校正"
        case .cameraRaw: return "Camera Raw 滤镜"
        case .removeBackground: return "移除背景"
        case .contentAwareFill: return "内容识别填充"
        case .curves: return "曲线"
        case .exposure: return "曝光"
        case .gradientMap: return "渐变映射"
        case .grain: return "颗粒"
        case .blackWhite: return "黑白"
        case .colorBalance: return "色彩平衡"
        }
    }
}

extension AdjustmentKind {
    var displayName: String {
        switch self {
        case .hsv: return "色相/饱和度"
        case .levels: return "色阶"
        case .curves: return "曲线"
        case .exposure: return "曝光"
        case .gradientMap: return "渐变映射"
        case .grain: return "颗粒"
        case .addNoise: return "添加杂色"
        case .gaussianBlur: return "高斯模糊"
        case .motionBlur: return "动感模糊"
        case .invert: return "反相"
        case .blackWhite: return "黑白"
        case .colorBalance: return "色彩平衡"
        }
    }
}

extension LayerEffectKind {
    var displayName: String {
        switch self {
        case .stroke: return "描边"
        case .shadow: return "投影"
        case .colorOverlay: return "颜色叠加"
        case .innerShadow: return "内阴影"
        case .outerGlow: return "外发光"
        case .innerGlow: return "内发光"
        }
    }
}

extension EditorSession.SelectionAmountOperation {
    var displayName: String {
        switch self {
        case .expand: return "扩展"
        case .contract: return "收缩"
        case .feather: return "羽化"
        }
    }
}
