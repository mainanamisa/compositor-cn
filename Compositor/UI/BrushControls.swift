import SwiftUI

struct BrushControls: View {
    @Bindable var session: EditorSession
    var body: some View {
        HStack(spacing: 12) {
            Text(session.tool == .remove ? "移除" : session.tool == .spotHealing ? "污点修复" : session.tool == .cloneStamp ? "仿制图章" : session.tool == .blur ? "涂抹" : session.brushMode == .erase ? "橡皮擦" : "画笔").font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                if session.tool == .brush {
                    Picker("模式", selection: $session.brushMode) {
                        ForEach(BrushToolMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("用前景色绘制 (B)，或擦除像素 (E)")
                }
                if session.tool == .blur {
                    Picker("模式", selection: $session.blurMode) {
                        ForEach(BlurToolMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("液化推移像素 · 模糊柔化 · 涂抹沿方向拖动颜色")
                }
                if session.tool == .spotHealing {
                    Picker("类型", selection: $session.spotHealingMode) {
                        ForEach(SpotHealingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityIdentifier("spotHealingType")
                }
                if session.tool == .cloneStamp {
                    Toggle("对齐", isOn: $session.cloneSettings.aligned)
                        .help("让取样源在笔画之间随画笔移动；关闭时每一笔都从取样点开始")
                    Picker("取样", selection: $session.cloneSettings.sampleAllLayers) {
                        Text("当前图层").tag(false)
                        Text("所有图层").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("仅从当前图层取样，或从所有可见图层的显示效果取样")
                }
                Text("大小").scrubbable(sensitivity: 1.0, value: $session.brushSettings.diameter, range: 1...2000)
                TextField("大小", value: Binding<Double>(get: { Double(session.brushSettings.diameter) },
                    set: { session.brushSettings.diameter = $0.isFinite ? CGFloat(min(2000, max(1, $0))) : 40 }),
                    format: .number.precision(.fractionLength(0)))
                    .frame(width: 48).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.diameter) },
                                change: { session.brushSettings.diameter = CGFloat(min(2000, max(1, $0))) })
                    .onChange(of: session.brushSettings.diameter) { _, value in
                        session.brushSettings.diameter = value.isFinite ? min(2000, max(1, value)) : 40
                    }
                    .unitSuffix("px")
                // Remove paints only a mask for the model: size is all it takes.
                if session.tool != .remove {
                Text("硬度").scrubbable(sensitivity: 0.01, value: $session.brushSettings.hardness, range: 0...1)
                Slider(value: $session.brushSettings.hardness, in: 0...1).frame(width: 100)
                TextField("硬度", value: Binding<Double>(get: { Double(session.brushSettings.hardness * 100) },
                    set: { session.brushSettings.hardness = $0.isFinite ? CGFloat(min(1, max(0, $0 / 100))) : 1 }),
                    format: .number.precision(.fractionLength(0)))
                    .frame(width: 42).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.hardness * 100) },
                                change: { session.brushSettings.hardness = CGFloat(min(1, max(0, $0 / 100))) })
                    .unitSuffix("%")
                Text(session.tool == .blur ? "强度" : "不透明度")
                    .scrubbable(sensitivity: 0.01, value: $session.brushSettings.opacity, range: 0.01...1)
                Slider(value: $session.brushSettings.opacity, in: 0.01...1).frame(width: 100)
                TextField("不透明度", value: Binding<Double>(get: { Double(session.brushSettings.opacity * 100) },
                    set: { session.brushSettings.opacity = $0.isFinite ? CGFloat(min(100, max(1, $0)) / 100) : 1 }),
                    format: .number.precision(.fractionLength(0)))
                    .frame(width: 42).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.opacity * 100) },
                                change: { session.brushSettings.opacity = CGFloat(min(100, max(1, $0)) / 100) })
                    .help("按 1–9 设置 10–90%，按 0 设置 100%")
                    .unitSuffix("%")
                }
                // Blur softens by a radius of its own, apart from how strongly it lays the softening down.
                if session.tool == .blur, session.blurMode == .blur {
                    Text("半径").scrubbable(sensitivity: 0.1, value: $session.brushSettings.blurRadius, range: 0.5...50)
                    // The slider covers everyday radii; typing or scrubbing reaches up to 50.
                    Slider(value: Binding(get: { min(20, session.brushSettings.blurRadius) },
                                          set: { session.brushSettings.blurRadius = $0 }), in: 0.5...20).frame(width: 100)
                    TextField("半径", value: Binding<Double>(get: { Double(session.brushSettings.blurRadius) },
                        set: { session.brushSettings.blurRadius = $0.isFinite ? CGFloat(min(50, max(0.5, $0))) : 5 }),
                        format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 42).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.brushSettings.blurRadius) },
                                    change: { session.brushSettings.blurRadius = CGFloat(min(50, max(0.5, $0))) })
                        .help("模糊柔化的范围，以像素为单位")
                        .unitSuffix("px")
                }
                // Paint and Erase only: healing, cloning and smearing have their own feel.
                if session.tool == .brush {
                    Text("平滑")
                        .scrubbable(sensitivity: 1, value: $session.brushSettings.smoothing, range: 0...100)
                    Slider(value: $session.brushSettings.smoothing, in: 0...100).frame(width: 100)
                    TextField("平滑", value: Binding<Double>(get: { Double(session.brushSettings.smoothing) },
                        set: { session.brushSettings.smoothing = $0.isFinite ? CGFloat(min(100, max(0, $0))) : 0 }),
                        format: .number.precision(.fractionLength(0)))
                        .frame(width: 42).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.brushSettings.smoothing) },
                                    change: { session.brushSettings.smoothing = CGFloat(min(100, max(0, $0))) })
                        .help("画笔像被这样长的绳子牵着跟随指针，手抖也能画出平滑的线条")
                }
                if session.isMaskSelected {
                    Picker("绘制", selection: $session.maskPaintWhite) {
                        Text("黑色 · 隐藏").tag(false)
                        Text("白色 · 显示").tag(true)
                    }.frame(width: 180)
                } else if session.tool != .cloneStamp, session.tool != .blur, session.tool != .remove {
                    // Same foreground color and Color Picker as the tool-rail swatch.
                    HStack(spacing: 6) {
                        Text("颜色")
                        Button { session.openColorPicker(background: false) } label: {
                            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                            shape.fill(session.foregroundColor.swiftUI)
                                .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1) }
                                .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                                .frame(width: 34, height: 18)
                                .contentShape(shape)
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.canEditPalette)
                        .help("前景色")
                        .accessibilityLabel("前景色")
                    }
                }
                Spacer(minLength: 0)
                if session.tool == .cloneStamp, session.cloneSource == nil {
                    Text("按住 Option 点按以设置取样源").foregroundStyle(.secondary)
                }
                if session.isMaskSelected { Text("蒙版").foregroundStyle(.secondary) }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy)
    }
}

/// A rubber stamp for the tool rail (SF Symbols has none): round handle, neck, body, and pad.
struct CloneStampToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var stamp = Path()
            stamp.addEllipse(in: CGRect(x: w * 0.33, y: h * 0.02, width: w * 0.34, height: h * 0.30))
            stamp.addRect(CGRect(x: w * 0.43, y: h * 0.28, width: w * 0.14, height: h * 0.28))
            stamp.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.54, width: w * 0.76, height: h * 0.22),
                                 cornerSize: CGSize(width: w * 0.08, height: w * 0.08))
            stamp.addRect(CGRect(x: w * 0.06, y: h * 0.82, width: w * 0.88, height: h * 0.12))
            context.fill(stamp, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
