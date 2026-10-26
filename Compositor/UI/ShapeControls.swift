import SwiftUI

struct ShapeControls: View {
    @Bindable var session: EditorSession

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
            Button { session.openColorPicker(background: false) } label: {
                let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
                swatch.fill(Color(nsColor: session.foregroundColor.nsColor))
                    .overlay { swatch.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                    .frame(width: 36, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("填充颜色")
            .help("形状以前景色填充；点按可更改")
            if session.shapeKind == .line {
                HStack(spacing: 6) {
                    Text("宽度").scrubbable(sensitivity: 1, value: $session.shapeLineWidth, range: 1...5000)
                    // The slider covers everyday widths; typing or scrubbing reaches up to 5000.
                    Slider(value: Binding(get: { min(50, session.shapeLineWidth) },
                                          set: { session.shapeLineWidth = $0.rounded() }), in: 1...50)
                        .frame(width: 100)
                    TextField("宽度", value: Binding(get: { session.shapeLineWidth },
                                                      set: { session.shapeLineWidth = $0.isFinite ? min(5000, max(1, $0)) : 4 }),
                              format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { session.shapeLineWidth },
                                    change: { session.shapeLineWidth = min(5000, max(1, $0)) })
                        .unitSuffix("px")
                }
                HStack(spacing: 6) {
                    Text("样式")
                    Picker("样式", selection: $session.shapeLineStyle) {
                        ForEach(ShapeLineStyle.allCases, id: \.self) { style in
                            Image(nsImage: LineSample.style(style)).accessibilityLabel(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
                .help("实线、虚线或点线；虚线随线宽变长")
                HStack(spacing: 6) {
                    Text("端点")
                    Picker("端点", selection: $session.shapeLineCap) {
                        ForEach(ShapeLineCap.allCases, id: \.self) { cap in
                            Label { Text(cap.displayName) } icon: { Image(nsImage: LineSample.cap(cap)) }.tag(cap)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
                .help("线条端点以及每段虚线和点的外观")
            }
            if session.shapeKind == .rectangle {
                HStack(spacing: 6) {
                    Text("圆角").scrubbable(sensitivity: 1, value: $session.shapeCornerRadius, range: 0...5000)
                    Slider(value: Binding(get: { min(200, session.shapeCornerRadius) },
                                          set: { session.shapeCornerRadius = $0.rounded() }), in: 0...200)
                        .frame(width: 100)
                    TextField("圆角", value: Binding(get: { session.shapeCornerRadius },
                                                       set: { session.shapeCornerRadius = $0.isFinite ? min(5000, max(0, $0)) : 0 }),
                              format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.shapeCornerRadius) },
                                    change: { session.shapeCornerRadius = min(5000, max(0, CGFloat($0))) })
                        .unitSuffix("px")
                }
                .help("将矩形的角按此像素数倒圆；0 保持直角")
                Toggle("平滑圆角", isOn: $session.shapeSmoothing)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .disabled(session.shapeCornerRadius <= 0)
                    .help(session.shapeCornerRadius <= 0
                          ? "圆角半径大于 0 时才能使用平滑圆角。"
                          : "使用 60% 平滑度的连续曲率圆角（squircle），与 Figma 的 iOS 设置一致")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
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
