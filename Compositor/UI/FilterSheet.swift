import AppKit
import SwiftUI

/// The open filter's panel: its settings, Preview, and Cancel / OK.
struct FilterSheet: View {
    @Bindable var session: EditorSession
    private var edit: FilterEdit? { session.filterEdit }
    private var settings: FilterSettings { edit?.settings ?? FilterSettings() }
    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: edit?.preview ?? true)
    }

    private var isCameraRaw: Bool { edit?.kind == .cameraRaw }
    /// The widest slider title in the panel, so every slider starts and ends in the same place.
    @State private var labelWidth: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch edit?.kind ?? .gaussianBlur {
            case .curves:
                CurvesControls(settings: Binding(get: { settings.curves }, set: { new in update { $0.curves = new } }))
            case .exposure:
                control("曝光度", \.exposure.exposure, range: ExposureSettings.exposureRange, unit: "", decimals: 2, logarithmic: false)
                control("位移", \.exposure.offset, range: ExposureSettings.offsetRange, unit: "", decimals: 4, logarithmic: false)
                control("灰度系数", \.exposure.gamma, range: ExposureSettings.gammaRange, unit: "", decimals: 2, logarithmic: true)
            case .gradientMap:
                GradientMapControls(settings: Binding(get: { settings.gradientMap }, set: { new in update { $0.gradientMap = new } }),
                                    pick: { session.openGradientMapColorPicker(highlights: $0) })
            case .blackWhite:
                // Each slider says how bright that family of colors becomes, as Photoshop's do.
                control("红色", \.blackWhite.reds, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(0))
                control("黄色", \.blackWhite.yellows, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(60))
                control("绿色", \.blackWhite.greens, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(120))
                control("青色", \.blackWhite.cyans, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(180))
                control("蓝色", \.blackWhite.blues, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(240))
                control("洋红", \.blackWhite.magentas, range: BlackWhiteSettings.range, unit: "%", decimals: 0, logarithmic: false, track: .luminance(300))
                Toggle("色调", isOn: flag(\.blackWhite.tint))
                    .help("在保留明暗关系的同时为结果上色，可做出褐色调或蓝晒效果")
                if settings.blackWhite.tint {
                    control("色相", \.blackWhite.tintHue, range: 0...360, unit: "°", decimals: 0, logarithmic: false, track: .plain)
                    control("饱和度", \.blackWhite.tintSaturation, range: 0...100, unit: "%", decimals: 0, logarithmic: false,
                            track: .saturation(settings.blackWhite.tintHue))
                }
            case .cameraRaw:
                CameraRawControls(session: session)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .colorBalance:
                Text("阴影").font(.headline)
                control("青色 / 红色", \.colorBalance.shadowCyanRed, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.cyanRedTrack)
                control("洋红 / 绿色", \.colorBalance.shadowMagentaGreen, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.magentaGreenTrack)
                control("黄色 / 蓝色", \.colorBalance.shadowYellowBlue, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.yellowBlueTrack)
                Text("中间调").font(.headline)
                control("青色 / 红色", \.colorBalance.midCyanRed, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.cyanRedTrack)
                control("洋红 / 绿色", \.colorBalance.midMagentaGreen, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.magentaGreenTrack)
                control("黄色 / 蓝色", \.colorBalance.midYellowBlue, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.yellowBlueTrack)
                Text("高光").font(.headline)
                control("青色 / 红色", \.colorBalance.highlightCyanRed, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.cyanRedTrack)
                control("洋红 / 绿色", \.colorBalance.highlightMagentaGreen, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.magentaGreenTrack)
                control("黄色 / 蓝色", \.colorBalance.highlightYellowBlue, range: ColorBalanceSettings.range, unit: "", decimals: 0, logarithmic: false, track: Self.yellowBlueTrack)
                Toggle("保留明度", isOn: flag(\.colorBalance.preserveLuminosity))
                    .help("调整后恢复每个像素的亮度，只改变颜色")
            case .grain:
                control("数量", \.grain.amount, range: GrainSettings.amountRange, unit: "", decimals: 0, logarithmic: false)
                control("大小", \.grain.size, range: GrainSettings.sizeRange, unit: "px", decimals: 1, logarithmic: true)
                control("粗糙度", \.grain.roughness, range: GrainSettings.roughnessRange, unit: "", decimals: 0, logarithmic: false)
            case .removeBackground:
                Text("将背景隐藏到图层蒙版之后，保留前景主体。像素不会被删除，随时可以重新绘制背景。")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("质量", selection: Binding(get: { settings.backgroundQuality },
                                                     set: { new in update { $0.backgroundQuality = new } })) {
                    ForEach(BackgroundQuality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .help("“基本”速度更快；“高级”会参照图层自身细节优化蒙版，适合毛发")
                if settings.backgroundQuality == .advanced {
                    control("优化", \.refineEdges, range: 0...40, unit: "px", decimals: 0, logarithmic: false)
                        .help("让蒙版贴合图像自身的边缘，可恢复毛发细节")
                    control("对比度", \.matteContrast, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                        .help("清除让背景从薄弱区域透出的灰雾")
                    control("移动边缘", \.shiftEdge, range: -10...10, unit: "px", decimals: 0, logarithmic: false)
                        .help("收缩蒙版以去掉主体周围的背景色边缘，或向外扩展")
                }
            case .contentAwareFill:
                Text("使用该图层周围的像素填充选区。")
                    .fixedSize(horizontal: false, vertical: true)
            case .gaussianBlur:
                control("半径", \.radius, range: 0.1...250, unit: "px", decimals: 1, logarithmic: true)
                Toggle("保留透明", isOn: flag(\.preserveTransparency))
                    .help("只模糊颜色，保持图层的轮廓和透明区域不变")
            case .progressiveBlur:
                Text("在画布上点按并拖出两个点")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text("形状")
                    Picker("形状", selection: flag(\.progressiveRadial)) {
                        Text("线性").tag(false)
                        Text("径向").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("线性沿线条方向渐变模糊；径向保持起点清晰、向外逐渐模糊")
                }
                control("起点", \.progressiveFrom, range: 0...250, unit: "px", decimals: 1, logarithmic: false)
                    .help("线条起点处的模糊量")
                control("终点", \.progressiveTo, range: 0...250, unit: "px", decimals: 1, logarithmic: false)
                    .help("线条终点及之外的模糊量")
                Toggle("反转", isOn: flag(\.progressiveInverted))
                    .help("交换起点和终点：起点模糊、向终点逐渐清晰")
            case .rgbSplit:
                HStack(spacing: 10) {
                    Text("形状")
                    Picker("形状", selection: flag(\.rgbSplitRadial)) {
                        Text("线性").tag(false)
                        Text("径向").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("线性沿一个方向错位颜色；径向从中心向外错位，中心保持清晰")
                }
                if settings.rgbSplitRadial {
                    Text("在画布上点按或拖动来移动中心")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                control("距离", \.rgbSplitDistance, range: 0...200, unit: "px", decimals: 0, logarithmic: false)
                    .help("颜色错开的距离：红色偏向一侧，蓝色偏向另一侧")
                control("模糊", \.rgbSplitBlur, range: 0...400, unit: "px", decimals: 0, logarithmic: false)
                    .help("沿错位方向把颜色拖成条纹")
                if !settings.rgbSplitRadial {
                    control("角度", \.rgbSplitAngle, range: -180...180, unit: "°", decimals: 0, logarithmic: false)
                        .help("颜色错开的方向")
                }
            case .lensEffects:
                lensEffectsControls
            case .rimLight:
                rimLightControls
            case .motionBlur:
                control("角度", \.angle, range: -90...90, unit: "°", decimals: 0, logarithmic: false)
                control("距离", \.distance, range: 1...2000, unit: "px", decimals: 0, logarithmic: true)
            case .addNoise:
                control("数量", \.amount, range: 0.1...400, unit: "%", decimals: 1, logarithmic: true)
                HStack(spacing: 10) {
                    Text("分布")
                    Picker("分布", selection: flag(\.gaussian)) {
                        Text("平均").tag(false)
                        Text("高斯").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Toggle("单色", isOn: flag(\.monochromatic))
            case .dither:
                ditherControls
            case .scanlines:
                scanlinesControls
            case .vignette:
                HStack(spacing: 8) {
                    Text("颜色").frame(width: 95, alignment: .leading)
                    Button { session.openVignetteColorPicker() } label: {
                        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                        shape.fill(Color(.sRGB, red: settings.vignetteColor.red,
                                         green: settings.vignetteColor.green, blue: settings.vignetteColor.blue))
                            .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1.5) }
                            .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                            .frame(width: 24, height: 24)
                            .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .help("选取暗角颜色")
                    Spacer()
                }
                control("数量", \.vignetteAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                    .help("将所选颜色混合到边缘，中心保持不变")
                control("中点", \.vignetteMidpoint, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                control("圆度", \.vignetteRoundness, range: -100...100, unit: "", decimals: 0, logarithmic: false)
                control("羽化", \.vignetteFeather, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                control("高光", \.vignetteHighlights, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                    .help("保护边缘附近的亮部区域")
            case .sharpen:
                control("数量", \.sharpenAmount, range: 0...300, unit: "%", decimals: 0, logarithmic: false)
                    .help("强化边缘和细节的程度")
                control("半径", \.sharpenRadius, range: 0.1...20, unit: "px", decimals: 1, logarithmic: true)
                    .help("锐化细节的精细程度：小值突出清晰纹理，大值效果更强烈")
            case .bloomGlow:
                control("数量", \.bloomAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                control("半径", \.bloomRadius, range: 1...150, unit: "px", decimals: 0, logarithmic: true)
            case .tonalContrast:
                control("数量", \.tonalAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                control("阴影", \.tonalShadows, range: -100...100, unit: "%", decimals: 0, logarithmic: false)
                control("中间调", \.tonalMidtones, range: -100...100, unit: "%", decimals: 0, logarithmic: false)
                control("高光", \.tonalHighlights, range: -100...100, unit: "%", decimals: 0, logarithmic: false)
                control("半径", \.tonalRadius, range: 1...100, unit: "px", decimals: 0, logarithmic: true)
            case .lensCorrection:
                control("移除畸变", \.distortion, range: -100...100, unit: "", decimals: 0, logarithmic: false)
                Text("正值校正向外弯曲的线条（桶形畸变）；负值校正向内弯曲的线条（枕形畸变）。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("预览", isOn: Binding(get: { edit?.preview ?? true },
                                            set: { session.updateFilter(settings, preview: $0) }))
            if let error = edit?.previewError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if session.adjustmentOriginal == nil && session.selection != nil {
                Text("仅应用于选区").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("取消") { session.cancelFilter() }.configuredNativeShortcut(.escape)
                // The utility beside the effect: the layer's own channels, unshifted, as layers for Export As › Channel Pack.
                // Not on an RGB Split adjustment layer, which has no pixels of its own to split.
                if edit?.kind == .rgbSplit, session.adjustmentOriginal == nil {
                    Button("拆分为图层") {
                        session.cancelFilter()
                        session.splitChannels()
                    }
                    .help("将图层的原始通道拆分为红、绿、蓝和 Alpha 四个灰度图层，供「导出为 › Channel Pack」使用。完全透明像素下的颜色无法恢复")
                }
                Spacer()
                // While the preview is being worked out (Remove Background's mask, Content-Aware Fill) OK waits, so
                // the panel says what it is waiting for rather than showing a disabled button and nothing else.
                // Only the slow filters say so: a quick preview (Dither, a blur) toggling this at every slider step would
                // make the panel flicker as it grows and shrinks.
                if edit?.committing == true || (edit?.preparing == true && edit?.kind.isAutomatic == true) {
                    ProgressView().controlSize(.small)
                    Text(edit?.committing == true ? "正在应用…" : "正在处理…")
                        .font(.callout).foregroundStyle(.secondary)
                } else if let edit, edit.kind == .rimLight, edit.preparing, !RimLighting.hasSubject(for: edit.hdrPreviewSource ?? edit.previewSource) {
                    // Only the first preview, which finds the subject: relighting it afterwards is quick.
                    ProgressView().controlSize(.small)
                    Text("正在识别主体…").font(.callout).foregroundStyle(.secondary)
                }
                Button("确定") { Task { await session.commitFilter() } }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
                    .disabled(edit?.kind.isAutomatic == true && (edit?.preparing == true || edit?.previewError != nil))
            }
        }
        .onPreferenceChange(LabelWidthKey.self) { labelWidth = max(60, $0) }
        .padding(24)
        .frame(width: isCameraRaw ? FloatingPanelController.dockedWidth : 380)
        .frame(maxHeight: isCameraRaw ? .infinity : nil, alignment: .top)
        .fixedSize(horizontal: false, vertical: !isCameraRaw)

        .disabled(edit?.committing == true)
        // Filter colors preview live while the app's color picker is open.
        .onChange(of: session.colorPicker?.color) { _, _ in
            session.previewGradientMapColor()
            session.previewVignetteColor()
            session.previewRimLightColor()
            session.previewDitherColor()
        }
    }

    @ViewBuilder private var ditherControls: some View {
        let dither = settings.dither
        Picker("样式", selection: Binding(get: { dither.style }, set: { new in update { $0.dither.style = new } })) {
            ForEach(DitherStyle.groups.indices, id: \.self) { group in
                if group > 0 { Divider() }
                ForEach(DitherStyle.groups[group], id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
        if dither.style.usesPixelSize {
        control("像素大小", \.dither.pixelSize, range: DitherSettings.pixelSizeRange, unit: "px", decimals: 0, logarithmic: false)
            .help("让每个抖动像素达到这个宽度，呈现粗糙的老屏幕效果")
        }
        if dither.style == .ascii {
            control("文字大小", \.dither.textSize, range: DitherSettings.textSizeRange, unit: "px", decimals: 0, logarithmic: false)
                .help("每行字符的高度")
        }

        if dither.style.isHalftone {
            control("单元大小", \.dither.cellSize, range: DitherSettings.cellSizeRange, unit: "px", decimals: 0, logarithmic: false)
        }
        if dither.style.isHalftone {
            control("角度", \.dither.angle, range: -90...90, unit: "°", decimals: 0, logarithmic: false)
        }
        if dither.style == .ascii {
            HStack(spacing: 10) {
                Text("字符")
                TextField("字符", text: Binding(get: { dither.characters }, set: { new in update { $0.dither.characters = new } }))
                    .textFieldStyle(.roundedBorder).font(.body.monospaced())
            }
            .help("用于绘制的字符，顺序不限：每个位置都会选用油墨量与其明暗最匹配的字符")
        }
        if dither.style.hasTones {
            control("色调", \.dither.levels, range: DitherSettings.levelsRange, unit: "", decimals: 0, logarithmic: false)
                .help("每通道的色调数：2 为纯黑白")
        }
        if dither.style.diffuses {
            control("扩散", \.dither.diffusion, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("每个像素的误差扩散到相邻像素的比例。数值越小，区域越平坦")
        }
        control("密度", \.dither.density, range: -100...100, unit: "", decimals: 0, logarithmic: false)
            .help("抖动前增加油墨（更暗）或减少油墨")
        control("对比度", \.dither.contrast, range: -100...100, unit: "", decimals: 0, logarithmic: false)
        // A menu, like Style: the three choices as segments are wider than the panel, which then flips between
        // squeezing the row and wrapping it, resizing itself at every slider step.
        Picker("颜色", selection: Binding(get: { dither.colors }, set: { new in update { $0.dither.colors = new } })) {
            ForEach(DitherColors.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        if dither.colors == .twoColors {
            HStack(spacing: 8) {
                Text("深色")
                swatch(dither.dark, help: "选取深色") { session.openDitherColorPicker(light: false) }
                Text("浅色").padding(.leading, 10)
                swatch(dither.light, help: "选取浅色") { session.openDitherColorPicker(light: true) }
                Spacer()
            }
        }
        if dither.pixelSize > 1, dither.style.usesPixelSize {
            Picker("像素形状", selection: Binding(get: { dither.pixelShape }, set: { new in update { $0.dither.pixelShape = new } })) {
                ForEach(DitherPixelShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            .help("把每个粗像素画成实心方块，或像点阵屏幕一样的圆点")
        }
        if dither.style.drawsMarks {
            Toggle("暗底亮色", isOn: flag(\.dither.lightOnDark))
                .help("在深色上绘制亮色调的纹样，像发光的屏幕")
        }
    }

    @ViewBuilder private var scanlinesControls: some View {
        let lines = settings.scanlines
        control("行距", \.scanlines.lineSpacing, range: ScanlinesSettings.lineSpacingRange, unit: "px", decimals: 0, logarithmic: false)
            .help("屏幕上各线条之间的间距")
        control("粗细", \.scanlines.thickness, range: 5...100, unit: "%", decimals: 0, logarithmic: false)
            .help("亮部线条填满间隙的程度；暗部的线条画得更细")
        control("辉光", \.scanlines.glow, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("线条周围的光晕，类似 CRT 的荧光粉")
        control("点阵", \.scanlines.dots, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("比此值暗的区域把线条打成光点，亮部则融入实线")
        control("位移", \.scanlines.displace, range: ScanlinesSettings.displaceRange, unit: "px", decimals: 0, logarithmic: false)
            .help("亮部把线条抬高（负值则压低），让线条随画面起伏")
        control("平滑度", \.scanlines.smoothness, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("位移前对亮度的平滑程度，从尖锐棱线到圆润山丘")
        control("阈值", \.scanlines.threshold, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("比此值暗的区域不画线条，屏幕保持黑暗")
        control("摆动", \.scanlines.wobble, range: ScanlinesSettings.wobbleRange, unit: "px", decimals: 0, logarithmic: false)
            .help("让线条在屏幕上左右摆动，像 CRT 失去同步")
        control("色彩分离", \.scanlines.split, range: ScanlinesSettings.splitRange, unit: "px", decimals: 0, logarithmic: false)
            .help("把红色和蓝色通道错开，在线条上形成彩色镶边")
        control("密度", \.scanlines.density, range: -100...100, unit: "", decimals: 0, logarithmic: false)
            .help("画线前把画面调暗或调亮")
        control("对比度", \.scanlines.contrast, range: -100...100, unit: "", decimals: 0, logarithmic: false)
        control("黑场", \.scanlines.blackLevel, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("画面纯黑处线条的亮度，让黑色上也能看到线条")
        Picker("颜色", selection: Binding(get: { lines.colors }, set: { new in update { $0.scanlines.colors = new } })) {
            ForEach(DitherColors.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        if lines.colors == .twoColors {
            HStack(spacing: 8) {
                Text("深色")
                swatch(lines.dark, help: "选取屏幕的颜色") { session.openDitherColorPicker(light: false) }
                Text("浅色").padding(.leading, 10)
                swatch(lines.light, help: "选取线条的颜色") { session.openDitherColorPicker(light: true) }
                Spacer()
            }
        }
    }

    private func swatch(_ color: AdjustmentColor, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            shape.fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1.5) }
                .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                .frame(width: 24, height: 24)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Lens Effects: which effect, then its own settings.
    /// Rim Light: Glow, then each light's color, angle, strength, width and choke, with room for up to three.
    @ViewBuilder private var rimLightControls: some View {
        let rim = settings.rimLight
        control("辉光", \.rimLight.glow, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            .help("让光在主体周围的空气中晕染，使其融入背景")
        ForEach(Array(rim.lights.enumerated()), id: \.element.id) { index, light in
            Divider()
            HStack(spacing: 8) {
                Text("光源 \(index + 1)").font(.headline)
                Spacer()
                let color = light.color
                Button { session.openRimLightColorPicker(index: index) } label: {
                    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                    shape.fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                        .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1.5) }
                        .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                        .frame(width: 24, height: 24)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .help("选择此光源的颜色")
                if rim.lights.count > 1 {
                    Button {
                        // A color still being picked belongs to the lights as they were numbered.
                        if case .rimLight = session.colorPicker?.target { session.closeColorPicker(commit: true) }
                        update { $0.rimLight.lights.removeAll { $0.id == light.id } }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("移除此光源")
                }
            }
            control("角度", \.rimLight[light: light.id].angle, range: -180...180, unit: "°", decimals: 0, logarithmic: false)
                .help("光从主体背后的哪个方向来：0° 为右侧，90° 为正上方")
            control("强度", \.rimLight[light: light.id].strength, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            control("宽度", \.rimLight[light: light.id].width, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光包裹主体边缘的程度")
            control("收缩", \.rimLight[light: light.id].choke, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光在内侧的结束方式：低值从边缘柔和渐隐，高值保持明亮并利落截止")
        }
        if rim.lights.count < RimLightSettings.maximumLights {
            Button("添加光源") {
                if case .rimLight = session.colorPicker?.target { session.closeColorPicker(commit: true) }
                update { $0.rimLight.lights.append($0.rimLight.nextLight) }
            }
            .help("再从另一侧给主体补光")
        }
    }

    @ViewBuilder private var lensEffectsControls: some View {
        HStack(spacing: 10) {
            Text("效果")
            Picker("效果", selection: Binding(get: { settings.lens.effect }, set: { new in update { $0.lens.effect = new } })) {
                ForEach(LensEffect.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        switch settings.lens.effect {
        case .anamorphicFlare:
            control("数量", \.lens.flareAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            control("长度", \.lens.flareLength, range: 1...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光斑条纹在画面中延伸的长度")
            control("阈值", \.lens.threshold, range: 50...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光源要多亮才会产生光斑；接近 100 时只有最大、最亮的光点")
            control("蓝色", \.lens.flareBlue, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("镜片镀膜使条纹沿长度偏蓝的程度；为 0 时保留光源本身的颜色")
        case .starburst:
            control("数量", \.lens.starAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            control("长度", \.lens.starLength, range: 2...40, unit: "%", decimals: 0, logarithmic: false)
                .help("星芒延伸的长度")
            control("阈值", \.lens.threshold, range: 50...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光源要多亮才会产生星芒；接近 100 时只有最大、最亮的光点")
            control("角度", \.lens.starAngle, range: -180...180, unit: "°", decimals: 0, logarithmic: false)
            HStack(spacing: 10) {
                Text("星芒数")
                Picker("星芒数", selection: Binding(get: { settings.lens.starPoints }, set: { new in update { $0.lens.starPoints = new } })) {
                    ForEach(LensEffectSettings.starPointChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("每个光源的星芒数量，如同镜头光圈叶片形成的效果")
            }
        case .mist:
            control("强度", \.lens.mistStrength, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光线散射的程度：亮部周围形成柔和光晕，暗部被轻轻提亮")
            control("大小", \.lens.mistSize, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光线扩散的范围")
        case .prism:
            control("数量", \.lens.prismAmount, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
            control("重影数", \.lens.prismCopies, range: 1...8, unit: "", decimals: 0, logarithmic: false)
                .help("画面重复的次数，每次更淡")
            control("偏移", \.lens.prismOffset, range: 0...50, unit: "%", decimals: 0, logarithmic: false)
                .help("各重影之间的距离")
            control("角度", \.lens.prismAngle, range: -180...180, unit: "°", decimals: 0, logarithmic: false)
                .help("重影排列的方向")
            control("模糊", \.lens.prismBlur, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("柔化重影，推得越远越模糊")
            control("色散", \.lens.prismFringe, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("像玻璃棱镜一样分离每个重影的红蓝通道；设为 0 时重影清晰无色散")
            HStack(spacing: 10) {
                Text("方向")
                Picker("方向", selection: Binding(get: { settings.lens.prismBothWays }, set: { new in update { $0.lens.prismBothWays = new } })) {
                    Text("单侧").tag(false)
                    Text("双侧").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("重影只出现在画面一侧，或向两侧展开")
            }
        case .bokeh:
            control("大小", \.lens.bokehRadius, range: LensEffectSettings.bokehSizes, unit: "%", decimals: 1, logarithmic: false)
                .help("失焦程度：每个光斑的大小")
            control("亮度", \.lens.bokehBrightness, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光点展开成光斑的亮度")
            control("光环", \.lens.bokehRing, range: 0...100, unit: "%", decimals: 0, logarithmic: false)
                .help("光斑边缘聚光的程度，类似某些镜头的成像")
            HStack(spacing: 10) {
                Text("形状")
                Picker("形状", selection: Binding(get: { settings.lens.bokehShape }, set: { new in update { $0.lens.bokehShape = new } })) {
                    ForEach(BokehShape.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
                .help("光圈的形状：全开时为圆形，光圈叶片形成六边形，变形宽银幕镜头为椭圆，或边缘处呈猫眼形")
            }
        }
    }

    private func flag(_ key: WritableKeyPath<FilterSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
    }

    /// The setting put back to its filter's default, as a double-click on a colored slider does.
    static func resetting(_ key: WritableKeyPath<FilterSettings, Double>, in settings: FilterSettings) -> FilterSettings {
        var value = settings
        value[keyPath: key] = FilterSettings()[keyPath: key]
        return value
    }

    static let cyanRedTrack = CameraRawSliderTrack.opposing(NSColor(srgbRed: 0.10, green: 0.72, blue: 0.80, alpha: 1),
                                                            NSColor(srgbRed: 0.86, green: 0.18, blue: 0.20, alpha: 1))
    static let magentaGreenTrack = CameraRawSliderTrack.opposing(NSColor(srgbRed: 0.80, green: 0.22, blue: 0.70, alpha: 1),
                                                                 NSColor(srgbRed: 0.24, green: 0.70, blue: 0.30, alpha: 1))
    static let yellowBlueTrack = CameraRawSliderTrack.opposing(NSColor(srgbRed: 0.95, green: 0.82, blue: 0.18, alpha: 1),
                                                               NSColor(srgbRed: 0.22, green: 0.40, blue: 0.92, alpha: 1))

    /// A slider plus an exact field. Logarithmic sliders give the small values used most most of the travel.
    /// A colored track draws the slider as Camera Raw's, where a double-click on the title or knob resets it.
    private func control(_ title: String, _ key: WritableKeyPath<FilterSettings, Double>, range: ClosedRange<Double>,
                         unit: String, decimals: Int, logarithmic: Bool, track: CameraRawSliderTrack? = nil) -> some View {
        let step = pow(10, Double(decimals))
        let reset = { update { $0 = Self.resetting(key, in: $0) } }
        return HStack(spacing: 10) {
            Text(title).fixedSize()
                .background(GeometryReader { Color.clear.preference(key: LabelWidthKey.self, value: $0.size.width) })
                .frame(width: labelWidth, alignment: .leading)
                .onTapGesture(count: 2) { if track != nil { reset() } }
                .scrubbable(sensitivity: 1 / step,
                            value: Binding(get: { settings[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } }),
                            range: range)
            if let track {
                CameraRawSlider(value: settings[keyPath: key], range: range, track: track,
                                help: "\(title)。双击可复位。",
                                onChange: { value in update { $0[keyPath: key] = (value * step).rounded() / step } },
                                onReset: reset)
            } else {
                Slider(value: Binding(get: { logarithmic ? log(settings[keyPath: key]) : settings[keyPath: key] },
                                      set: { value in update { $0[keyPath: key] = ((logarithmic ? exp(value) : value) * step).rounded() / step } }),
                       in: logarithmic ? log(range.lowerBound)...log(range.upperBound) : range)
            }
            TextField(title, value: Binding(get: { settings[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } }),
                      format: .number.precision(.fractionLength(0...decimals)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .unitSuffix(unit)
        }
    }
}

/// Gradient Map's two colors, the gradient they make, and Reverse. The colors are swatches like the
/// tool rail's, and open the app's own color picker.
struct GradientMapControls: View {
    @Binding var settings: GradientMapSettings
    /// Opens the color picker on an end: false for Shadows, true for Highlights.
    let pick: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let ends = settings.ends
            LinearGradient(colors: [color(ends.dark), color(ends.light)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.black.opacity(0.35)) }
                .accessibilityHidden(true)
            HStack(spacing: 20) {
                swatch("阴影", settings.shadows) { pick(false) }
                swatch("高光", settings.highlights) { pick(true) }
                Spacer()
            }
            Toggle("反向", isOn: $settings.reversed)
        }
    }

    private func color(_ value: AdjustmentColor) -> Color { Color(.sRGB, red: value.red, green: value.green, blue: value.blue) }

    private func swatch(_ title: String, _ value: AdjustmentColor, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 8) {
            Button(action: action) {
                shape
                    .fill(color(value))
                    .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1.5) }
                    .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                    .frame(width: 24, height: 24)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help("选取\(title)颜色")
            .accessibilityLabel("\(title)颜色")
            Text(title)
        }
    }
}

private struct LabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Chinese display names for the pickers; the raw values stay English because both enums are Codable
// and stored in project files.
private extension LensEffect {
    var displayName: String {
        switch self {
        case .anamorphicFlare: return "变形光斑"
        case .starburst: return "星芒"
        case .mist: return "薄雾"
        case .prism: return "棱镜"
        case .bokeh: return "焦外光斑"
        }
    }
}

private extension BokehShape {
    var displayName: String {
        switch self {
        case .round: return "圆形"
        case .hexagon: return "六边形"
        case .oval: return "椭圆形"
        case .catsEye: return "猫眼形"
        }
    }
}
