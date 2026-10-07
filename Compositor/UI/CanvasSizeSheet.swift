import SwiftUI

struct CanvasSizeSheet: View {
    let foreground: PaletteColor
    let background: PaletteColor
    let session: EditorSession
    let finish: (CanvasSizeOptions?) -> Void
    @State private var draft: CanvasSizeDraft
    @State private var anchor = 4
    @State private var extensionChoice = "透明"
    @State private var customColor = PaletteColor.white
    private let anchorNames = ["左上", "上中", "右上", "左中", "居中", "右中", "左下", "下中", "右下"]

    init(document: CanvasDocument, session: EditorSession, finish: @escaping (CanvasSizeOptions?) -> Void) {
        self.foreground = session.foregroundColor
        self.background = session.backgroundColor
        self.session = session
        self.finish = finish
        _draft = State(initialValue: CanvasSizeDraft(width: document.width, height: document.height, resolution: document.resolution))
    }

    private func dimension(_ widthAxis: Bool) -> Binding<Double> {
        Binding(get: { draft.displayed(widthAxis: widthAxis) }, set: { draft.set($0, widthAxis: widthAxis) })
    }
    private func scrubRange(_ widthAxis: Bool) -> ClosedRange<Double> {
        let original = Double(widthAxis ? draft.originalWidth : draft.originalHeight)
        let other = Double(widthAxis ? draft.originalHeight : draft.originalWidth)
        let lower = draft.locked ? max(1, original / other) : 1.0
        let upper = draft.locked ? min(30_000, 30_000 * original / other) : 30_000.0
        func displayed(_ pixels: Double) -> Double {
            let difference = pixels - (draft.relative ? original : 0)
            switch draft.unit {
            case .pixels: return difference
            case .percent: return difference / original * 100
            case .inches: return difference / draft.resolution
            case .centimeters: return difference / draft.resolution * 2.54
            }
        }
        return displayed(lower)...displayed(upper)
    }
    private func scrubSensitivity(_ widthAxis: Bool) -> Double {
        switch draft.unit {
        case .pixels: return 1
        case .percent: return 100 / Double(widthAxis ? draft.originalWidth : draft.originalHeight)
        case .inches: return 1 / draft.resolution
        case .centimeters: return 2.54 / draft.resolution
        }
    }
    private func bytes(_ width: Int, _ height: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(width) * Int64(height) * 4, countStyle: .memory)
    }
    private var fill: CanvasExtensionColor? {
        let color: NSColor
        switch extensionChoice {
        case "透明": return nil
        case "黑色": color = .black
        case "前景": color = foreground.nsColor
        case "白色": color = .white
        case "背景": color = background.nsColor
        default: color = customColor.nsColor
        }
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return CanvasExtensionColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    var body: some View { sheet.roundedControls() }
    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("画布大小").font(.title2.bold())
            Text("当前：\(draft.originalWidth) × \(draft.originalHeight) 像素")
            Text("未压缩 RGBA 画布 \(bytes(draft.originalWidth, draft.originalHeight))")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Picker("单位", selection: $draft.unit) {
                ForEach(CanvasUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Text("宽度").frame(width: 60, alignment: .leading)
                    .scrubbable(sensitivity: scrubSensitivity(true), value: dimension(true), range: scrubRange(true), step: 1)
                TextField("宽度", value: dimension(true), format: .number.precision(.fractionLength(0...3)))
            }
            HStack {
                Text("高度").frame(width: 60, alignment: .leading)
                    .scrubbable(sensitivity: scrubSensitivity(false), value: dimension(false), range: scrubRange(false), step: 1)
                TextField("高度", value: dimension(false), format: .number.precision(.fractionLength(0...3)))
            }
            Toggle("相对于当前尺寸", isOn: $draft.relative)
            Toggle("锁定原始长宽比", isOn: $draft.locked)
                .onChange(of: draft.locked) { _, locked in
                    if locked { draft.set(draft.displayed(widthAxis: true), widthAxis: true) }
                }
            if draft.valid {
                Text("新建：\(Int(draft.width.rounded())) × \(Int(draft.height.rounded())) 像素 · 未压缩 \(bytes(Int(draft.width.rounded()), Int(draft.height.rounded())))")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("最终尺寸每边必须为 1–\(DocumentLimits.maxSide.formatted()) 像素。")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("锚点")
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        ForEach(0..<3) { row in
                            GridRow {
                                ForEach(0..<3) { column in
                                    let index = row * 3 + column
                                    Button { anchor = index } label: {
                                        Image(systemName: index == anchor ? "circle.fill" : "circle")
                                            .frame(width: 25, height: 25)
                                    }
                                    .tint(index == anchor ? .accentColor : .secondary)
                                    .help(anchorNames[index]).accessibilityLabel(anchorNames[index])
                                    .accessibilityValue(index == anchor ? "已选中" : "")
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(anchorNames[anchor]).font(.callout.bold())
                    Text("保持该点固定。图像内容不会缩放；被裁剪的内容保留在画布之外。")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(.top, 28)
            }
            Picker("画布扩展颜色", selection: $extensionChoice) {
                ForEach(["透明", "前景", "背景", "黑色", "白色", "自定"], id: \.self) { Text($0) }
            }
            if extensionChoice == "自定" {
                HStack(spacing: 8) {
                    Text("扩展颜色")
                    DialogColorSwatch(title: "扩展颜色", color: $customColor, session: session)
                        .help("新增画布区域的颜色")
                }
            }
            HStack {
                Button("取消") { DialogColorSwatch.closePicker(session); finish(nil) }.configuredNativeShortcut(.escape)
                Spacer()
                Button("确定") {
                    guard draft.valid else { return }
                    DialogColorSwatch.closePicker(session)
                    finish(CanvasSizeOptions(width: Int(draft.width.rounded()), height: Int(draft.height.rounded()), anchor: anchor, fill: fill))
                }.configuredNativeShortcut(.return).disabled(!draft.valid)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 450)
    }
}
