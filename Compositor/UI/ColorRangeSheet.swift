import SwiftUI

/// Select > Color Range's panel: the eyedroppers, Fuzziness and Invert, with the selection updating on the canvas.
struct ColorRangeSheet: View {
    @Bindable var session: EditorSession
    private var edit: ColorRangeEdit? { session.colorRange }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(HueSampleMode.allCases, id: \.self) { mode in
                    Button { edit?.sampleMode = mode } label: { eyedropper(mode) }
                        .buttonStyle(.plain)
                        // Holding Shift or Option lights up the eyedropper a click will use.
                        .background(edit?.effectiveMode == mode ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .help(help(mode))
                        .accessibilityLabel("\(mode.rawValue) 颜色")
                }
                Spacer()
            }
            preview
            Text(edit?.hasColors == true ? "按住 Shift 点按可添加颜色，按住 Option 点按可减去颜色。"
                                         : "点按图像以选取要选择的颜色。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text("颜色容差").fixedSize()
                    .scrubbable(sensitivity: 1, value: fuzziness, range: ColorRangeEdit.fuzzinessRange)
                Slider(value: fuzziness, in: ColorRangeEdit.fuzzinessRange)
                TextField("颜色容差", value: fuzziness, format: .number.precision(.fractionLength(0)))
                    .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            }
            .help("颜色与已选取颜色相差多远仍会被选中")
            Toggle("反相", isOn: Binding(get: { edit?.invert ?? false }, set: { edit?.invert = $0; session.updateColorRange() }))
                .help("选择这些颜色以外的所有内容，例如绿幕之外的全部区域")
            if let error = edit?.error {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("取消") { session.cancelColorRange() }.configuredNativeShortcut(.escape)
                Spacer()
                Button("确定") { session.commitColorRange() }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 340).fixedSize()
    }

    /// The selection in black and white, white where selected, shaped like the canvas: black until a color is picked.
    private var preview: some View {
        let image = edit?.image
        let size = image.map { CGSize(width: $0.width, height: $0.height) } ?? ColorRangeEdit.previewSize
        let scale = min(ColorRangeEdit.previewSize.width / size.width, ColorRangeEdit.previewSize.height / size.height)
        return ZStack {
            Color.black
            if let picture = edit?.preview { Image(decorative: picture, scale: 2).resizable() }
        }
        .frame(width: size.width * scale, height: size.height * scale)
        .overlay { Rectangle().strokeBorder(.white.opacity(0.2)) }
        .frame(maxWidth: .infinity)
    }

    private var fuzziness: Binding<Double> {
        Binding(get: { edit?.fuzziness ?? 40 }, set: { value in
            let clamped = min(ColorRangeEdit.fuzzinessRange.upperBound, max(ColorRangeEdit.fuzzinessRange.lowerBound, value.rounded()))
            guard let edit, edit.fuzziness != clamped else { return }
            edit.fuzziness = clamped
            session.updateColorRange()
        })
    }

    private func help(_ mode: HueSampleMode) -> String {
        switch mode {
        case .replace: "点按图像以选择该颜色"
        case .add: "点按图像以将该颜色添加到选区"
        case .remove: "点按图像以将该颜色从选区中减去"
        }
    }

    /// The eyedropper, with a plus or minus badge for Add and Remove, as Hue/Saturation's.
    private func eyedropper(_ mode: HueSampleMode) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: mode.symbol)
            if let badge = mode.badge {
                Image(systemName: badge).font(.system(size: 8, weight: .semibold)).offset(x: 3, y: 1)
            }
        }
        .frame(width: 24, height: 20)
    }
}
