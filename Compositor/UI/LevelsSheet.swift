import SwiftUI

struct LevelsSheet: View {
    @Bindable var session: EditorSession
    private var edit: LevelsEdit? { session.levels }
    private var settings: LevelsSettings { edit?.settings ?? LevelsSettings() }
    private var current: LevelRange { settings.current }
    private func update(_ change: (inout LevelsSettings) -> Void) {
        var value = settings; change(&value)
        session.updateLevels(value, preview: edit?.preview ?? true)
    }
    private func value(_ key: WritableKeyPath<LevelRange, Double>) -> Binding<Double> {
        Binding(get: { current[keyPath: key] }, set: { newValue in
            update { var range = $0.current; range[keyPath: key] = newValue; $0.current = range }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("通道", selection: Binding(get: { settings.channel }, set: { channel in update { $0.channel = channel } })) {
                ForEach(LevelsChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }.frame(width: 180)
            VStack(spacing: 0) {
                histogram.frame(height: 150).background(.black.opacity(0.25))
                    .overlay(alignment: .topLeading) {
                        if edit?.histogramReady != true { Text("正在载入直方图…").font(.caption).padding(8) }
                    }
                handles(output: false).frame(height: 20)
            }
            HStack {
                field("输入黑场", value(\.black), decimals: 0)
                Spacer()
                field("灰度系数", value(\.gamma), decimals: 2)
                Spacer()
                field("输入白场", value(\.white), decimals: 0)
            }
            VStack(spacing: 0) {
                LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing).frame(height: 14)
                handles(output: true).frame(height: 20)
            }
            HStack {
                field("输出黑场", value(\.outputBlack), decimals: 0)
                Spacer()
                field("输出白场", value(\.outputWhite), decimals: 0)
            }
            HStack {
                Text("取样").font(.caption).foregroundStyle(.secondary)
                ForEach(LevelsSample.allCases, id: \.self) { mode in
                    Button {
                        edit?.sampleMode = edit?.sampleMode == mode ? nil : mode
                        session.brushRevision += 1
                    } label: {
                        Label(mode.displayName, systemImage: "eyedropper")
                    }.tint(edit?.sampleMode == mode ? .accentColor : .secondary)
                }
            }
            if let mode = edit?.sampleMode {
                Text("点按原始图层以设置\(mode.displayName)。再次点按吸管可停止。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("自动").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(LevelsAuto.allCases, id: \.self) { mode in
                        Button(mode.displayName) { session.autoLevels(mode) }
                    }
                }.disabled(edit?.histogramReady != true)
            }
            HStack {
                Toggle("预览", isOn: Binding(get: { edit?.preview ?? true }, set: {
                    session.updateLevels(settings, preview: $0)
                })).configuredNativeShortcut("p", modifiers: .option)
                Spacer()
                Button("重置") { edit?.sampleMode = nil; update { $0 = LevelsSettings() } }
            }
            Text(session.adjustmentOriginal != nil ? "下方像素 · 按透明度加权的直方图" : session.selection == nil ? "原始像素 · 按透明度加权的直方图" : "原始像素 · 按选区与透明度加权的直方图")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("取消") { session.cancelLevels() }.configuredNativeShortcut(.escape)
                Spacer()
                if edit?.committing == true { ProgressView().controlSize(.small) }
                Button("好") { Task { await session.commitLevels() } }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 440).fixedSize()
        .disabled(edit?.committing == true)
    }
    private func field(_ name: String, _ binding: Binding<Double>, decimals: Int) -> some View {
        let range: ClosedRange<Double> = name == "灰度系数" ? 0.1...9.99 : 0...255
        return VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .scrubbable(sensitivity: decimals == 0 ? 1 : 0.01, value: binding, range: range)
            TextField(name, value: binding, format: .number.precision(.fractionLength(decimals)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80)
                .accessibilityIdentifier("levels\(name.replacingOccurrences(of: " ", with: ""))")
        }
    }
    private var histogram: some View {
        Canvas { context, size in
            let bins = edit?.histogram[settings.channel.index] ?? Array(repeating: 0, count: 256)
            let peak = LevelsHistogramDisplay.scale(for: bins)
            guard peak > 0 else { return }
            var path = Path()
            for index in 0..<256 {
                let height = size.height * min(1, max(0, bins[index] / peak))
                path.addRect(CGRect(x: CGFloat(index) * size.width / 256, y: size.height - height,
                                    width: size.width / 256 + 0.1, height: height))
            }
            let color: Color = switch settings.channel { case .rgb: .gray; case .red: .red; case .green: .green; case .blue: .blue }
            context.fill(path, with: .color(color))
        }.accessibilityLabel("原始 \(settings.channel.displayName) 通道直方图")
        .help("线性直方图，垂直方向自动缩放。尖峰可能超出图形范围；0 到 255 的所有色调仍全部包含在内。")
    }
    private func handles(output: Bool) -> some View {
        GeometryReader { geometry in
            let gammaPosition = current.black + (current.white - current.black) * pow(0.5, current.gamma)
            let positions = output ? [current.outputBlack, current.outputWhite] : [current.black, gammaPosition, current.white]
            ForEach(positions.indices, id: \.self) { index in
                let names = output ? ["输出黑场", "输出白场"] : ["输入黑场", "灰度系数", "输入白场"]
                Image(systemName: "triangle.fill").font(.system(size: 12))
                    .foregroundStyle(index == 0 ? Color.black : index == positions.count - 1 ? .white : .gray)
                    .shadow(color: .gray, radius: 0.5)
                    .frame(width: 22, height: 20).contentShape(Rectangle())
                    .position(x: positions[index] / 255 * geometry.size.width, y: 9)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(output ? "levelsOutput" : "levelsInput"))
                        .onChanged { drag in
                            let x = min(255, max(0, drag.location.x / geometry.size.width * 255))
                            update {
                                var range = $0.current
                                if output {
                                    if index == 0 { range.outputBlack = x.rounded() } else { range.outputWhite = x.rounded() }
                                } else if index == 0 { range.black = min(range.white - 1, x.rounded()) }
                                else if index == 2 { range.white = max(range.black + 1, x.rounded()) }
                                else {
                                    let fraction = min(0.999, max(0.001, (x - range.black) / (range.white - range.black)))
                                    range.gamma = log(fraction) / log(0.5)
                                }
                                $0.current = range
                            }
                        })
                    .accessibilityLabel(names[index])
            }
        }.coordinateSpace(name: output ? "levelsOutput" : "levelsInput")
    }
}

private extension LevelsChannel {
    var displayName: String {
        switch self {
        case .rgb: return "RGB"
        case .red: return "红色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        }
    }
}

private extension LevelsSample {
    var displayName: String {
        switch self {
        case .black: return "黑场"
        case .gray: return "灰场"
        case .white: return "白场"
        }
    }
}

private extension LevelsAuto {
    var displayName: String {
        switch self {
        case .contrast: return "对比度"
        case .color: return "颜色"
        case .neutral: return "颜色 + 中性中间调"
        }
    }
}
