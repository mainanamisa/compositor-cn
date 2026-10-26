import SwiftUI

/// The Layers panel's type filter: the kinds of layer the list narrows to while their toggles are on, and Selected,
/// the layers selected right now.
enum LayerType: String, CaseIterable {
    case image, shape, text, folder, adjustment, selected
}

extension LayerType {
    var titleKey: LocalizedStringKey {
        switch self {
        case .image: "图像"
        case .shape: "形状"
        case .text: "文本"
        case .folder: "组"
        case .adjustment: "调整"
        case .selected: "选中"
        }
    }
    var systemImageName: String {
        switch self {
        case .image: "photo"
        case .shape: "square.on.circle"
        case .text: "character"
        case .folder: "folder"
        case .adjustment: "circle.righthalf.filled"
        case .selected: "checkmark.circle"
        }
    }
    /// VoiceOver's description of the type's toggle.
    var filterLabel: LocalizedStringKey {
        switch self {
        case .image: "只显示图像图层"
        case .shape: "只显示形状图层"
        case .text: "只显示文本图层"
        case .folder: "只显示组"
        case .adjustment: "只显示调整图层"
        case .selected: "只显示选中的图层"
        }
    }
    /// The toggle's stable identifier, cased to match "layerFilterAll".
    var accessibilityID: String {
        "layerFilter" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

extension ImageLayer {
    /// Which of the panel's type filters the layer belongs to. Text means editable text; rasterized
    /// text counts as an image, as it does everywhere else in the app.
    var layerType: LayerType {
        if isGroup { return .folder }
        if adjustment != nil { return .adjustment }
        if liveText != nil { return .text }
        if shape != nil { return .shape }
        return .image
    }
}

extension EditorSession {
    /// Whether the panel's search text or type filter is on.
    var isFilteringLayers: Bool { !layerSearchText.isEmpty || !layerTypeFilter.isEmpty }
    /// The rows the panel shows: `layerRows` narrowed by the search text and type filter. While a filter
    /// is on, folders list themselves opened, so layers inside collapsed folders can be found too.
    var filteredLayerRows: [LayerHierarchy.Entry] {
        let entries = LayerHierarchy.entries(document?.layers.map(\.hierarchyRecord) ?? [], topFirst: true,
                                             collapsed: isFilteringLayers ? [] : collapsedGroupIDs)
        guard isFilteringLayers else { return entries }
        let query = layerSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        let byID = Dictionary(uniqueKeysWithValues: (document?.layers ?? []).map { ($0.id, $0) })
        func matches(_ layer: ImageLayer) -> Bool {
            (query.isEmpty || layer.name.lowercased().contains(query))
                && (layerTypeFilter.isEmpty || layerTypeFilter.contains(layer.layerType)
                    || (layerTypeFilter.contains(.selected) && selectedLayerIDs.contains(layer.id)))
        }
        // A folder that matches brings everything inside it along, so its contents can be seen and worked on.
        let matched = Set((document?.layers ?? []).filter(matches).map(\.id))
        func insideMatchedFolder(_ layer: ImageLayer) -> Bool {
            var parent = layer.parentID
            while let id = parent {
                if matched.contains(id) { return true }
                parent = byID[id]?.parentID
            }
            return false
        }
        return entries.filter { entry in
            guard let layer = byID[entry.layer.id] else { return false }
            return matched.contains(layer.id) || insideMatchedFolder(layer)
        }
    }
    /// Clears the panel's search text.
    func clearLayerSearch() {
        layerSearchText = ""
    }
    /// Clears the panel's every type toggle.
    func clearLayerTypeFilter() {
        layerTypeFilter = []
    }
}

/// The Layers panel's title row: "Layers", with a magnifier that turns the title into a search field for layer names
/// (and itself into a close button), and a funnel that opens the type filter (blue while one is on). Escape on an
/// empty search, or the close button, puts the title back.
struct LayersHeader: View {
    @Bindable var session: EditorSession
    @State private var searching = false
    /// Whether the funnel's type-filter panel is open.
    @State private var isPresentingFilter = false

    var body: some View {
        HStack(spacing: 2) {
            if searching {
                LayerSearchField(text: $session.layerSearchText) { searching = false }
                    .padding(.trailing, 6)
            } else {
                Text("图层").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            Button {
                if searching { session.clearLayerSearch() }
                searching.toggle()
            } label: { headerIcon(searching ? "xmark" : "magnifyingglass") }
                .buttonStyle(.plain)
                .help(searching ? "关闭搜索" : "按名称搜索图层")
                .accessibilityLabel(searching ? "关闭搜索" : "搜索图层")
                .accessibilityIdentifier("layerSearchButton")
            Button { isPresentingFilter.toggle() } label: {
                headerIcon("line.3.horizontal.decrease", active: !session.layerTypeFilter.isEmpty)
            }
            .buttonStyle(.plain)
            .help("只显示部分类型的图层").accessibilityLabel("过滤图层列表")
            .popover(isPresented: $isPresentingFilter) { typeFilterPopover }
        }
        // As tall as the search field, so the row keeps its height when the title turns into one.
        .frame(height: 30)
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
        .disabled(session.document?.layers.isEmpty != false)
    }

    /// A title-row icon with room around it to click: the whole square, not just the glyph.
    private func headerIcon(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name)
            .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }

    /// The funnel's contents: All Layers reads as on while no toggle is on, and turning it on clears them.
    private var typeFilterPopover: some View {
        VStack(alignment: .leading) {
            Toggle("全部图层", systemImage: "square.3.layers.3d", isOn: Binding(
                get: { session.layerTypeFilter.isEmpty },
                set: { on in if on { session.clearLayerTypeFilter() } }
            ))
            .labelReservedIconWidth(16)
            .accessibilityIdentifier("layerFilterAll")
            Divider()
            ForEach(LayerType.allCases.filter { $0 != .selected }, id: \.self) { typeToggle($0) }
            Divider()
            typeToggle(.selected)
        }
        .padding()
    }

    private func typeToggle(_ kind: LayerType) -> some View {
        Toggle(kind.titleKey, systemImage: kind.systemImageName, isOn: Binding(
            get: { session.layerTypeFilter.contains(kind) },
            set: { on in if on { session.layerTypeFilter.insert(kind) } else { session.layerTypeFilter.remove(kind) } }
        ))
        .labelReservedIconWidth(16)
        .accessibilityLabel(kind.filterLabel)
        .accessibilityIdentifier(kind.accessibilityID)
    }
}

/// The Layers panel's search field, styled as the font list's: a magnifier and plain text in a box with a thin accent
/// border. It takes the keyboard when it appears; `end` runs once it's left empty, by Escape or a click elsewhere.
private struct LayerSearchField: View {
    @Binding var text: String
    var end: () -> Void

    var body: some View {
        let box = RoundedRectangle(cornerRadius: 6, style: .continuous)
        // The font list's measurements: 30 points tall, a 13-point magnifier in a 16-point square, 13-point text.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            PlainSearchText(text: $text, end: end)
        }
        .padding(.leading, 8).padding(.trailing, 6)
        .frame(height: 30)
        .overlay { box.strokeBorder(Color.accentColor, lineWidth: 1) }
    }
}

/// The field itself: plain text, no bezel, no focus ring and no clear button.
private struct PlainSearchText: NSViewRepresentable {
    @Binding var text: String
    var end: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "搜索图层"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("layerSearch")
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Only when they differ: writing the string back mid-edit would move the insertion point.
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, end: end) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>
        let end: () -> Void
        init(text: Binding<String>, end: @escaping () -> Void) { self.text = text; self.end = end }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if text.wrappedValue.isEmpty { end() }
        }

        /// Escape clears the search, then on an empty one closes it and gives the canvas back the keyboard.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            if text.wrappedValue.isEmpty {
                control.window?.makeFirstResponder(nil)
                end()
            } else {
                text.wrappedValue = ""
                (control as? NSTextField)?.stringValue = ""
            }
            return true
        }
    }
}
