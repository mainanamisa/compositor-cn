import SwiftUI

/// View > Grid Settings…: every change shows on the canvas at once through `preview`; Cancel puts back what was there.
struct GridSettingsSheet: View {
    let session: EditorSession
    let preview: (LayoutGrid, GridAppearance) -> Void
    let finish: ((LayoutGrid, GridAppearance)?) -> Void
    @State private var spacing: Int
    @State private var subdivisions: Int
    @State private var appearance: GridAppearance
    /// The preset in use when the picker first moved the color; Cancel in the picker puts it back.
    @State private var pickedFrom: GridAppearance.Preset?

    init(session: EditorSession, grid: LayoutGrid, appearance: GridAppearance, preview: @escaping (LayoutGrid, GridAppearance) -> Void,
         finish: @escaping ((LayoutGrid, GridAppearance)?) -> Void) {
        self.session = session
        self.preview = preview
        self.finish = finish
        _spacing = State(initialValue: grid.spacing)
        _subdivisions = State(initialValue: grid.subdivisions)
        _appearance = State(initialValue: appearance)
    }

    private var valid: Bool {
        LayoutGrid.spacingRange.contains(spacing) && LayoutGrid.subdivisionRange.contains(subdivisions)
            && subdivisions <= spacing
    }

    private var grid: LayoutGrid { LayoutGrid(spacing: spacing, subdivisions: subdivisions) }

    /// The swatch shows whichever color is in use; picking one in it makes that the Custom color.
    private var swatchColor: Binding<PaletteColor> {
        Binding(get: { appearance.color }, set: { picked in
            // The picker reports the color it opened on too; that alone leaves the preset chosen.
            guard picked != appearance.color else { return }
            if let pickedFrom, picked == pickedFrom.color {
                appearance.preset = pickedFrom
                self.pickedFrom = nil
                return
            }
            if appearance.preset != .custom { pickedFrom = appearance.preset }
            appearance.customColor = picked
            appearance.preset = .custom
        })
    }

    private func setOpacity(_ value: Int) {
        appearance.opacity = min(max(value, GridAppearance.opacityRange.lowerBound), GridAppearance.opacityRange.upperBound)
    }

    var body: some View { sheet.roundedControls() }

    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("网格").font(.title2.bold())
            HStack {
                Text("颜色").frame(width: 110, alignment: .leading)
                Picker("颜色", selection: $appearance.preset) {
                    ForEach(GridAppearance.Preset.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden()
                DialogColorSwatch(title: "网格颜色", color: swatchColor, session: session)
                    .help("选取自定义网格颜色")
            }
            HStack {
                Text("样式").frame(width: 110, alignment: .leading)
                Picker("样式", selection: $appearance.style) {
                    ForEach(GridAppearance.Style.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden()
            }
            HStack {
                Text("不透明度").frame(width: 110, alignment: .leading)
                    .scrubbable(sensitivity: 0.5, value: $appearance.opacity, range: GridAppearance.opacityRange)
                Slider(value: Binding(get: { Double(appearance.opacity) }, set: { appearance.opacity = Int($0.rounded()) }),
                       in: Double(GridAppearance.opacityRange.lowerBound)...Double(GridAppearance.opacityRange.upperBound))
                TextField("不透明度", value: Binding(get: { appearance.opacity }, set: setOpacity), format: .number)
                    .frame(width: 48).multilineTextAlignment(.trailing)
                    .arrowSteps(value: { Double(appearance.opacity) }, change: { setOpacity(Int($0.rounded())) })
                    .unitSuffix("%")
            }
            Divider()
            HStack {
                Text("网格线间隔").frame(width: 110, alignment: .leading)
                    .scrubbable(sensitivity: 1, value: $spacing, range: LayoutGrid.spacingRange)
                TextField("网格线间隔", value: $spacing, format: .number)
                Text("像素").foregroundStyle(.secondary)
            }
            HStack {
                Text("子网格").frame(width: 110, alignment: .leading)
                    .scrubbable(sensitivity: 0.2, value: $subdivisions, range: LayoutGrid.subdivisionRange)
                TextField("子网格", value: $subdivisions, format: .number)
            }
            Text(valid ? "每 \(Double(grid.step).formatted(.number.precision(.fractionLength(0...2)))) 像素一条子网格线。"
                       : "网格线间隔须为 \(LayoutGrid.spacingRange.lowerBound)–\(LayoutGrid.spacingRange.upperBound.formatted()) 像素，子网格数为 \(LayoutGrid.subdivisionRange.lowerBound)–\(LayoutGrid.subdivisionRange.upperBound)，且不超过网格线之间的像素数。")
                .foregroundStyle(valid ? Color.secondary : Color.orange).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { DialogColorSwatch.closePicker(session); finish(nil) }.configuredNativeShortcut(.escape)
                Button("恢复默认") {
                    spacing = LayoutGrid().spacing
                    subdivisions = LayoutGrid().subdivisions
                    // The Custom color is kept, so it's still there if Custom is chosen again.
                    pickedFrom = nil
                    appearance.preset = GridAppearance().preset
                    appearance.style = GridAppearance().style
                    appearance.opacity = GridAppearance().opacity
                }
                Spacer()
                Button("确定") {
                    guard valid else { return }
                    DialogColorSwatch.closePicker(session)
                    finish((grid, appearance))
                }
                .configuredNativeShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 360)
        .onChange(of: appearance) { preview(grid, appearance) }
        // Choosing a preset from the menu ends a pick that started from another.
        .onChange(of: appearance.preset) { _, preset in if preset != .custom { pickedFrom = nil } }
        .onChange(of: spacing) { if valid { preview(grid, appearance) } }
        .onChange(of: subdivisions) { if valid { preview(grid, appearance) } }
    }
}

/// Chinese picker labels; the raw values are stored in user defaults, so they stay English.
private extension GridAppearance.Preset {
    var displayName: String {
        switch self {
        case .lightGray: "浅灰色"
        case .lightBlue: "浅蓝色"
        case .lightRed: "浅红色"
        case .green: "绿色"
        case .mediumBlue: "中蓝色"
        case .yellow: "黄色"
        case .magenta: "洋红"
        case .cyan: "青色"
        case .black: "黑色"
        case .custom: "自定"
        }
    }
}

private extension GridAppearance.Style {
    var displayName: String {
        switch self {
        case .lines: "直线"
        case .dashedLines: "虚线"
        case .dots: "网点"
        }
    }
}
