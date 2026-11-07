import SwiftUI

struct LassoControls: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 12) {
            Text(session.tool == .marquee ? "选框" : session.tool == .wand ? "魔棒" : "套索").font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                if session.tool == .marquee {
                    Picker("形状", selection: Binding(get: { session.marqueeKind }, set: { kind in
                        session.cancelLasso()
                        session.marqueeKind = kind
                    })) {
                        ForEach(LassoKind.marqueeChoices, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("按 M 在矩形和椭圆之间切换")
                }
                if session.tool == .wand {
                    Picker("模式", selection: Binding(get: { session.wandMode }, set: { mode in
                        session.cancelLasso()
                        session.wandMode = mode
                    })) {
                        ForEach(WandMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("按 Tab 在魔棒和对象之间切换")
                }
                if session.tool == .lasso {
                    Picker("套索", selection: Binding(get: { session.lassoKind }, set: { kind in
                        session.cancelLasso()
                        session.lassoKind = kind
                    })) {
                        ForEach(LassoKind.lassoChoices, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("按 L 在徒手和多边形之间切换")
                }
                // Shows held Shift/Option (or an outline's mode) live; clicking sets the choice.
                Picker("模式", selection: Binding(get: { session.displayedSelectionMode },
                                                  set: { session.selectionModeChoice = $0 })) {
                    ForEach(SelectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("按住 Shift 添加到选区，按住 Option 从选区减去（仅对当前一次有效）")
                if session.tool == .wand, session.wandMode == .wand { wandControls }
                if session.tool == .wand, session.wandMode == .object { objectSelectionControls }
                // Rectangles snap to whole pixels, so smoothing doesn't apply (as in Photoshop); ellipses curve.
                if session.tool == .lasso || session.tool == .wand || (session.tool == .marquee && session.marqueeKind == .ellipse) {
                    Toggle("消除锯齿", isOn: $session.selectionAntialiased)
                        .help(session.tool == .wand && session.wandMode == .object ? "平滑检测到的对象轮廓；关闭则使用原始像素蒙版" : "平滑选区边缘；关闭则为硬像素边缘")
                }
                Divider().frame(height: 18)
                modifyControls
                }
            }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            if let selection = session.selection {
                if selection.isEmpty { Text("空选区").foregroundStyle(.secondary) }
                Button("取消选择") { session.deselect() }.disabled(!session.canEditSelection)
            }
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }

    /// Tolerance, sample size, which pixels to read, and whether matches must connect.
    private var wandControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("容差").scrubbable(sensitivity: 1, value: $session.wandSettings.tolerance, range: 0...255)
                TextField("容差", value: Binding(get: { session.wandSettings.tolerance },
                                                      set: { session.wandSettings.tolerance = min(255, max(0, $0)) }),
                          format: .number)
                    .frame(width: ToolHeaderStyle.threeDigits).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.wandSettings.tolerance) },
                                change: { session.wandSettings.tolerance = Int(min(255, max(0, $0.rounded()))) })
            }
            .help("每个颜色通道（0–255）与点击颜色相差多少仍会被选中")
            Picker("取样大小", selection: $session.wandSettings.sampleSize) {
                ForEach(WandSampleSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            .help("匹配点击的像素，或其周围像素的平均值")
            Picker("取样", selection: $session.wandSettings.sampleAllLayers) {
                Text("当前图层").tag(false)
                Text("所有图层").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("仅从当前图层读取颜色，或按显示效果从所有可见图层读取")
            Toggle("连续", isOn: $session.wandSettings.contiguous)
                .help("只选中与点击处相连的相似像素；关闭则在整个图像中选择")
        }
    }

    private var objectSelectionControls: some View {
        HStack(spacing: 12) {
            Picker("取样", selection: $session.objectSelectionSettings.sampleAllLayers) {
                Text("当前图层").tag(false)
                Text("所有图层").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("仅分析当前图层，或按显示效果分析所有可见图层")
            HStack(spacing: 6) {
                Text("边缘").scrubbable(sensitivity: 1, value: $session.objectSelectionSettings.edgeOffset, range: -10...10)
                TextField("边缘", value: Binding(get: { session.objectSelectionSettings.edgeOffset },
                                                 set: { session.objectSelectionSettings.edgeOffset = min(10, max(-10, $0)) }),
                          format: .number)
                    .frame(width: ToolHeaderStyle.threeDigits).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.objectSelectionSettings.edgeOffset) },
                                change: { session.objectSelectionSettings.edgeOffset = Int(min(10, max(-10, $0.rounded()))) })
            }
            // The bar squeezes text before controls, so without this the label collapses to
            // nothing the moment a selection adds its own buttons, leaving an unlabelled number box.
            .fixedSize()
            .help("正值将检测到的蒙版向内收缩；负值向外扩展")
        }
    }

