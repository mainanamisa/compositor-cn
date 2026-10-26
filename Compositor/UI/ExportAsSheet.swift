import SwiftUI
import UniformTypeIdentifiers

/// File › Export As…: the flattened canvas, or frame timelines driving it, sized and previewed as written.
struct ExportAsSheet: View {
    let raster: ExportRaster
    /// The same flattened at 16 bits a channel, when the document has a 16-bit layer to keep.
    let deepRaster: ExportRaster?
    /// The same flattened in half floats, when the document has an HDR layer: what an EXR is written from, the only
    /// format offered that keeps light brighter than white. Without one, EXR isn't offered.
    let hdrRaster: ExportRaster?
    /// The document's layers, which Channel Pack and GIF read; without it, neither is offered.
    let snapshot: ProjectSnapshot?
    private var formats: [ExportFormat] {
        ExportFormat.allCases.filter { ($0 != .exr || hdrRaster != nil) && (($0 != .channelPack && $0 != .gif) || snapshot != nil) }
    }
    let session: EditorSession
    let finish: ((data: Data, format: ExportFormat)?) -> Void
    @State private var format: ExportFormat
    @State private var options: JPEGOptions
    @State private var gifOptions: GIFExportOptions
    @State private var width: Int
    @State private var height: Int
    /// Channel Pack's red, green, blue and alpha, in that order.
    @State private var channels: [ChannelPack.Source]
    /// Each document's last Channel Pack choices, while the app is open.
    @MainActor private static var channelChoices: [UUID: [ChannelPack.Source]] = [:]
    /// JPEG's quality from the last export, which the next one starts from.
    private static let qualityKey = "jpegExportQuality"

    init(raster: ExportRaster, deepRaster: ExportRaster? = nil, hdrRaster: ExportRaster? = nil, snapshot: ProjectSnapshot? = nil,
         session: EditorSession, format: ExportFormat, finish: @escaping ((data: Data, format: ExportFormat)?) -> Void) {
        self.raster = raster
        self.snapshot = snapshot
        self.deepRaster = deepRaster
        self.hdrRaster = hdrRaster
        let layers = snapshot?.manifest.layers ?? []
        let remembered = snapshot.flatMap { Self.channelChoices[$0.manifest.documentID] }?
            .filter { if case .layer(let id) = $0 { layers.contains { $0.id == id } } else { true } }
        _channels = State(initialValue: remembered?.count == 4 ? remembered!
                          : ChannelPack.Channel.allCases.map { ChannelPack.defaultSource(for: $0, in: layers) })
        self.session = session
        self.finish = finish
        var start = JPEGOptions()
        if let saved = UserDefaults.standard.object(forKey: Self.qualityKey) as? Double, saved.isFinite {
            start.quality = min(1, max(0, saved))
        }
        _options = State(initialValue: start)
        _gifOptions = State(initialValue: GIFExportOptions())
        _format = State(initialValue: (format == .exr && hdrRaster == nil) || (format == .channelPack && snapshot == nil) ? .png : format)
        _width = State(initialValue: raster.image.width)
        _height = State(initialValue: raster.image.height)
    }

    /// What's written depends on these; a change makes a new preview.
    struct Settings: Equatable {
        var format: ExportFormat
        var options: JPEGOptions
        var gifOptions: GIFExportOptions
        var width: Int
        var height: Int
        var sixteenBit: Bool
        /// In this CMYK profile's inks, for print (JPEG, TIFF and PDF); nil for RGB.
        var cmyk: CMYKProfile?
        /// Channel Pack's sources; empty for the other formats.
        var channels: [ChannelPack.Source] = []
    }
    struct Encoded {
        let id = UUID()
        let settings: Settings
        let data: Data
        let preview: CGImage
        var durations: [TimeInterval] = []
    }
    private var settings: Settings {
        Settings(format: format, options: options, gifOptions: gifOptions, width: width, height: height, sixteenBit: sixteenBit && format == .png && deepRaster != nil,
                 cmyk: cmyk && takesCMYK ? profile : nil, channels: format == .channelPack ? channels : [])
    }
    /// The formats that can be written in a printer's inks.
    private var takesCMYK: Bool { format == .jpeg || format == .tiff || format == .pdf }
    /// CMYK for print: off each time, as most exports are for screens.
    @State private var cmyk = false
    /// The CMYK profile, as View › CMYK › Profile sets it.
    private var profile: CMYKProfile? { session.proofProfile ?? CMYK.chosen }
    /// A PNG at 16 bits a channel: off by default, it's about twice the size.
    @State private var sixteenBit = false
    @State private var result: Encoded?
    @State private var error: String?
    @State private var gifProgress: (completed: Int, total: Int)?
    @State private var gifPreviewImage: CGImage?
    @State private var gifPreviewIndex = 0
    @State private var isGIFPreviewPlaying = true
    private var isReady: Bool { result?.settings == settings && error == nil }
    /// The preview's zoom, 1 being 100%; nil fits the whole image.
    @State private var zoom: Double?
    @Environment(\.displayScale) private var displayScale
    private var shownZoom: Double {
        zoom ?? JPEGPreview.fitZoom(width: width, height: height, in: JPEGPreview.frame, displayScale: displayScale)
    }

