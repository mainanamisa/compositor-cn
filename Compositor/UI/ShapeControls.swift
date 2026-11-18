import SwiftUI

struct ShapeControls: View {
    @Bindable var session: EditorSession

    /// A selected rectangle or ellipse takes the fill, stroke and radius, unless Line is chosen: that bar is the
    /// line being drawn, then the line just created.
    private var editsSelection: Bool { session.editingShapeLayer != nil && session.shapeKind != .line }
    private var editsLine: Bool { session.editingLineLayer != nil && (session.shapeKind == .line || session.editingShapeLayer == nil) }
    private var showsLine: Bool { session.shapeKind == .line || editsLine }
    private var showsStroke: Bool { !showsLine && (editsSelection || session.shapeKind != .line) }
    private var showsRadius: Bool {
        if showsLine { return false }
        if let kind = session.editingShapeLayer?.liveShape?.style.kind { return kind == .rectangle }
        return session.shapeKind == .rectangle
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("形状").font(ToolHeaderStyle.titleFont)
            Picker("形状", selection: Binding(get: { session.shapeKind }, set: { kind in
                session.cancelShape()
                session.shapeKind = kind
            })) {
                ForEach(ShapeKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("按 Shift-U（或 Tab）在矩形、椭圆和直线之间切换")
            HStack(spacing: 6) {
                Text(showsStroke ? "填充" : "颜色")
                Button { session.openShapeFillPicker() } label: {
                    ColorSwatch(color: Color(nsColor: session.displayedShapeFill.nsColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("填充颜色")
                .help(editsLine ? "所选直线的颜色"
                      : session.shapeKind == .line ? "下一条直线的颜色"
                      : editsSelection ? "所选形状的填充颜色"
                      : "形状以前景色填充；点按可更改")
            }
            if showsStroke {
                HStack(spacing: 6) {
                    Text("描边")
                    Button { session.openShapeStrokePicker() } label: {
                        ColorSwatch(color: Color(nsColor: session.displayedShapeStroke.nsColor))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("描边颜色")
                    Text("宽度").scrubbable(sensitivity: 1, value: strokeWidth, range: 0...5000,
                                             onStart: session.beginShapeStyleEdit, onEnd: session.finishShapeStyleEdit)
                    // The slider covers everyday widths; typing or scrubbing reaches up to 5000.
                    AppSlider(value: Binding(get: { min(50, strokeWidth.wrappedValue) },
                                          set: { strokeWidth.wrappedValue = $0.rounded() }), in: 0...50,
                              onEditingChanged: { if $0 { session.beginShapeStyleEdit() } else { session.finishShapeStyleEdit() } })
                        .frame(width: 100)
                    TextField("宽度", value: strokeWidth, format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { session.displayedStrokeWidth },
                                    change: { session.setDisplayedStrokeWidth($0) })
                }
                .help("描边绘制在形状内侧，单位为像素；0 表示不描边")
            }
            if showsLine {
                HStack(spacing: 6) {
                    Text("宽度").scrubbable(sensitivity: 1, value: lineWidth, range: 1...5000,
                                             onStart: session.beginShapeStyleEdit, onEnd: session.finishShapeStyleEdit)
                    // The slider covers everyday widths; typing or scrubbing reaches up to 5000.
                    AppSlider(value: Binding(get: { min(50, lineWidth.wrappedValue) },
                                          set: { lineWidth.wrappedValue = $0.rounded() }), in: 1...50,
                              onEditingChanged: { if $0 { session.beginShapeStyleEdit() } else { session.finishShapeStyleEdit() } })
                        .frame(width: 100)
                    TextField("宽度", value: lineWidth, format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { session.displayedLineWidth },
                                    change: { session.setDisplayedLineWidth($0) })
                }
                HStack(spacing: 6) {
                    Text("样式")
                    Picker("样式", selection: Binding(get: { session.displayedLineStyle },
                                                      set: { session.setDisplayedLineStyle($0) })) {
                        ForEach(ShapeLineStyle.allCases, id: \.self) { style in
                            Image(nsImage: LineSample.style(style)).accessibilityLabel(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
                .help(editsLine ? "所选直线的虚线样式；随线宽变长"
                      : "实线、虚线或点线；虚线随线宽变长")
                HStack(spacing: 6) {
                    Text("端点")
                    Picker("端点", selection: Binding(get: { session.displayedLineCap },
                                                    set: { session.setDisplayedLineCap($0) })) {
                        ForEach(ShapeLineCap.allCases, id: \.self) { cap in
                            Label { Text(cap.displayName) } icon: { Image(nsImage: LineSample.cap(cap)) }.tag(cap)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
                .help(editsLine ? "所选直线端点的外观"
                      : "线条端点以及每段虚线和点的外观")
            }
            if showsRadius {
                HStack(spacing: 6) {
                    Text("圆角").scrubbable(sensitivity: 1, value: cornerRadius, range: 0...5000,
                                              onStart: session.beginShapeStyleEdit, onEnd: session.finishShapeStyleEdit)
                    AppSlider(value: Binding(get: { min(200, cornerRadius.wrappedValue) },
                                          set: { cornerRadius.wrappedValue = $0.rounded() }), in: 0...200,
                              onEditingChanged: { if $0 { session.beginShapeStyleEdit() } else { session.finishShapeStyleEdit() } })
                        .frame(width: 100)
                    TextField("圆角", value: cornerRadius, format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { session.displayedCornerRadius },
                                    change: { session.setDisplayedCornerRadius($0) })
                }
                .help("将矩形的角按此像素数倒圆；0 保持直角")
                Toggle("平滑圆角", isOn: Binding(get: { session.displayedShapeSmoothing },
                                                      set: { session.setDisplayedShapeSmoothing($0) }))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .disabled(session.displayedCornerRadius <= 0)
                    .help(session.displayedCornerRadius <= 0
                          ? "圆角半径大于 0 时才能使用平滑圆角。"
                          : "使用 60% 平滑度的连续曲率圆角（squircle），与 Figma 的 iOS 设置一致")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
        .onChange(of: session.colorPicker?.color) { _, _ in session.previewShapeColor() }
    }

    private var strokeWidth: Binding<Double> {
        Binding(get: { session.displayedStrokeWidth }, set: { session.setDisplayedStrokeWidth($0) })
    }
    private var cornerRadius: Binding<Double> {
        Binding(get: { session.displayedCornerRadius }, set: { session.setDisplayedCornerRadius($0) })
    }
    private var lineWidth: Binding<Double> {
        Binding(get: { session.displayedLineWidth }, set: { session.setDisplayedLineWidth($0) })
    }
}

/// Small drawings for the Line shape's menus. Template images, so a menu tints them with its text and highlight.
@MainActor private enum LineSample {
    private static var images: [String: NSImage] = [:]

    /// A stretch of line in `style`, as it looks drawn.
    static func style(_ style: ShapeLineStyle) -> NSImage {
        image("style." + style.rawValue, size: NSSize(width: 84, height: 10)) { context in
            context.strokeShapeLine(from: CGPoint(x: 2, y: 5), to: CGPoint(x: 82, y: 5), width: 2, style: style, cap: .round)
        }
    }

    /// The end of a thick line in outline, with its center line running into the cap.
    static func cap(_ cap: ShapeLineCap) -> NSImage {
        image("cap." + cap.rawValue, size: NSSize(width: 18, height: 14)) { context in
            let center = CGMutablePath()
            center.move(to: CGPoint(x: 0, y: 7))
            center.addLine(to: CGPoint(x: 10, y: 7))
            context.addPath(center.copy(strokingWithWidth: 11, lineCap: cap.cgLineCap, lineJoin: .miter, miterLimit: 10))
            context.setLineWidth(1.5)
            context.strokePath()
            context.addPath(center)
            context.setLineWidth(1.5)
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 8, y: 5, width: 4, height: 4))
        }
    }

    private static func image(_ key: String, size: NSSize, draw: @escaping (CGContext) -> Void) -> NSImage {
        if let image = images[key] { return image }
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(.black)
            context.setFillColor(.black)
            draw(context)
            return true
        }
        image.isTemplate = true
        images[key] = image
        return image
    }
}

private extension ShapeLineStyle {
    var displayName: String {
        switch self {
        case .solid: return "实线"
        case .dotted: return "点线"
        case .dashed: return "虚线"
        case .longDash: return "长虚线"
        }
    }
}

private extension ShapeLineCap {
    var displayName: String {
        switch self {
        case .square: return "方头"
        case .round: return "圆头"
        }
    }
}
