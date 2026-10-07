import SwiftUI

struct PSDConversionRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let confirmTitle: String
    var conversions: [PSDConversion]
    /// The file is still being read: the sheet is up so the click feels answered, but it has
    /// nothing to report yet.
    var isReading: Bool
    init(id: UUID = UUID(), title: String, confirmTitle: String, conversions: [PSDConversion], isReading: Bool = false) {
        self.id = id
        self.title = title
        self.confirmTitle = confirmTitle
        self.conversions = conversions
        self.isReading = isReading
    }
}

struct PSDConversionSheet: View {
    let request: PSDConversionRequest
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title).font(.title2.bold())
            Text(request.isReading ? "正在读取文件，查看需要转换的内容。"
                 : "Compositor 将转换以下 Photoshop 功能。在你继续之前不会应用任何更改。")
                .foregroundStyle(.secondary)
            if request.isReading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Photoshop 文件…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(request.conversions) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.layerName).font(.headline)
                        Text(item.message)
                    }.padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
            HStack {
                Spacer()
                Button("取消") { finish(false) }.keyboardShortcut(.cancelAction)
                Button(request.confirmTitle) { finish(true) }.keyboardShortcut(.defaultAction)
                    .disabled(request.isReading)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .roundedControls()
    }
}

extension View {
    func psdConversionSheet(_ session: EditorSession) -> some View {
        sheet(isPresented: Binding(
            get: { session.showsConversionSheet },
            set: { if !$0 { session.finishConversion(false) } }
        )) {
            if let request = session.conversionRequest {
                PSDConversionSheet(request: request, finish: session.finishConversion)
            }
        }
    }
}