    var body: some View { sheet.roundedControls() }
    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("导出为").font(.title2.bold())
                Spacer()
                if format == .gif, let result, result.durations.count > 1 {
                    Button {
                        if !isGIFPreviewPlaying, gifPreviewIndex == result.durations.count - 1, !gifOptions.loopsForever {
                            gifPreviewIndex = 0
                            gifPreviewImage = result.preview
                        }
                        isGIFPreviewPlaying.toggle()
                    } label: { Image(systemName: isGIFPreviewPlaying ? "pause.fill" : "play.fill").foregroundStyle(.white) }
                        .disabled(!isReady)
                        .help(isGIFPreviewPlaying ? "暂停动画预览。" : "播放动画预览。")
                        .accessibilityLabel(isGIFPreviewPlaying ? "暂停动画预览" : "播放动画预览")
                }
                Button("适应") { zoom = nil }.disabled(zoom == nil)
                    .help("显示整张图像（⌘0）")
                Button { zoomBy(1) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(JPEGPreview.step(from: shownZoom, in: 1) == nil)
                    .help("放大（⌘+），当前 \(percent)。100% 时导出的一个像素对应屏幕的一个像素")
                Button { zoomBy(-1) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(JPEGPreview.step(from: shownZoom, in: -1) == nil)
                    .help("缩小（⌘−），当前 \(percent)")
            }
            .padding(.bottom, -8)
            ZStack {
                Color(white: 0.12)
                if let result {
                    JPEGPreview(image: result.settings.format == .gif ? gifPreviewImage ?? result.preview : result.preview,
                                pixelWidth: result.settings.width, pixelHeight: result.settings.height, zoom: $zoom)
                }
                if !isReady && error == nil {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }.frame(width: JPEGPreview.frame.width, height: JPEGPreview.frame.height).clipped()
                .help("启用的蒙版会应用于此，与画布一致。拖动或滚动查看；双击在「适应」和 100% 之间切换")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("格式")
                    // The everyday formats side by side, JPEG first; the rest (PDF, and EXR with an HDR layer) in a menu beside them,
                    // which takes the chosen one's name.
                    HStack(spacing: 12) {
                        Picker("格式", selection: $format) {
                            ForEach([ExportFormat.jpeg, .png], id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        moreFormats
                    }
                }
                GridRow {
                    Text("尺寸")
                    HStack(spacing: 6) {
                        sizeField(width, set: setWidth).help("宽度（像素），高度按比例跟随")
                        Text("×").foregroundStyle(.secondary)
                        sizeField(height, set: setHeight).help("高度（像素），宽度按比例跟随")
                        Text("px").foregroundStyle(.secondary)
                        Menu("\(scalePercent)%") {
                            ForEach([25, 50, 75, 100, 200], id: \.self) { percent in
                                Button("\(percent)%") { setScale(Double(percent) / 100) }
                            }
                        }
                        .fixedSize().help("缩放导出结果；文档本身不变")
                    }
                }
                if format == .jpeg {
                    GridRow {
                        Text("质量")
                        HStack {
                            Slider(value: $options.quality, in: 0...1, step: 0.01).frame(width: 300)
                            Text("\(Int((options.quality * 100).rounded()))%").monospacedDigit().frame(width: 45, alignment: .trailing)
                        }
                    }
                }
                if format == .png, deepRaster != nil {
                    GridRow {
                        Text("位深")
                        Toggle("每通道 16 位", isOn: $sixteenBit)
                            .help("保留 16 位图层的全部精度，文件约为两倍大")
                    }
                }
                if takesCMYK {
                    GridRow {
                        Text("颜色")
                        HStack(spacing: 10) {
                            colorMenu
                            // CMYK goes through View › CMYK › Profile's profile, named under the settings; a printer's own
                            // can be loaded here too.
                            if cmyk {
                                Button("载入配置文件…") { loadProfile() }
                                    .help("使用 CMYK ICC 配置文件，例如印刷厂提供的那份")
                            }
                        }
                    }
                }
                if format == .channelPack {
                    ForEach(Array(ChannelPack.Channel.allCases.enumerated()), id: \.offset) { index, channel in
                        GridRow {
                            Text(channelName(channel))
                            channelPicker(index, channel: channel)
                        }
                    }
                }
                if format == .pdf {
                    GridRow {
                        Text("页面")
                        Text(pageSize).foregroundStyle(.secondary)
                    }
                }
                if format == .gif {
                    GridRow {
                        Text("循环")
                        Picker("循环", selection: $gifOptions.loopsForever) {
                            Text("永远").tag(true)
                            Text("一次").tag(false)
                        }.pickerStyle(.segmented).labelsHidden().fixedSize()
                            .disabled(!gifHasAnimation)
                    }
                    GridRow {
                        Text("透明度")
                        Toggle("保留透明区域", isOn: $gifOptions.keepsTransparency)
                            .help("GIF 只保留完全透明或完全不透明的像素；半透明边缘按 50% 阈值处理")
                    }
                    GridRow {
                        Text("帧")
                        Text(gifSummary).foregroundStyle(.secondary)
                    }
                }
                // JPEG has no transparency, and a PDF's page shows through it, so both fill it with a color.
                if format == .jpeg || format == .pdf || (format == .tiff && cmyk) || (format == .gif && !gifOptions.keepsTransparency) {
                    GridRow {
                        Text("背景")
                        DialogColorSwatch(title: "导出背景色", color: format == .gif ? gifMatte : matte, session: session)
                            .help("填充透明区域的颜色")
                    }
                }
            }
            HStack(spacing: 12) {
                Text(format == .channelPack ? "每个通道取自一个图层，按灰度读取 · PNG"
                     : format == .gif ? "最多 256 色 · sRGB" : format == .exr ? "保留高光与透明"
                     : takesCMYK && cmyk ? "CMYK – \(profile?.name ?? "无配置文件")"
                     : format == .png || format == .tiff ? "保留透明 · sRGB" : "sRGB")
                    .foregroundStyle(.secondary)
                Spacer()
                if isReady, let result {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(result.data.count), countStyle: .file)).monospacedDigit()
                } else if error == nil {
                    Text(format == .gif ? gifProgress.map { "正在编码第 \(min($0.completed + 1, $0.total)) 帧，共 \($0.total) 帧…" } ?? "更新中…" : "更新中…")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Button("取消") { DialogColorSwatch.closePicker(session); finish(nil) }.configuredNativeShortcut(.escape)
                Button("导出…") {
                    DialogColorSwatch.closePicker(session)
                    if format == .jpeg { UserDefaults.standard.set(options.quality, forKey: Self.qualityKey) }
                    if format == .channelPack, let snapshot { Self.channelChoices[snapshot.manifest.documentID] = channels }
                    if let result { finish((result.data, result.settings.format)) }
                }
                    .configuredNativeShortcut(.return)
                    .disabled(!isReady)
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).frame(maxWidth: JPEGPreview.frame.width, alignment: .leading) }
        }
        .padding(24)
        .onAppear {
            setScale(Double(width) / Double(raster.image.width))
            session.previewZoom = { command in
                switch command {
                case .zoomIn: zoomBy(1)
                case .zoomOut: zoomBy(-1)
                case .fit: zoom = nil
                case .actual: zoom = 1
                }
            }
        }
        .onDisappear { session.previewZoom = nil }
        .onChange(of: format) { setScale(Double(width) / Double(raster.image.width)) }
        .task(id: settings) {
            let requested = settings
            error = nil
            gifProgress = nil
            do {
                try await Task.sleep(for: .milliseconds(200))
                if requested.format == .gif, let snapshot {
                    let encoded = try await GIFExporter.shared.encode(snapshot, width: requested.width, height: requested.height,
                        options: requested.gifOptions) { completed, total in
                            await MainActor.run {
                                if settings == requested { gifProgress = (completed, total) }
                            }
                        }
                    try Task.checkCancellation()
                    gifPreviewIndex = 0
                    gifPreviewImage = encoded.preview
                    isGIFPreviewPlaying = true
                    result = Encoded(settings: requested, data: encoded.data, preview: encoded.preview, durations: encoded.durations)
                    return
                }
                if requested.format == .channelPack, let snapshot {
                    let packed = try await ImageExporter.shared.channelPack(snapshot, sources: requested.channels,
                                                                            width: requested.width, height: requested.height)
                    try Task.checkCancellation()
                    result = Encoded(settings: requested, data: packed.data, preview: packed.preview)
                    return
                }
                let source = requested.format == .exr ? hdrRaster ?? raster : requested.sixteenBit ? deepRaster ?? raster : raster
                let sized = try await ImageExporter.shared.resized(source, width: requested.width, height: requested.height)
                let data: Data, preview: CGImage
                switch requested.format {
                case .jpeg:
                    let encoded = try await ImageExporter.shared.jpeg(sized, options: requested.options, cmyk: requested.cmyk)
                    (data, preview) = (encoded.data, encoded.preview)
                case .tiff:
                    let matte = CGColor(srgbRed: requested.options.red, green: requested.options.green, blue: requested.options.blue, alpha: 1)
                    (data, preview) = try await ImageExporter.shared.tiffData(sized, cmyk: requested.cmyk, matte: matte)
                case .png, .channelPack: (data, preview) = (try await ImageExporter.shared.pngData(sized), sized.image)
                // Shown as everything is, brighter than white as white.
                case .exr: (data, preview) = (try await ImageExporter.shared.exrData(sized), try DeepLayer.dithered(sized.image))
                case .pdf:
                    let background = CGColor(srgbRed: requested.options.red, green: requested.options.green,
                                             blue: requested.options.blue, alpha: 1)
                    data = try await ImageExporter.shared.pdfData(sized, background: background, cmyk: requested.cmyk)
                    if let cmyk = requested.cmyk {
                        preview = try CMYK.convert(sized.image, to: cmyk, over: background)
                    } else {
                        preview = try await ImageExporter.shared.flattened(sized, over: background)
                    }
                case .gif: return
                }
                try Task.checkCancellation()
                result = Encoded(settings: requested, data: data, preview: preview)
            } catch is CancellationError {
                // A newer setting superseded this preview.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
        .task(id: GIFPreviewRequest(resultID: result?.id, isPlaying: isGIFPreviewPlaying, isReady: isReady)) {
            guard isReady, isGIFPreviewPlaying, let result, result.settings.format == .gif,
                  result.durations.count > 1 else { return }
            do {
                try await GIFPreviewPlayback.play(durations: result.durations, startingAt: gifPreviewIndex,
                                                   loops: result.settings.gifOptions.loopsForever) { index in
                    let image = try await GIFExporter.shared.preview(result.data, index: index)
                    try Task.checkCancellation()
                    gifPreviewIndex = index
                    gifPreviewImage = image
                }
                isGIFPreviewPlaying = false
            } catch is CancellationError {
                // A setting changed, playback paused, or the dialog closed.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private struct GIFPreviewRequest: Equatable {
        let resultID: UUID?
        let isPlaying: Bool
        let isReady: Bool
    }
    private var gifSchedule: GIFExportSchedule? { snapshot.flatMap { try? GIFExportSchedule($0, options: gifOptions) } }
    private var gifHasAnimation: Bool {
        guard let snapshot else { return false }
        return snapshot.gifExportLayers.contains { (snapshot.animations[$0.id]?.frames.count ?? 0) > 1 }
    }
    private var gifSummary: String {
        guard !(snapshot?.gifExportLayers ?? []).isEmpty else { return "1 帧 · 静止画布" }
        guard let schedule = gifSchedule else { return "—" }
        let count = "\(schedule.frames.count) 帧"
        let durations = schedule.durations
        return "\(count) · \(durations.reduce(0, +).formatted(.number.precision(.fractionLength(0...2)))) 秒"
    }

    /// RGB or CMYK: one small menu, as few need CMYK. The profile CMYK goes through is View › CMYK › Profile's, named in
    /// the line under the settings.
    private var colorMenu: some View {
        Menu(cmyk ? "CMYK" : "RGB") {
            Toggle("RGB", isOn: Binding(get: { !cmyk }, set: { if $0 { cmyk = false } }))
            Toggle("CMYK", isOn: Binding(get: { cmyk }, set: { if $0 { cmyk = true } }))
        }
        .menuStyle(.button).buttonStyle(.bordered).fixedSize()
        .help("CMYK 通过「显示 › CMYK › 配置文件」中的配置文件写入印刷油墨")
    }

    private func loadProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
        panel.message = "选择一个 CMYK ICC 配置文件，例如印刷厂提供的那份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { session.proofProfile = try CMYK.load(url) }
        catch { self.error = error.localizedDescription }
    }

    /// Animation formats, TIFF, PDF, and EXR with an HDR layer: a menu beside PNG and JPEG, blue with the chosen one's name while it's chosen,
    /// as the selected segment beside it would be.
    @ViewBuilder private var moreFormats: some View {
        let others = formats.filter { $0 != .png && $0 != .jpeg }
        let chosen = others.contains(format)
        let menu = Menu(chosen ? format.rawValue : "更多") {
            Picker("更多格式", selection: $format) {
                ForEach(others, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline).labelsHidden()
        }
        .menuStyle(.button).fixedSize()
        .help("其他格式：TIFF、PDF 和 GIF\(others.contains(.exr) ? "，以及保留高光的 EXR" : "")，还有用于游戏贴图的 Channel Pack")
        if chosen { menu.buttonStyle(.borderedProminent) } else { menu.buttonStyle(.bordered) }
    }

    /// A channel's name as the sheet shows it; the raw values stay English.
    private func channelName(_ channel: ChannelPack.Channel) -> String {
        switch channel {
        case .red: "红"
        case .green: "绿"
        case .blue: "蓝"
        case .alpha: "Alpha"
        }
    }

    /// A channel's source: one of the document's layers or groups, top first, or solid black or white.
    private func channelPicker(_ index: Int, channel: ChannelPack.Channel) -> some View {
        let layers = snapshot?.manifest.layers ?? []
        return Picker(channelName(channel), selection: $channels[index]) {
            Text("黑色").tag(ChannelPack.Source.black)
            Text("白色").tag(ChannelPack.Source.white)
            Divider()
            ForEach(layers.reversed().filter { $0.adjustment == nil }, id: \.id) { layer in
                Text(layer.name).tag(ChannelPack.Source.layer(layer.id))
            }
        }
        .labelsHidden().frame(width: 260)
        .help("填充\(channelName(channel))通道的内容：以灰度读取的图层或组，或纯黑、纯白")
    }

    private func sizeField(_ value: Int, set: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: set), format: .number.grouping(.never))
            .frame(width: 64).multilineTextAlignment(.trailing)
    }
    /// Both sides follow one, keeping the canvas's proportions, within the export limits.
    private func setWidth(_ value: Int) { setScale(Double(value) / Double(raster.image.width)) }
    private func setHeight(_ value: Int) { setScale(Double(value) / Double(raster.image.height)) }
    private func setScale(_ scale: Double) {
        let maximumSide = DocumentLimits.maxSide
        let largest = min(Double(maximumSide) / Double(max(raster.image.width, raster.image.height)),
                          (Double(DocumentLimits.maxSurfacePixels) / Double(raster.image.width * raster.image.height)).squareRoot())
        let clamped = min(largest, max(0.01, scale.isFinite ? scale : 1))
        width = max(1, Int((Double(raster.image.width) * clamped).rounded()))
        height = max(1, Int((Double(raster.image.height) * clamped).rounded()))
    }
    private var scalePercent: Int { Int((Double(width) / Double(raster.image.width) * 100).rounded()) }
    /// The PDF page: the export's pixels at the document's resolution.
    private var pageSize: String {
        let dpi = raster.resolution > 0 ? raster.resolution : 72
        let inches = { (pixels: Int) in (Double(pixels) / dpi).formatted(.number.precision(.fractionLength(0...2))) }
        return "\(inches(width)) × \(inches(height)) 英寸，\(Int(dpi.rounded())) DPI"
    }
    private var percent: String { "\(Int((shownZoom * 100).rounded()))%" }
    private func zoomBy(_ direction: Int) {
        if let next = JPEGPreview.step(from: shownZoom, in: direction) { zoom = next }
    }
    private var matte: Binding<PaletteColor> {
        Binding(get: { PaletteColor(red: options.red, green: options.green, blue: options.blue) },
                set: { options.red = $0.red; options.green = $0.green; options.blue = $0.blue })
    }
    private var gifMatte: Binding<PaletteColor> {
        Binding(get: { PaletteColor(red: gifOptions.red, green: gifOptions.green, blue: gifOptions.blue) },
                set: { gifOptions.red = $0.red; gifOptions.green = $0.green; gifOptions.blue = $0.blue })
    }
}

