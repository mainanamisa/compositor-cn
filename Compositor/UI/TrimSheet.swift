import SwiftUI

struct TrimSheet: View {
    let finish: (TrimOptions?) -> Void
    @State private var basedOn: TrimBasedOn = .transparentPixels
    @State private var trimTop: Bool = true
    @State private var trimBottom: Bool = true
    @State private var trimLeft: Bool = true
    @State private var trimRight: Bool = true

    var body: some View { sheet.roundedControls() }

    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("裁切").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("基于").font(.headline)
                Picker("", selection: $basedOn) {
                    ForEach(TrimBasedOn.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("裁掉").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Toggle("顶边", isOn: $trimTop)
                        Toggle("底边", isOn: $trimBottom)
                    }
                    GridRow {
                        Toggle("左边", isOn: $trimLeft)
                        Toggle("右边", isOn: $trimRight)
                    }
                }
            }

            Divider()

            HStack {
                Button("取消") { finish(nil) }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button("好") {
                    let options = TrimOptions(
                        basedOn: basedOn,
                        top: trimTop,
                        bottom: trimBottom,
                        left: trimLeft,
                        right: trimRight
                    )
                    finish(options)
                }
                .configuredNativeShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!trimTop && !trimBottom && !trimLeft && !trimRight)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

private extension TrimBasedOn {
    var displayName: String {
        switch self {
        case .transparentPixels: return "透明像素"
        case .topLeftPixelColor: return "左上角像素颜色"
        case .bottomRightPixelColor: return "右下角像素颜色"
        }
    }
}
