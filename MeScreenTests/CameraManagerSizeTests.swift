import XCTest
@testable import MeScreen

@MainActor
private struct ImmediateCameraTransitionScheduler: CameraTransitionScheduling {
    func schedule(_ action: @escaping @MainActor @Sendable () -> Void) {
        action()
    }
}

nonisolated final class CameraManagerSizeTests: XCTestCase {
    @MainActor
    func testWindowSizeMetadata() {
        XCTAssertEqual(WindowSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(WindowSize.allCases.map(\.rawValue), [100, 150, 200])
        XCTAssertEqual(WindowSize.allCases.map(\.displayName), ["Small", "Medium", "Large"])
    }

    @MainActor
    func testSizeTransitionLifecycle() {
        let manager = makeManager()

        manager.changeSize(to: .large)
        XCTAssertTrue(manager.isTransitioning)
        XCTAssertEqual(manager.windowSize, .large)

        manager.finishTransition()
        XCTAssertFalse(manager.isTransitioning)
    }

    @MainActor
    func testOverlappingSizeChangeIsIgnored() {
        let manager = makeManager()

        manager.changeSize(to: .large)
        manager.changeSize(to: .small)

        XCTAssertEqual(manager.windowSize, .large)
    }

    @MainActor
    private func makeManager() -> CameraManager {
        CameraManager(
            startCamera: false,
            transitionScheduler: ImmediateCameraTransitionScheduler()
        )
    }
}