/// The export, fitted or zoomed (1 is 100%: one image pixel per screen pixel, as the canvas counts it), where it
/// can be dragged or scrolled around. Double-click switches between Fit and 100%.
struct JPEGPreview: View {
    static let frame = CGSize(width: 560, height: 330)
    static let steps: [Double] = [0.25, 0.5, 1, 2, 4, 8]
    let image: CGImage
    /// The exported image's size, which the preview may have been decoded smaller than.
    let pixelWidth: Int
    let pixelHeight: Int
    @Binding var zoom: Double?
    @Environment(\.displayScale) private var displayScale
    @State private var position = ScrollPosition()
    @State private var offset = CGPoint.zero
    @State private var dragStart: CGPoint?

    /// The zoom at which the whole image fits `frame`.
    static func fitZoom(width: Int, height: Int, in frame: CGSize, displayScale: CGFloat) -> Double {
        let points = CGSize(width: CGFloat(width) / max(1, displayScale), height: CGFloat(height) / max(1, displayScale))
        return Double(min(frame.width / points.width, frame.height / points.height))
    }
    /// The next zoom step past `zoom` in `direction` (1 in, −1 out), or nil at the end.
    static func step(from zoom: Double, in direction: Int) -> Double? {
        direction > 0 ? steps.first { $0 > zoom * 1.001 } : steps.last { $0 < zoom * 0.999 }
    }

