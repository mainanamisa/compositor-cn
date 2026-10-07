import AppKit
import SwiftUI

/// Camera Raw Filter's adjustment column: the histogram, then Light, Color, Color Grading, Effects, Curve,
/// Color Mixer, Detail, Optics, Geometry, and Calibration.
struct CameraRawControls: View {
    @Bindable var session: EditorSession
    @State private var expanded: Set<Section> = [.light, .color, .colorGrading]
    @State private var optionMonitor: Any?

    private var settings: FilterSettings { session.filterEdit?.settings ?? FilterSettings() }
    private var raw: CameraRawSettings { settings.cameraRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            histogram
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Section.allCases) { section in
                        disclosure(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { installOptionMonitor() }
        .onDisappear { removeOptionMonitor() }
    }

    private var histogram: some View {
        let scope = session.filterEdit?.cameraRawScope
        let mode = session.filterEdit?.cameraRawScopeMode ?? .histogram
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                graph(scope, mode: mode)
                    .frame(height: 110)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                HStack {
                    clipButton(shadows: true)
                    Spacer()
                    clipButton(shadows: false)
                }
                .padding(4)
            }
            .contextMenu {
                Button("直方图") { session.filterEdit?.cameraRawScopeMode = .histogram }
                Button("矢量图") { session.filterEdit?.cameraRawScopeMode = .vectorscope }
            }
            .help(mode == .histogram
                  ? "色调从左到右由黑到白：黑场、阴影、中间调、高光、白场。按住 Control 点按可显示矢量图。"
                  : "色相沿色轮分布，饱和度由中心向外。按住 Control 点按可显示直方图。")
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("指针下像素的红、绿、蓝值。")
        }
    }

    private var readout: String {
        guard let value = session.filterEdit?.cameraRawReadout else { return "R —   G —   B —" }
        return "R \(value.red)   G \(value.green)   B \(value.blue)"
    }

    private func clipButton(shadows: Bool) -> some View {
        let on = shadows ? session.filterEdit?.showsShadowClipping == true : session.filterEdit?.showsHighlightClipping == true
        return Button {
            if shadows { session.filterEdit?.showsShadowClipping.toggle() }
            else { session.filterEdit?.showsHighlightClipping.toggle() }
            if let edit = session.filterEdit { session.updateFilter(edit.settings, preview: edit.preview) }
        } label: {
            Image(systemName: "triangle.fill")
                .font(.caption2)
                .foregroundStyle(on ? (shadows ? Color.blue : Color.red) : Color.white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(shadows ? "在预览中以蓝色显示剪切阴影。" : "在预览中以红色显示剪切高光。")
        .accessibilityLabel(shadows ? "阴影剪切指示器" : "高光剪切指示器")
    }

    private func graph(_ scope: CameraRawScope?, mode: CameraRawScopeMode) -> some View {
        Canvas { context, size in
            guard let scope else { return }
            switch mode {
            case .histogram:
                let peak = scope.peak
                guard peak > 0 else { return }
                ribbon(scope.red, color: .red, peak: peak, in: context, size: size)
                ribbon(scope.green, color: .green, peak: peak, in: context, size: size)
                ribbon(scope.blue, color: .blue, peak: peak, in: context, size: size)
            case .vectorscope:
                let peak = scope.vectorscope.max() ?? 0
                guard peak > 0 else { return }
                let cell = size.width / CGFloat(CameraRawScope.scopeSide)
                for index in scope.vectorscope.indices where scope.vectorscope[index] > 0 {
                    let column = index % CameraRawScope.scopeSide
                    let row = index / CameraRawScope.scopeSide
                    let amount = min(1, scope.vectorscope[index] / peak)
                    let rect = CGRect(x: CGFloat(column) * cell, y: size.height - CGFloat(row + 1) * cell, width: cell + 0.2, height: cell + 0.2)
                    context.fill(Path(rect), with: .color(.white.opacity(0.15 + 0.85 * amount)))
                }
            }
        }
        .accessibilityLabel(mode == .histogram ? "RGB 直方图" : "矢量图")
    }

    private func ribbon(_ bins: [Double], color: Color, peak: Double, in context: GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for index in bins.indices {
            let x = CGFloat(index) * size.width / CGFloat(bins.count)
            let height = size.height * min(1, max(0, bins[index] / peak))
            path.addLine(to: CGPoint(x: x, y: size.height - height))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.55)))
    }

    @ViewBuilder private func disclosure(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded.contains(section) ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Text(section.rawValue).font(.headline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
                Spacer(minLength: 0)
                if section == .light, raw.adjustsLight { eye(shown: session.filterEdit?.showsCameraRawLight ?? true, name: "亮度", group: .light) }
                if section == .color, raw.adjustsColor { eye(shown: session.filterEdit?.showsCameraRawColor ?? true, name: "颜色", group: .color) }
                if section == .effects, raw.adjustsEffects { eye(shown: session.filterEdit?.showsCameraRawEffects ?? true, name: "效果", group: .effects) }
                if section == .curve, raw.adjustsCurve { eye(shown: session.filterEdit?.showsCameraRawCurve ?? true, name: "曲线", group: .curve) }
                if section == .colorMixer, raw.adjustsMixer { eye(shown: session.filterEdit?.showsCameraRawMixer ?? true, name: "混色器", group: .mixer) }
                if section == .colorGrading, raw.adjustsGrading { eye(shown: session.filterEdit?.showsCameraRawGrading ?? true, name: "颜色分级", group: .grading) }
                if section == .detail, raw.adjustsDetail { eye(shown: session.filterEdit?.showsCameraRawDetail ?? true, name: "细节", group: .detail) }
                if section == .optics, raw.adjustsOptics { eye(shown: session.filterEdit?.showsCameraRawOptics ?? true, name: "光学", group: .optics) }
                if section == .geometry, raw.adjustsGeometry { eye(shown: session.filterEdit?.showsCameraRawGeometry ?? true, name: "几何", group: .geometry) }
                if section == .calibration, raw.adjustsCalibration { eye(shown: session.filterEdit?.showsCameraRawCalibration ?? true, name: "校准", group: .calibration) }
            }
            if expanded.contains(section) {
                switch section {
                case .light: lightControls.padding(.leading, 18)
                case .color: colorControls.padding(.leading, 18)
                case .effects: effectsControls.padding(.leading, 18)
                case .curve: CameraRawCurveControls(session: session).padding(.leading, 18)
                case .colorMixer: CameraRawMixerControls(session: session).padding(.leading, 18)
                case .colorGrading: CameraRawGradingControls(session: session).padding(.leading, 18)
                case .detail: CameraRawDetailControls(session: session).padding(.leading, 18)
                case .optics: CameraRawOpticsControls(session: session).padding(.leading, 18)
                case .geometry: CameraRawGeometryControls(session: session).padding(.leading, 18)
                case .calibration: CameraRawCalibrationControls(session: session).padding(.leading, 18)
                }
            }
        }
    }

    private var lightControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            slider("曝光", \.exposure, range: CameraRawSettings.exposureRange, decimals: 2, clipping: .highlights,
                   help: "以曝光档为单位提亮或压暗整张图片。按住 Option 可查看剪切高光。")
            slider("对比度", \.contrast, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   help: "加大或减小亮部与暗部的差异，主要影响中间调。")
            slider("高光", \.highlights, range: CameraRawSettings.toneRange, decimals: 0, clipping: .highlights,
                   help: "调整图片的亮部。按住 Option 可查看剪切高光。")
            slider("阴影", \.shadows, range: CameraRawSettings.toneRange, decimals: 0, clipping: .shadows,
                   help: "调整图片的暗部。按住 Option 可查看剪切阴影。")
            slider("白色", \.whites, range: CameraRawSettings.toneRange, decimals: 0, clipping: .highlights,
                   help: "设置最亮的点。按住 Option 可查看剪切高光。")
            slider("黑色", \.blacks, range: CameraRawSettings.toneRange, decimals: 0, clipping: .shadows,
                   help: "设置最暗的点。按住 Option 可查看剪切阴影。")
        }
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("白平衡").frame(minWidth: Self.labelWidth, alignment: .leading)
                    .help("自动按平均颜色平衡。自定则跟随色温和色调。")
                Picker("白平衡", selection: Binding(get: { raw.whiteBalance }, set: setWhiteBalance)) {
                    ForEach(CameraRawWhiteBalance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .help("自动按平均颜色平衡。自定则跟随色温和色调。")
                Button {
                    session.filterEdit?.samplesWhiteBalance.toggle()
                    session.brushRevision += 1
                } label: {
                    Image(systemName: "eyedropper")
                }
                .buttonStyle(.borderless)
                .tint(session.filterEdit?.samplesWhiteBalance == true ? Color.accentColor : Color.secondary)
                .help("点按一个应为中性的像素。")
                .accessibilityLabel("白平衡取样器")
            }
            if session.filterEdit?.samplesWhiteBalance == true {
                Text("点按原图层。再次点按吸管可停止。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            slider("色温", \.temperature, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   track: .temperature, help: "让图片在蓝色与黄色之间偏移。")
            slider("色调", \.tint, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   track: .tint, help: "让图片在绿色与品红之间偏移。")
            slider("自然饱和度", \.vibrance, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   track: .chroma, help: "对较弱颜色的增强强于已经鲜艳的颜色，并保护肤色。")
            slider("饱和度", \.saturation, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   track: .chroma, help: "以相同幅度增强或减弱所有颜色。")
        }
    }

    private var effectsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            slider("纹理", \.texture, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   help: "增加或柔化细小的细节。")
            slider("清晰度", \.clarity, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   help: "增加或柔化较大形状的对比度。")
            slider("去除薄雾", \.dehaze, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   help: "调高可去除薄雾，调低则增加薄雾。")
            Text("辉光").font(.subheadline)
            slider("辉光", \.glow, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                   help: "从明亮区域扩散出辉光。")
            Picker("样式", selection: Binding(get: { raw.glowStyle }, set: { style in update { $0.cameraRaw.glowStyle = style } })) {
                ForEach(CameraRawGlowStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .help("漫射柔和而宽广，柔焦更集中，光晕是红色边缘。")
            VStack(alignment: .leading, spacing: 8) {
                slider("范围", \.glowRange, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                       help: "选择多亮的区域才会产生辉光。在调高辉光之前没有作用。")
                slider("扩散", \.glowSpread, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                       help: "设置辉光扩散的距离。在调高辉光之前没有作用。")
                slider("暖色", \.glowWarmth, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                       help: "让辉光在冷暖之间偏移。光晕保持红色。在调高辉光之前没有作用。")
            }
            .padding(.leading, 16)
            Text("晕影").font(.subheadline)
            slider("数量", \.vignetteAmount, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                   help: "压暗或提亮边缘。中心不变。")
            Picker("样式", selection: Binding(get: { raw.vignetteStyle }, set: { style in update { $0.cameraRaw.vignetteStyle = style } })) {
                ForEach(CameraRawVignetteStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .help("高光优先保护明亮边缘。颜色优先还会减少颜色。绘画叠加均匀覆盖边缘。")
            VStack(alignment: .leading, spacing: 8) {
                slider("中点", \.vignetteMidpoint, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                       reset: 50, help: "设置晕影从中心向外开始的位置。")
                slider("圆度", \.vignetteRoundness, range: CameraRawSettings.toneRange, decimals: 0, clipping: nil,
                       help: "让晕影更圆或更方。")
                slider("羽化", \.vignetteFeather, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                       reset: 50, help: "柔化晕影的边缘。")
                slider("高光", \.vignetteHighlights, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                       help: "应用暗晕影时保护明亮像素。供高光优先使用。")
            }
            .padding(.leading, 16)
            Text("颗粒").font(.subheadline)
            slider("数量", \.grainAmount, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                   help: "添加胶片颗粒，中间调最明显。")
            slider("大小", \.grainSize, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                   reset: 25, help: "让颗粒更粗或更细。")
            slider("粗糙度", \.grainRoughness, range: CameraRawSettings.unitRange, decimals: 0, clipping: nil,
                   reset: 50, help: "让颗粒更平滑或更不均匀。")
        }
    }

    private func eye(shown: Bool, name: String, group: PanelEye) -> some View {
        Button {
            switch group {
            case .light: session.filterEdit?.showsCameraRawLight.toggle()
            case .color: session.filterEdit?.showsCameraRawColor.toggle()
            case .effects: session.filterEdit?.showsCameraRawEffects.toggle()
            case .curve: session.filterEdit?.showsCameraRawCurve.toggle()
            case .mixer: session.filterEdit?.showsCameraRawMixer.toggle()
            case .grading: session.filterEdit?.showsCameraRawGrading.toggle()
            case .detail: session.filterEdit?.showsCameraRawDetail.toggle()
            case .optics: session.filterEdit?.showsCameraRawOptics.toggle()
            case .geometry: session.filterEdit?.showsCameraRawGeometry.toggle()
            case .calibration: session.filterEdit?.showsCameraRawCalibration.toggle()
            }
            if let edit = session.filterEdit { session.updateFilter(edit.settings, preview: edit.preview) }
        } label: {
            Image(systemName: shown ? "eye" : "eye.slash")
        }
        .buttonStyle(.borderless)
        .help(shown ? "在预览中隐藏\(name)" : "在预览中显示\(name)")
        .accessibilityLabel(shown ? "隐藏\(name)" : "显示\(name)")
    }

    private func slider(_ title: String, _ key: WritableKeyPath<CameraRawSettings, Double>, range: ClosedRange<Double>,
                        decimals: Int, clipping: CameraRawClipping?, track: CameraRawSliderTrack = .plain,
                        reset resetValue: Double = 0, help: String) -> some View {
        let step = pow(10, Double(decimals))
        return HStack(spacing: 10) {
            Text(title)
                .frame(minWidth: Self.labelWidth, alignment: .leading)
                .help(help)
                .onTapGesture(count: 2) { reset(key, to: resetValue) }
                .scrubbable(sensitivity: 1 / step,
                            value: Binding(get: { raw[keyPath: key] }, set: { assign(key, $0, clipping: nil) }),
                            range: range)
            CameraRawSlider(value: raw[keyPath: key], range: range, track: track, help: help,
                            onChange: { rawValue in assign(key, (rawValue * step).rounded() / step, clipping: clipping) },
                            onReset: { reset(key, to: resetValue) })
            TextField(title, value: Binding(get: { raw[keyPath: key] }, set: { assign(key, $0, clipping: nil) }),
                      format: .number.precision(.fractionLength(0...decimals)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .help(help)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func setWhiteBalance(_ mode: CameraRawWhiteBalance) {
        if mode == .auto {
            Task { await session.applyCameraRawAutoWhiteBalance() }
            return
        }
        update { settings in
            settings.cameraRaw.whiteBalance = mode
        }
    }

    private func assign(_ key: WritableKeyPath<CameraRawSettings, Double>, _ newValue: Double, clipping: CameraRawClipping?) {
        let showClipping = clipping != nil && NSEvent.modifierFlags.contains(.option)
        session.filterEdit?.cameraRawClipping = showClipping ? clipping : nil
        update { settings in
            settings.cameraRaw[keyPath: key] = newValue
            if key == \.temperature || key == \.tint { settings.cameraRaw.whiteBalance = .custom }
        }
    }

    private func reset(_ key: WritableKeyPath<CameraRawSettings, Double>, to resetValue: Double) {
        session.filterEdit?.cameraRawClipping = nil
        assign(key, resetValue, clipping: nil)
    }

    private enum PanelEye { case light, color, effects, curve, mixer, grading, detail, optics, geometry, calibration }

    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: session.filterEdit?.preview ?? true)
    }

    private func installOptionMonitor() {
        removeOptionMonitor()
        optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if !event.modifierFlags.contains(.option) {
                let edit = session.filterEdit
                if edit?.cameraRawClipping != nil || edit?.cameraRawSharpenMask == true {
                    edit?.cameraRawClipping = nil
                    edit?.cameraRawSharpenMask = false
                    if let edit { session.updateFilter(edit.settings, preview: edit.preview) }
                }
            }
            return event
        }
    }

    private func removeOptionMonitor() {
        if let optionMonitor { NSEvent.removeMonitor(optionMonitor) }
        optionMonitor = nil
    }

    static let labelWidth: CGFloat = 96

    private enum Section: String, CaseIterable, Identifiable {
        case light = "亮度"
        case color = "颜色"
        case colorGrading = "颜色分级"
        case effects = "效果"
        case curve = "曲线"
        case colorMixer = "混色器"
        case detail = "细节"
        case optics = "光学"
        case geometry = "几何"
        case calibration = "校准"
        var id: String { rawValue }
    }
}
