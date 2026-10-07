import SwiftUI

/// Photoshop-style Export As: the format picker on top, with the quality slider and the matte color shown only
/// where the chosen format supports them. Changing anything re-encodes the debounced live preview, as in the
/// JPEG sheet.
struct ExportSheet: View {
    let raster: ExportRaster
    let session: EditorSession
    let finish: ((Data, ExportFormat)?) -> Void
    @State private var options: ExportOptions
    /// The quality of the last export, which the next one starts from; shared with the JPEG sheet.
    private static let qualityKey = "jpegExportQuality"
    /// The format of the last Export As, which the next one starts from.
    private static let formatKey = "exportAsFormat"

    init(raster: ExportRaster, session: EditorSession, finish: @escaping ((Data, ExportFormat)?) -> Void) {
        self.raster = raster
        self.session = session
        self.finish = finish
        var start = ExportOptions()
        if let saved = UserDefaults.standard.object(forKey: Self.qualityKey) as? Double, saved.isFinite {
            start.quality = min(1, max(0, saved))
        }
        if let saved = UserDefaults.standard.string(forKey: Self.formatKey),
           let format = ExportFormat(rawValue: saved), ExportFormat.available.contains(format) {
            start.format = format
        }
        _options = State(initialValue: start)
    }
    @State private var result: ExportResult?
    /// The preview's zoom, 1 being 100%; nil fits the whole image.
    @State private var zoom: Double?
    @Environment(\.displayScale) private var displayScale
    /// The zoom shown now, Fit's included.
    private var shownZoom: Double {
        zoom ?? JPEGPreview.fitZoom(width: raster.image.width, height: raster.image.height,
                                    in: JPEGPreview.frame, displayScale: displayScale)
    }
    @State private var readyOptions: ExportOptions?
    @State private var error: String?

    var body: some View { sheet.roundedControls() }
    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("导出为").font(.title2.bold())
                Picker("格式", selection: $options.format) {
                    ForEach(ExportFormat.available, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Button("适合") { zoom = nil }.disabled(zoom == nil)
                    .help("显示完整图像（⌘0）")
                Button { zoomBy(1) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(JPEGPreview.step(from: shownZoom, in: 1) == nil)
                    .help("放大（⌘+），当前 \(percent)。100% 时图像的每个像素对应屏幕的一个像素，与画布一致")
                Button { zoomBy(-1) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(JPEGPreview.step(from: shownZoom, in: -1) == nil)
                    .help("缩小（⌘−），当前 \(percent)")
            }
            // Closer to the title row than the rest of the dialog's spacing.
            .padding(.bottom, -8)
            ZStack {
                Color(white: 0.12)
                if let result {
                    JPEGPreview(image: result.preview, pixelWidth: raster.image.width, pixelHeight: raster.image.height, zoom: $zoom)
                }
                if readyOptions != options && error == nil {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }.frame(width: JPEGPreview.frame.width, height: JPEGPreview.frame.height).clipped()
                .help("拖动或滚动以移动视图；双击在“适合”和 100% 之间切换")
            if options.format.supportsQuality {
                HStack {
                    Text("质量")
                    Slider(value: $options.quality, in: 0...1, step: 0.01)
                    Text("\(Int((options.quality * 100).rounded()))%")
                        .monospacedDigit().frame(width: 45, alignment: .trailing)
                }
            }
            if !options.format.supportsAlpha {
                HStack(spacing: 8) {
                    Text("透明区域背景色")
                    DialogColorSwatch(title: "\(options.format.title) 背景色", color: matte, session: session)
                        .help("用于填充透明区域的颜色")
                }
            }
            HStack(spacing: 12) {
                Text("\(raster.image.width.formatted()) × \(raster.image.height.formatted()) 像素 · sRGB")
                    .foregroundStyle(.secondary)
                Spacer()
                if let error { Text(error).foregroundStyle(.red) }
                else if readyOptions == options, let result {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(result.data.count), countStyle: .file)).monospacedDigit()
                } else { Text("正在更新…").foregroundStyle(.secondary) }
                Button("取消") { DialogColorSwatch.closePicker(session); finish(nil) }.configuredNativeShortcut(.escape)
                Button("导出…") {
                    DialogColorSwatch.closePicker(session)
                    UserDefaults.standard.set(options.quality, forKey: Self.qualityKey)
                    UserDefaults.standard.set(options.format.rawValue, forKey: Self.formatKey)
                    if let result { finish((result.data, options.format)) }
                    else { finish(nil) }
                }
                    .configuredNativeShortcut(.return)
                    .disabled(result == nil || readyOptions != options || error != nil)
            }
        }
        .padding(24)
        .onAppear { session.previewZoom = { command in
            switch command {
            case .zoomIn: zoomBy(1)
            case .zoomOut: zoomBy(-1)
            case .fit: zoom = nil
            case .actual: zoom = 1
            }
        } }
        .onDisappear { session.previewZoom = nil }
        .task(id: options) {
            let requested = options
            error = nil
            do {
                try await Task.sleep(for: .milliseconds(200))
                let encoded = try await ImageExporter.shared.encode(raster, options: requested)
                try Task.checkCancellation()
                result = encoded
                readyOptions = requested
            } catch is CancellationError {
                // A newer setting superseded this preview.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private var percent: String { "\(Int((shownZoom * 100).rounded()))%" }
    private func zoomBy(_ direction: Int) {
        if let next = JPEGPreview.step(from: shownZoom, in: direction) { zoom = next }
    }
    private var matte: Binding<PaletteColor> {
        Binding(get: { PaletteColor(red: options.red, green: options.green, blue: options.blue) },
                set: { options.red = $0.red; options.green = $0.green; options.blue = $0.blue })
    }
}
