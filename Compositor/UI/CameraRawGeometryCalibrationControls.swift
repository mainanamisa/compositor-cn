import AppKit
import SwiftUI

struct CameraRawGeometryControls: View {
    @Bindable var session: EditorSession
    private var settings: FilterSettings { session.filterEdit?.settings ?? FilterSettings() }
    private var raw: CameraRawSettings { settings.cameraRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upright 校正").font(.subheadline)
            Picker("Upright", selection: uprightBinding) {
                ForEach(CameraRawUprightMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .help("关闭时保持图片原样。引导模式按你在图片上绘制的线条校正。")
            if raw.geometry.upright == .guided {
                Button {
                    session.filterEdit?.drawingCameraRawGeometryGuide.toggle()
                    session.brushRevision += 1
                } label: {
                    Label("绘制引导线", systemImage: "line.diagonal")
                }
                .help("在预览上绘制两条或更多应为水平或垂直的线条。")
                .tint(session.filterEdit?.drawingCameraRawGeometryGuide == true ? Color.accentColor : Color.secondary)
                if session.filterEdit?.drawingCameraRawGeometryGuide == true {
                    Text("在图层上拖移以放置引导线。至少绘制两条线。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !raw.geometry.guides.isEmpty {
                    Button("清除引导线") {
                        update { $0.cameraRaw.geometry.guides = [] }
                    }
                    .help("移除所有引导线。")
                }
            }
            Picker("投影", selection: binding(\.projection)) {
                ForEach(CameraRawProjection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .help("透视允许更强的梯形校正。直线保持较温和的变形。")
            geometrySlider("垂直", \.vertical, help: "将垂直线向中心校正。")
            geometrySlider("水平", \.horizontal, help: "将水平线向中心校正。")
            geometrySlider("旋转", \.rotate, range: CameraRawGeometrySettings.rotateRange, help: "围绕中心旋转图片。")
            geometrySlider("长宽比", \.aspect, help: "相对于高度拉伸宽度。")
            geometrySlider("缩放", \.scale, help: "在画面内缩放变换后的图片。")
            geometrySlider("X 偏移", \.offsetX, help: "左右移动图片。")
            geometrySlider("Y 偏移", \.offsetY, help: "上下移动图片。")
            Toggle("限制裁剪", isOn: binding(\.constrainCrop))
                .help("变换后裁掉空白的边缘，并将结果适配回画面。")
        }
    }

    private var uprightBinding: Binding<CameraRawUprightMode> {
        Binding(get: { raw.geometry.upright }, set: { mode in
            update { $0.cameraRaw.geometry.upright = mode }
            if mode != .guided { session.filterEdit?.drawingCameraRawGeometryGuide = false }
        })
    }

    private func binding<T>(_ key: WritableKeyPath<CameraRawGeometrySettings, T>) -> Binding<T> {
        Binding(get: { raw.geometry[keyPath: key] }, set: { value in update { $0.cameraRaw.geometry[keyPath: key] = value } })
    }

    private func geometrySlider(_ title: String, _ key: WritableKeyPath<CameraRawGeometrySettings, Double>,
                                range: ClosedRange<Double> = CameraRawGeometrySettings.toneRange, help: String) -> some View {
        let value = raw.geometry[keyPath: key]
        return HStack(spacing: 10) {
            Text(title).frame(minWidth: CameraRawControls.labelWidth, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1,
                            value: Binding(get: { raw.geometry[keyPath: key] },
                                           set: { newValue in update { $0.cameraRaw.geometry[keyPath: key] = newValue } }), range: range)
            CameraRawSlider(value: value, range: range, track: .plain, help: help,
                            onChange: { rawValue in update { $0.cameraRaw.geometry[keyPath: key] = rawValue.rounded() } },
                            onReset: { update { $0.cameraRaw.geometry[keyPath: key] = 0 } })
            TextField(title, value: Binding(get: { raw.geometry[keyPath: key] },
                                            set: { newValue in update { $0.cameraRaw.geometry[keyPath: key] = newValue } }),
                      format: .number.precision(.fractionLength(0)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).help(help)
        }
    }

    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: session.filterEdit?.preview ?? true)
    }
}

struct CameraRawCalibrationControls: View {
    @Bindable var session: EditorSession
    private var settings: FilterSettings { session.filterEdit?.settings ?? FilterSettings() }
    private var raw: CameraRawSettings { settings.cameraRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("处理版本", selection: binding(\.process)) {
                ForEach(CameraRawProcessVersion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .help("选择下方校准滑块的应用强度。版本 6 是当前的默认值。")
            Text(raw.calibration.process.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(raw.calibration.process.summary)
            Text("阴影").font(.subheadline)
            calibrationSlider("色调", \.shadowTint, help: "向最暗的色调添加绿色或品红。")
            Text("红原色").font(.subheadline)
            calibrationSlider("色相", \.redHue, help: "改变红色的解析方式。")
            calibrationSlider("饱和度", \.redSaturation, help: "增强或减弱红原色。")
            Text("绿原色").font(.subheadline)
            calibrationSlider("色相", \.greenHue, help: "改变绿色的解析方式。")
            calibrationSlider("饱和度", \.greenSaturation, help: "增强或减弱绿原色。")
            Text("蓝原色").font(.subheadline)
            calibrationSlider("色相", \.blueHue, help: "改变蓝色的解析方式。")
            calibrationSlider("饱和度", \.blueSaturation, help: "增强或减弱蓝原色。")
        }
    }

    private func binding<T>(_ key: WritableKeyPath<CameraRawCalibrationSettings, T>) -> Binding<T> {
        Binding(get: { raw.calibration[keyPath: key] }, set: { value in update { $0.cameraRaw.calibration[keyPath: key] = value } })
    }

    private func calibrationSlider(_ title: String, _ key: WritableKeyPath<CameraRawCalibrationSettings, Double>, help: String) -> some View {
        let value = raw.calibration[keyPath: key]
        return HStack(spacing: 10) {
            Text(title).frame(minWidth: CameraRawControls.labelWidth, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1,
                            value: Binding(get: { raw.calibration[keyPath: key] },
                                           set: { newValue in update { $0.cameraRaw.calibration[keyPath: key] = newValue } }),
                            range: CameraRawCalibrationSettings.toneRange)
            CameraRawSlider(value: value, range: CameraRawCalibrationSettings.toneRange, track: .plain, help: help,
                            onChange: { rawValue in update { $0.cameraRaw.calibration[keyPath: key] = rawValue.rounded() } },
                            onReset: { update { $0.cameraRaw.calibration[keyPath: key] = 0 } })
            TextField(title, value: Binding(get: { raw.calibration[keyPath: key] },
                                            set: { newValue in update { $0.cameraRaw.calibration[keyPath: key] = newValue } }),
                      format: .number.precision(.fractionLength(0)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).help(help)
        }
    }

    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: session.filterEdit?.preview ?? true)
    }
}