    var body: some View {
        GeometryReader { geometry in
            if let zoom {
                let size = shownSize(zoom)
                ScrollView([.horizontal, .vertical]) {
                    // Nearest-neighbor from 100% up, so each pixel of the JPEG and its artifacts shows as it is.
                    Image(decorative: image, scale: 1).resizable().interpolation(zoom >= 1 ? .none : .high)
                        .frame(width: size.width, height: size.height)
                        .background { Self.checkerboard }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .scrollIndicators(.visible)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, new in offset = new }
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = dragStart ?? offset
                        dragStart = start
                        position.scrollTo(point: CGPoint(x: start.x - drag.translation.width, y: start.y - drag.translation.height))
                    }
                    .onEnded { _ in dragStart = nil })
                .onTapGesture(count: 2) { self.zoom = nil }
                .onAppear { keepCentered(from: nil, to: zoom, in: geometry.size) }
                .onChange(of: zoom) { old, new in keepCentered(from: old, to: new, in: geometry.size) }
                .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
            } else {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                    .background { Self.checkerboard }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { self.zoom = 1 }
            }
        }
    }

    /// The canvas's checkerboard behind the image, 10-point squares of two grays, so a transparent PNG shows where its
    /// edges are and what's see-through. A small tile repeated, however far the preview is zoomed.
    private static let checkerboard: some View = Image(nsImage: {
        let tile = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor(white: 0.30, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 20, height: 20).fill()
            NSColor(white: 0.35, alpha: 1).setFill()
            NSRect(x: 0, y: 10, width: 10, height: 10).fill()
            NSRect(x: 10, y: 0, width: 10, height: 10).fill()
            return true
        }
        return tile
    }()).resizable(resizingMode: .tile)

    /// The image's size on screen at `zoom`, in points.
    private func shownSize(_ zoom: Double) -> CGSize {
        CGSize(width: CGFloat(pixelWidth) / max(1, displayScale) * zoom, height: CGFloat(pixelHeight) / max(1, displayScale) * zoom)
    }

    /// Zooming keeps the middle of the view on the same part of the image; coming from Fit, it starts at the center.
    private func keepCentered(from old: Double?, to new: Double?, in view: CGSize) {
        guard let new else { return }
        let size = shownSize(new)
        var middle = CGPoint(x: size.width / 2, y: size.height / 2)
        if let old {
            let before = shownSize(old)
            let fx = before.width > 0 ? (offset.x + min(view.width, before.width) / 2) / before.width : 0.5
            let fy = before.height > 0 ? (offset.y + min(view.height, before.height) / 2) / before.height : 0.5
            middle = CGPoint(x: fx * size.width, y: fy * size.height)
        }
        position.scrollTo(point: CGPoint(x: min(max(0, middle.x - view.width / 2), max(0, size.width - view.width)),
                                         y: min(max(0, middle.y - view.height / 2), max(0, size.height - view.height))))
    }
}
