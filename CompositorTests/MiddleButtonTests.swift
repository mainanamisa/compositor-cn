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
}
