import AppKit
import Testing
@testable import Compositor

/// Issue #2: a saved .comp reopened later must list every layer at once, not one until a click or rename
/// nudges the panel.
@MainActor
struct ReopenedProjectLayerListTests {
    private func makeTable(session: EditorSession) -> (LayerTableView, NativeLayerList.Coordinator) {
        let coordinator = NativeLayerList.Coordinator(session: session)
        let table = LayerTableView()
        table.session = session
        table.rowHeight = 52
        table.allowsMultipleSelection = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer"))
        column.width = 252
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        return (table, coordinator)
    }

    @Test func aReopenedProjectListsAllItsLayers() async throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        for _ in 0..<3 { session.addBlankLayer() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let reopened = EditorSession()
        let controller = ProjectController(session: reopened)
        #expect(await controller.open(url))
        #expect(reopened.document?.layers.count == 3)
        #expect(reopened.layerRows.count == 3)

        let (table, coordinator) = makeTable(session: reopened)
        coordinator.update(table)
        #expect(coordinator.numberOfRows(in: table) == 3)
    }

    /// The reporter's exact shape: three imported image layers, saved, reopened.
    @Test func aReopenedProjectOfImportedImagesListsAllItsLayers() async throws {
        func png() throws -> URL {
            let context = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 256,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            let image = try #require(context.makeImage())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            return url
        }
        let session = EditorSession()
        try await session.importImages([png(), png(), png()])
        #expect(session.document?.layers.count == 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let reopened = EditorSession()
        let controller = ProjectController(session: reopened)
        #expect(await controller.open(url))
        #expect(reopened.document?.layers.count == 3)
        #expect(reopened.layerRows.count == 3)

        let (table, coordinator) = makeTable(session: reopened)
        coordinator.update(table)
        #expect(coordinator.numberOfRows(in: table) == 3)
    }
}
