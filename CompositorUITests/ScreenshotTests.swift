import AppKit
import XCTest

/// Screenshots of the main screens, so how the app looks can be checked without launching it: CI keeps them with
/// each run. Nothing is compared. A step that can't find what it needs records a failure, and the rest still run.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    func testMainScreens() throws {
        let app = XCUIApplication()
        // A fresh window at its default size, and no update check.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-SUEnableAutomaticChecks", "NO"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "the editor window")
        shoot("01 Start", window)

        try open(picture(), in: app)
        XCTAssertTrue(app.staticTexts["canvasDimensions"].waitForExistence(timeout: 10), "the opened picture")
        shoot("02 Editor", window)

        app.menuBars.menuBarItems["Filter"].click()
        shoot("03 Filter menu")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("i", modifierFlags: [.command, .option])
        shoot("04 Image Size", window)
        dismiss(app)

        app.typeKey("u", modifierFlags: .command)
        shoot("05 Hue Saturation")
        dismiss(app)

        app.menuBars.menuBarItems["Filter"].click()
        app.menuItems["Camera Raw Filter…"].click()
        shoot("06 Camera Raw", settle: 2)
        dismiss(app)

        app.typeKey("n", modifierFlags: .command)
        shoot("07 Second tab", window)
    }

    /// Waits for animations to finish, then keeps a screenshot of the element, or of the whole screen (for menus and
    /// panels outside the window).
    private func shoot(_ name: String, _ element: XCUIElement? = nil, settle seconds: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: seconds)
        let attachment = XCTAttachment(screenshot: element?.screenshot() ?? XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Cancels the sheet or panel showing, by its Cancel button where it has one.
    private func dismiss(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.click() } else { app.typeKey(.escape, modifierFlags: []) }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Opens a file in the app under test as the Finder would.
    private func open(_ file: URL, in app: XCUIApplication) throws {
        // This bundle is …/Products/Debug/CompositorUITests-Runner.app/Contents/PlugIns/CompositorUITests.xctest.
        var products = Bundle(for: Self.self).bundleURL
        for _ in 0..<4 { products.deleteLastPathComponent() }
        let compositor = products.appendingPathComponent("Compositor.app")
        let opened = expectation(description: "opened")
        NSWorkspace.shared.open([file], withApplicationAt: compositor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            XCTAssertNil(error)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 10)
    }

    /// A made-up landscape, for something to edit: a sunset sky, a sun and two rows of hills.
    private func picture() throws -> URL {
        let width = 2400, height = 1600
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let sky = try XCTUnwrap(CGGradient(colorsSpace: nil, colors: [
            CGColor(srgbRed: 0.98, green: 0.62, blue: 0.32, alpha: 1), CGColor(srgbRed: 0.42, green: 0.27, blue: 0.62, alpha: 1),
        ] as CFArray, locations: [0, 1]))
        context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        context.setFillColor(CGColor(srgbRed: 1, green: 0.88, blue: 0.6, alpha: 1))
        context.fillEllipse(in: CGRect(x: 1500, y: 520, width: 360, height: 360))
        for (base, color) in [(560.0, CGColor(srgbRed: 0.24, green: 0.32, blue: 0.36, alpha: 1)),
                              (300.0, CGColor(srgbRed: 0.12, green: 0.18, blue: 0.2, alpha: 1))] {
            context.setFillColor(color)
            context.move(to: .zero)
            for x in stride(from: 0, through: width, by: 40) {
                context.addLine(to: CGPoint(x: Double(x), y: base + 120 * sin(Double(x) / 330 + base)))
            }
            context.addLine(to: CGPoint(x: width, y: 0))
            context.fillPath()
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Landscape-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
