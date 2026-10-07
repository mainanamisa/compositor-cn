import SwiftUI

struct ImageSizeSheet: View {
    let document: CanvasDocument
    let finish: (ImageSizeOptions?) -> Void
    @State private var width: Double
    @State private var height: Double
    @State private var resolution: Double
    /// The last usable resolution. Print sizes scale from it, so passing through a zero or negative entry
    /// doesn't lose them.
    @State private var lastResolution: Double
    @State private var locked = true
    @State private var resample = true
    @State private var unit: CanvasUnit = .pixels
    @State private var sampling: LayerSampling = .high

    init(document: CanvasDocument, finish: @escaping (ImageSizeOptions?) -> Void) {
        self.document = document
        self.finish = finish
        _width = State(initialValue: Double(document.width))
        _height = State(initialValue: Double(document.height))
        _resolution = State(initialValue: document.resolution)
        _lastResolution = State(initialValue: document.resolution)
    }

    private var valid: Bool {
        width.isFinite && height.isFinite && resolution.isFinite && (1...9600).contains(resolution)
            && (1...DocumentLimits.maxSideExtent).contains(width.rounded()) && (1...DocumentLimits.maxSideExtent).contains(height.rounded())
            && (!resample || width.rounded() * height.rounded() <= DocumentLimits.maxSurfaceExtent)
    }
    private func display(_ pixels: Double, original: Int) -> Double {
        switch unit {
        case .percent: return pixels / Double(original) * 100
        case .inches: return pixels / resolution
        case .centimeters: return pixels / resolution * 2.54
        case .pixels: return pixels
        }
    }
    private func dimension(isWidth: Bool) -> Binding<Double> {
        Binding(get: { display(isWidth ? width : height, original: isWidth ? document.width : document.height) }, set: { value in
            guard value.isFinite, value > 0 else { return }
            if unit == .inches || unit == .centimeters, !(resolution.isFinite && resolution > 0) { return }
            if !resample {
                resolution = (isWidth ? width : height) / value * (unit == .centimeters ? 2.54 : 1)
                return
            }
            let pixels: Double
            switch unit {
            case .percent: pixels = value / 100 * Double(isWidth ? document.width : document.height)
            case .inches: pixels = value * resolution
            case .centimeters: pixels = value / 2.54 * resolution
            case .pixels: pixels = value
            }
            if isWidth {
                if locked { height = pixels * height / width }
                width = pixels
            } else {
                if locked { width = pixels * width / height }
                height = pixels
            }
        })
    }

    private var canScrubDimensions: Bool {
        (unit != .inches && unit != .centimeters) || (resolution.isFinite && resolution > 0)
    }

    private func scrubRange(isWidth: Bool) -> ClosedRange<Double> {
        guard canScrubDimensions else { return 0...0 }
        let pixels = isWidth ? width : height
        let other = isWidth ? height : width
        let original = Double(isWidth ? document.width : document.height)
        if !resample {
            let multiplier = unit == .centimeters ? 2.54 : 1.0
            return pixels * multiplier / 9600...pixels * multiplier
        }
        let minimum = locked ? max(1, pixels / other) : 1.0
        let dimensionLimit = locked ? min(30_000, 30_000 * pixels / other) : 30_000.0
        let areaLimit = locked ? sqrt(100_000_000 * pixels / other) : 100_000_000 / other
        let maximum = max(minimum, min(dimensionLimit, areaLimit))
        func displayed(_ count: Double) -> Double {
            switch unit {
            case .percent: return count / original * 100
            case .inches: return count / resolution
            case .centimeters: return count / resolution * 2.54
            case .pixels: return count
            }
        }
        return displayed(minimum)...displayed(maximum)
    }

    private func scrubSensitivity(isWidth: Bool) -> Double {
        guard canScrubDimensions else { return 0 }
        if !resample { return unit == .centimeters ? 0.0254 : 0.01 }
        switch unit {
        case .percent: return 100 / Double(isWidth ? document.width : document.height)
        case .inches: return 1 / resolution
        case .centimeters: return 2.54 / resolution
        case .pixels: return 1
        }
    }

    var body: some View { sheet.roundedControls() }
    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("图像大小").font(.title2.bold())
            Text("当前：\(document.width) × \(document.height) 像素").foregroundStyle(.secondary)
            Picker("单位", selection: $unit) {
                ForEach(CanvasUnit.allCases.filter { resample || ($0 != .pixels && $0 != .percent) }, id: \.self) { Text($0.rawValue) }
            }
            HStack {
                Text("宽度").frame(width: 75, alignment: .leading)
                    .scrubbable(sensitivity: scrubSensitivity(isWidth: true),
                                value: dimension(isWidth: true), range: scrubRange(isWidth: true), step: 1)
                    .disabled(!canScrubDimensions)
                TextField("宽度", value: dimension(isWidth: true), format: .number.precision(.fractionLength(0...3)))
            }
            HStack {
                Text("高度").frame(width: 75, alignment: .leading)
                    .scrubbable(sensitivity: scrubSensitivity(isWidth: false),
                                value: dimension(isWidth: false), range: scrubRange(isWidth: false), step: 1)
                    .disabled(!canScrubDimensions)
                TextField("高度", value: dimension(isWidth: false), format: .number.precision(.fractionLength(0...3)))
            }
            Toggle("锁定长宽比", isOn: $locked).disabled(!resample)
            HStack {
                Text("分辨率").scrubbable(sensitivity: 1, value: $resolution, range: 1...9600, step: 1)
                TextField("分辨率", value: $resolution, format: .number.precision(.fractionLength(0...3)))
                    .onChange(of: resolution) { _, new in
                        guard new.isFinite, new > 0 else { return }
                        if resample, unit == .inches || unit == .centimeters {
                            width *= new / lastResolution
                            height *= new / lastResolution
                        }
                        lastResolution = new
                    }
                Text("像素/英寸").foregroundStyle(.secondary)
            }
            Toggle("重新采样", isOn: $resample).onChange(of: resample) { _, enabled in
                if !enabled {
                    width = Double(document.width)
                    height = Double(document.height)
                    locked = true
                    if unit == .pixels || unit == .percent { unit = .inches }
                }
            }
            if resample {
                Picker("采样", selection: $sampling) {
                    ForEach(LayerSampling.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("将调整图层像素大小并应用已有的变换。撤销可恢复原始状态。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("仅更改打印尺寸和分辨率，像素保持不变。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(valid ? "结果：\(Int(width.rounded())) × \(Int(height.rounded())) 像素" : "每边须为 1–\(DocumentLimits.maxSide.formatted()) 像素，最大 \(DocumentLimits.maxSurfaceMegapixels) 百万像素，分辨率 1–9,600 像素/英寸。")
                .foregroundStyle(valid ? Color.secondary : Color.orange).font(.callout)
            HStack {
                Button("取消") { finish(nil) }.configuredNativeShortcut(.escape)
                Spacer()
                Button("调整大小") {
                    guard valid else { return }
                    finish(ImageSizeOptions(width: Int(width.rounded()), height: Int(height.rounded()),
                        resolution: resolution, sampling: sampling))
                }.configuredNativeShortcut(.return).disabled(!valid)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 430)
    }
}

/// LayerSampling is Codable with English raw values; the picker shows these instead.
private extension LayerSampling {
    var displayName: String {
        switch self {
        case .nearest: "邻近"
        case .smooth: "平滑"
        case .high: "高质量"
        }
    }
}
