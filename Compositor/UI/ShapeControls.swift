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
            if session.shapeKind == .line {
                HStack(spacing: 6) {
                    Text("宽度").scrubbable(sensitivity: 1, value: $session.shapeLineWidth, range: 1...5000)
                    Slider(value: Binding(get: { min(100, session.shapeLineWidth) },
                                          set: { session.shapeLineWidth = $0.rounded() }), in: 1...100)
                        .frame(width: 100)
                    TextField("宽度", value: Binding(get: { session.shapeLineWidth },
                                                      set: { session.shapeLineWidth = $0.isFinite ? min(5000, max(1, $0)) : 4 }),
                              format: .number.precision(.fractionLength(0)))
                        .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .arrowSteps(value: { session.shapeLineWidth },
                                    change: { session.shapeLineWidth = min(5000, max(1, $0)) })
                        .unitSuffix("px")
                }
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
                        .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .arrowSteps(value: { Double(session.shapeCornerRadius) },
                                    change: { session.shapeCornerRadius = min(5000, max(0, CGFloat($0))) })
                        .unitSuffix("px")
                }
                .help("将矩形的角按此像素数倒圆；0 保持直角")
            }
            HStack(spacing: 6) {
                Text("填充")
                Button { session.openColorPicker(background: false) } label: {
                    let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
                    swatch.fill(Color(nsColor: session.foregroundColor.nsColor))
                        .overlay { swatch.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                        .frame(width: 36, height: 18)
                }
                .buttonStyle(.plain)
                .help("形状以前景色填充；点按可更改")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }
}
