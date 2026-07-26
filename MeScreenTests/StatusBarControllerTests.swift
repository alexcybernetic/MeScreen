import AppKit
import XCTest
@testable import MeScreen

nonisolated final class StatusBarControllerTests: XCTestCase {
    @MainActor
    func testSizeMenuReflectsCommittedSettingsValue() async {
        let settingsStore = OverlaySettingsStore(defaults: nil)
        let controller = StatusBarController(
            cameraManager: CameraManager(startCamera: false),
            settingsStore: settingsStore,
            customizeAction: {},
            toggleOverlayAction: {}
        )
        controller.setupStatusBar()

        settingsStore.changeSize(to: .large)
        await nextMainQueueTurn()

        let menu = controller.menuForTesting
        XCTAssertEqual(menuItem(named: "Small", in: menu)?.state, .off)
        XCTAssertEqual(menuItem(named: "Medium", in: menu)?.state, .off)
        XCTAssertEqual(menuItem(named: "Large", in: menu)?.state, .on)
    }

    @MainActor
    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func menuItem(
        named title: String,
        in menu: NSMenu?
    ) -> NSMenuItem? {
        menu?.items.first { $0.title == title }
    }
}