    /// Expand, Contract and Feather, sharing one pixel amount (1–500, default 5); all disabled without a selection.
    private var modifyControls: some View {
        HStack(spacing: 6) {
            Text("大小").scrubbable(sensitivity: 1, value: $session.selectionModifyAmount, range: 1...500)
            TextField("大小", value: Binding(get: { session.selectionModifyAmount },
                                             set: { session.selectionModifyAmount = min(500, max(1, $0)) }),
                      format: .number)
                .frame(width: ToolHeaderStyle.threeDigits).textFieldStyle(.roundedBorder)
                .arrowSteps(value: { Double(session.selectionModifyAmount) },
                            change: { session.selectionModifyAmount = Int(min(500, max(1, $0.rounded()))) })
            ToolHeaderPill {
                ForEach(EditorSession.SelectionAmountOperation.allCases, id: \.self) { operation in
                    Button {
                        session.modifySelection(operation, by: session.selectionModifyAmount)
                    } label: {
                        SelectionModifyIcon(operation: operation).frame(width: 14, height: 14)
                    }
                    .accessibilityLabel(operation.displayName)
                    .help("按此像素数\(operation.displayName)选区")
                }
            }
        }
        .help("扩展、收缩或羽化选区的像素数")
        .disabled(!session.canModifySelection)
    }
}

/// Header icons for changing a selection. Expand is a small outline with arrows pointing out, Contract a large
/// one with arrows pointing in, and Feather a solid square whose edge fades away.
struct SelectionModifyIcon: View {
    let operation: EditorSession.SelectionAmountOperation

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 18
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            func square(_ inset: CGFloat) -> CGRect {
                CGRect(x: inset * unit, y: inset * unit, width: (18 - inset * 2) * unit, height: (18 - inset * 2) * unit)
            }
            func stroke(_ points: [CGPoint]) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round, lineJoin: .round))
            }
            /// Mirrors a top-left corner's points to all four corners.
            func corners(_ draw: ((CGFloat, CGFloat) -> CGPoint) -> Void) {
                for (flipX, flipY) in [(false, false), (true, false), (false, true), (true, true)] {
                    draw { x, y in point(flipX ? 18 - x : x, flipY ? 18 - y : y) }
                }
            }
            switch operation {
            case .expand:
                context.stroke(Path(square(6.2)), with: .foreground,
                               style: StrokeStyle(lineWidth: 1.3 * unit, dash: [1.6 * unit, 1.2 * unit]))
                corners { at in
                    stroke([at(4.3, 4.3), at(1.6, 1.6)])
                    stroke([at(1.6, 4.3), at(1.6, 1.6), at(4.3, 1.6)])
                }
            case .contract:
                context.stroke(Path(square(1.4)), with: .foreground,
                               style: StrokeStyle(lineWidth: 1.3 * unit, dash: [1.8 * unit, 1.4 * unit]))
                corners { at in
                    stroke([at(4.3, 4.3), at(7.2, 7.2)])
                    stroke([at(7.2, 4.8), at(7.2, 7.2), at(4.8, 7.2)])
                }
            case .feather:
                context.fill(Path(roundedRect: square(6), cornerRadius: 1 * unit), with: .foreground)
                var middle = context
                middle.opacity = 0.6
                middle.stroke(Path(roundedRect: square(3.8), cornerRadius: 2 * unit), with: .foreground, lineWidth: 1.3 * unit)
                var outer = context
                outer.opacity = 0.28
                outer.stroke(Path(roundedRect: square(1.4), cornerRadius: 3.4 * unit), with: .foreground, lineWidth: 1.2 * unit)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tool-rail icon for the Polygonal Lasso: the lasso's loop and rope drawn as straight segments, in the
/// line weight of the SF Symbols beside it.
struct PolygonalLassoToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 18
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            // Laid out like the SF Symbol lasso: a wide loop, a knot below its right side, a short rope.
            var loop = Path()
            loop.addLines([point(1.2, 7.0), point(4.0, 2.4), point(11.8, 1.8), point(16.8, 5.2), point(15.6, 10.4), point(7.0, 11.6)])
            loop.closeSubpath()
            var knot = Path()
            knot.addLines([point(8.9, 10.9), point(13.3, 10.5), point(11.6, 14.5)])
            knot.closeSubpath()
            var rope = Path()
            rope.addLines([point(11.6, 14.5), point(12.9, 17.3)])
            let style = StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round, lineJoin: .round)
            for part in [loop, knot, rope] { context.stroke(part, with: .foreground, style: style) }
        }
        .accessibilityHidden(true)
    }
}

