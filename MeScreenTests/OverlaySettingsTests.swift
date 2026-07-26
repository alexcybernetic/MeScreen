import XCTest
import AppKit
@testable import MeScreen

nonisolated final class OverlaySettingsTests: XCTestCase {
    @MainActor
    func testWindowSizeMetadata() {
        XCTAssertEqual(WindowSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(WindowSize.allCases.map(\.rawValue), [100, 150, 200])
        XCTAssertEqual(
            WindowSize.allCases.map(\.displayName),
            ["Small", "Medium", "Large"]
        )
    }

    @MainActor
    func testAppearanceDefaults() {
        let settings = OverlaySettings()

        XCTAssertEqual(settings.shape, .circle)
        XCTAssertEqual(settings.borderColor, .white)
        XCTAssertEqual(settings.borderWidth, 3)
        XCTAssertTrue(settings.hasShadow)
        XCTAssertEqual(settings.shadowSoftness, 6)
        XCTAssertEqual(settings.shadowIntensity, 0.65)
        XCTAssertFalse(settings.hasReflection)
    }

    @MainActor
    func testSettingsPersistAsSingleLocalValue() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = OverlaySettingsStore(defaults: defaults)
        store.update { settings in
            settings.shape = .octagon
            settings.borderWidth = 7
            settings.label.isEnabled = true
            settings.label.text = "Alex"
            settings.startingCorner = .bottomLeft
        }

        let restored = OverlaySettingsStore(defaults: defaults)
        XCTAssertEqual(restored.settings.shape, .octagon)
        XCTAssertEqual(restored.settings.borderWidth, 7)
        XCTAssertTrue(restored.settings.label.isEnabled)
        XCTAssertEqual(restored.settings.label.text, "Alex")
        XCTAssertEqual(restored.settings.startingCorner, .bottomLeft)
    }

    @MainActor
    func testRemovedPillBorderDoesNotBreakExistingSettings() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let encoded = try JSONEncoder().encode(OverlaySettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var label = try XCTUnwrap(object["label"] as? [String: Any])
        label["hasBorder"] = true
        object["label"] = label

        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: "overlay.settings.v1"
        )

        XCTAssertEqual(
            OverlaySettingsStore(defaults: defaults).settings,
            OverlaySettings()
        )
    }

    @MainActor
    func testResetRestoresAndPersistsDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = OverlaySettingsStore(defaults: defaults)
        store.update { settings in
            settings.windowSize = .large
            settings.shape = .square
            settings.hasReflection = true
            settings.label.isEnabled = true
            settings.label.text = "Presenter"
            settings.isGlobalShortcutEnabled = false
        }

        store.reset()

        XCTAssertEqual(store.settings, OverlaySettings())
        XCTAssertEqual(
            OverlaySettingsStore(defaults: defaults).settings,
            OverlaySettings()
        )
    }

    @MainActor
    func testSettingsNormalizationConstrainsUserInput() {
        let store = OverlaySettingsStore(defaults: nil)
        store.update { settings in
            settings.borderWidth = 99
            settings.shadowIntensity = -1
            settings.label.fontSize = 100
            settings.label.text = String(repeating: "a", count: 50) + "\nname"
        }

        XCTAssertEqual(store.settings.borderWidth, 12)
        XCTAssertEqual(store.settings.shadowIntensity, 0.05)
        XCTAssertEqual(store.settings.label.fontSize, 24)
        XCTAssertEqual(
            store.settings.label.text.count,
            OverlaySettings.maximumLabelLength
        )
        XCTAssertFalse(store.settings.label.text.contains("\n"))
    }

    @MainActor
    func testSizeTransitionLifecycle() {
        let store = OverlaySettingsStore(defaults: nil)

        store.changeSize(to: .large)
        XCTAssertTrue(store.isTransitioning)
        XCTAssertEqual(store.settings.windowSize, .large)

        store.changeSize(to: .small)
        XCTAssertEqual(store.settings.windowSize, .large)

        store.finishTransition()
        XCTAssertFalse(store.isTransitioning)
    }

    @MainActor
    func testLayoutAccountsForReflectionLabelAndShadow() {
        var settings = OverlaySettings()
        XCTAssertEqual(
            OverlayLayout(settings: settings).contentSize,
            CGSize(width: 176, height: 176)
        )

        settings.hasReflection = true
        settings.label.isEnabled = true
        settings.label.text = "Presenter"

        let layout = OverlayLayout(settings: settings)
        let expectedLabelHeight = ceil(
            NSFont.systemFont(ofSize: 14, weight: .semibold)
                .boundingRectForFont.height + 10
        )
        XCTAssertEqual(layout.outerPadding, 13)
        XCTAssertEqual(layout.reflectionHeight, 38)
        XCTAssertEqual(layout.labelHeight, expectedLabelHeight)
        XCTAssertEqual(
            layout.contentSize,
            CGSize(width: 176, height: 224 + expectedLabelHeight)
        )
    }

    @MainActor
    func testCornerPlacementUsesVisibleScreenFrame() {
        let visibleFrame = CGRect(x: 10, y: 20, width: 500, height: 400)
        let contentSize = CGSize(width: 100, height: 80)

        XCTAssertEqual(
            OverlayCorner.topLeft.origin(
                for: contentSize,
                in: visibleFrame
            ),
            CGPoint(x: 30, y: 320)
        )
        XCTAssertEqual(
            OverlayCorner.topRight.origin(
                for: contentSize,
                in: visibleFrame
            ),
            CGPoint(x: 390, y: 320)
        )
        XCTAssertEqual(
            OverlayCorner.bottomLeft.origin(
                for: contentSize,
                in: visibleFrame
            ),
            CGPoint(x: 30, y: 40)
        )
        XCTAssertEqual(
            OverlayCorner.bottomRight.origin(
                for: contentSize,
                in: visibleFrame
            ),
            CGPoint(x: 390, y: 40)
        )
    }

    @MainActor
    func testFlipsUseDisplayedAxesAfterRotation() {
        let transform = CameraImageTransform.make(
            isFlippedHorizontally: true,
            isFlippedVertically: false,
            rotation: .degrees90
        )

        let transformedVerticalPoint = CGPoint(x: 0, y: 1)
            .applying(transform)
        XCTAssertEqual(transformedVerticalPoint.x, 1, accuracy: 0.000_001)
        XCTAssertEqual(transformedVerticalPoint.y, 0, accuracy: 0.000_001)
    }

    @MainActor
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "OverlaySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
