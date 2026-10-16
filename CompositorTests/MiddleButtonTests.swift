import AppKit
import Testing
@testable import Compositor

/// The middle button pans the canvas, and with Command or Control held zooms it, as in Blender.
@MainActor
@Suite(.serialized)
struct MiddleButtonTests {
    private func canvas() throws -> (EditorSession, CanvasView, NSWindow) {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 450), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: try #require(session.document?.size))
        return (session, view, window)
    }

    /// A middle-button event `rise` points above where the drag started (screen coordinates rise upward).
    private func event(_ type: CGEventType, rise: CGFloat, flags: CGEventFlags = []) throws -> NSEvent {
        let cg = try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 300, y: 600 - rise),
                                      mouseButton: .center))
        cg.flags = flags
        return try #require(NSEvent(cgEvent: cg))
    }

    @Test(arguments: [CGEventFlags.maskCommand, .maskControl])
    func dragUpZoomsInAndDownZoomsOut(_ modifier: CGEventFlags) throws {
        let (session, view, window) = try canvas()
        defer { window.orderOut(nil) }
        let start = session.viewport.zoom
        view.otherMouseDown(with: try event(.otherMouseDown, rise: 0, flags: modifier))
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: 100, flags: modifier))
        #expect(abs(session.viewport.zoom - start * 2) < 0.01, "100 points up doubles the zoom: \(start) → \(session.viewport.zoom)")
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: -100, flags: modifier))
        #expect(abs(session.viewport.zoom - start / 2) < 0.01, "100 points down halves it: \(session.viewport.zoom)")
        view.otherMouseUp(with: try event(.otherMouseUp, rise: -100, flags: modifier))
    }

    @Test(arguments: [CGEventFlags.maskCommand, .maskControl])
    func zoomCursorChangesAsSoonAsTheDragReverses(_ modifier: CGEventFlags) throws {
        let (session, view, window) = try canvas()
        defer { window.orderOut(nil) }
        view.otherMouseDown(with: try event(.otherMouseDown, rise: 0, flags: modifier))
        let zoomInCursor = NSCursor.current
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: 100, flags: modifier))
        let peak = session.viewport.zoom
        #expect(NSCursor.current === zoomInCursor)
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: 80, flags: modifier))
        #expect(session.viewport.zoom < peak)
        let zoomOutCursor = NSCursor.current
        #expect(zoomOutCursor !== zoomInCursor, "reverse above the starting point")
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: 80, flags: modifier))
        #expect(NSCursor.current === zoomOutCursor, "no vertical movement keeps the direction")
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: -100, flags: modifier))
        #expect(NSCursor.current === zoomOutCursor)
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: -80, flags: modifier))
        #expect(NSCursor.current === zoomInCursor, "reverse below the starting point")
        view.otherMouseUp(with: try event(.otherMouseUp, rise: -80, flags: modifier))
    }

    @Test func withoutAModifierItPans() throws {
        let (session, view, window) = try canvas()
        defer { window.orderOut(nil) }
        let zoom = session.viewport.zoom, pan = session.viewport.pan
        view.otherMouseDown(with: try event(.otherMouseDown, rise: 0))
        view.otherMouseDragged(with: try event(.otherMouseDragged, rise: 40))
        view.otherMouseUp(with: try event(.otherMouseUp, rise: 40))
        #expect(session.viewport.zoom == zoom)
        #expect(session.viewport.pan != pan)
    }

    @Test(arguments: [3, 30])
    func middleDraggingScrollsOnlyTheLayerList(_ count: Int) throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 80, emptyLayer: true)
        for _ in 1..<count { session.addBlankLayer() }
        let coordinator = NativeLayerList.Coordinator(session: session)
        let table = LayerTableView()
        table.session = session
        table.headerView = nil
        table.rowHeight = 52
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer")))
        table.delegate = coordinator
        table.dataSource = coordinator
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 252, height: 400))
        scroll.documentView = table
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.orderOut(nil) }
        coordinator.update(table)
        scroll.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        let selection = session.selectedLayerIDs
        let rows = table.selectedRowIndexes
        let history = session.history.undoCount
        let pan = session.viewport.pan
        let maximum = max(0, table.bounds.height - scroll.contentView.bounds.height)
        #expect((maximum > 0) == (count == 30))
        table.otherMouseDown(with: try event(.otherMouseDown, rise: 0))
        table.otherMouseDragged(with: try event(.otherMouseDragged, rise: 100))
        #expect(abs(scroll.contentView.bounds.minY - min(100, maximum)) < 0.01)
        table.otherMouseDragged(with: try event(.otherMouseDragged, rise: 10000))
        #expect(abs(scroll.contentView.bounds.minY - maximum) < 0.01)
        table.otherMouseDragged(with: try event(.otherMouseDragged, rise: 9960))
        #expect(abs(scroll.contentView.bounds.minY - max(0, maximum - 40)) < 0.01)
        table.otherMouseDragged(with: try event(.otherMouseDragged, rise: -10000))
        #expect(abs(scroll.contentView.bounds.minY) < 0.01)
        table.otherMouseUp(with: try event(.otherMouseUp, rise: -10000))
        // Dragging after release has no effect.
        table.otherMouseDragged(with: try event(.otherMouseDragged, rise: 100))
        #expect(abs(scroll.contentView.bounds.minY) < 0.01)
        #expect(session.selectedLayerIDs == selection && table.selectedRowIndexes == rows)
        #expect(session.history.undoCount == history && session.viewport.pan == pan)
    }

}