/// Selection modifiers share the filter panels' floating window and control layout.
struct SelectionAmountSheet: View {
    let session: EditorSession
    let operation: EditorSession.SelectionAmountOperation
    @State private var input: String
    @FocusState private var focused: Bool

    init(session: EditorSession, operation: EditorSession.SelectionAmountOperation) {
        self.session = session
        self.operation = operation
        // The shared amount can be more than Feather accepts.
        _input = State(initialValue: String(min(session.selectionModifyAmount, operation == .feather ? 250 : 500)))
    }

    private var maximum: Int { operation == .feather ? 250 : 500 }
    private var amount: Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...maximum).contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("数量").frame(minWidth: 60, alignment: .leading)
                    .scrubbable(sensitivity: 1,
                                value: Binding<Int>(get: { amount ?? 1 }, set: { input = String($0) }),
                                range: 1...maximum)
                Slider(value: Binding(get: { Double(amount ?? 1) },
                                      set: { input = String(Int($0.rounded())) }),
                       in: 1...Double(maximum))
                TextField("数量", text: $input)
                    .frame(width: 56).textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing).focused($focused)
                    .unitSuffix("px")
            }
            Text("请输入 1 到 \(maximum) 像素之间的整数。")
                .font(.callout).foregroundStyle(.secondary)
                .opacity(amount == nil ? 1 : 0)
            Divider()
            HStack {
                Button("取消") { session.selectionAmountOperation = nil }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button("确定") {
                    if let amount { session.confirmSelectionAmount(amount) }
                }
                .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
                .disabled(amount == nil)
            }
        }
        .padding(24).frame(width: 380).fixedSize()
        .onAppear { focused = true }
    }
}

struct ObjectSelectionToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 18
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            let style = StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round)
            for corners in [
                [point(2, 6), point(2, 2), point(6, 2)],
                [point(12, 2), point(16, 2), point(16, 6)],
                [point(16, 12), point(16, 16), point(12, 16)],
                [point(6, 16), point(2, 16), point(2, 12)]
            ] {
                var corner = Path()
                corner.addLines(corners)
                context.stroke(corner, with: .foreground, style: style)
            }
            var cursor = Path()
            cursor.addLines([point(7, 5), point(7, 14), point(9.6, 11.7), point(11.3, 15.3),
                             point(13.2, 14.4), point(11.5, 10.9), point(14.5, 10.9)])
            cursor.closeSubpath()
            context.fill(cursor, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
