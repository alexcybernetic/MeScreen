//
//  MeScreenApp.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

import AppKit
import Combine
import SwiftUI

@main
struct MeScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.cameraManager)
                .environmentObject(appDelegate.settingsStore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }

            CommandGroup(replacing: .appTermination) {
                Button("Quit MeScreen") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusBarController: StatusBarController?
    private(set) var window: NSWindow?

    let cameraManager = CameraManager(
        startCamera: ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] == nil
    )
    let settingsStore = OverlaySettingsStore()

    private var customizationWindowController: CustomizationWindowController?
    private var globalShortcutController: GlobalShortcutController?
    private var isOverlayVisible = true
    private var lastObservedSettings: OverlaySettings?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = appIcon
        }

        statusBarController = StatusBarController(
            cameraManager: cameraManager,
            settingsStore: settingsStore,
            customizeAction: { [weak self] in
                self?.showCustomization()
            },
            toggleOverlayAction: { [weak self] in
                self?.toggleOverlay()
            }
        )
        statusBarController?.setupStatusBar()

        globalShortcutController = GlobalShortcutController { [weak self] in
            self?.toggleOverlay()
        }
        globalShortcutController?.setEnabled(
            settingsStore.settings.isGlobalShortcutEnabled
        )

        NSApp.setActivationPolicy(.accessory)
        observeSettings()

        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    func applicationDidUpdate(_ notification: Notification) {
        guard window == nil else { return }
        configureWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutController?.invalidate()
        cameraManager.stopCamera()
    }

    private func observeSettings() {
        lastObservedSettings = settingsStore.settings

        settingsStore.$settings
            .dropFirst()
            .sink { [weak self] settings in
                self?.applySettingsChange(settings)
            }
            .store(in: &cancellables)
    }

    private func applySettingsChange(_ settings: OverlaySettings) {
        let previousSettings = lastObservedSettings ?? settings
        lastObservedSettings = settings

        if settings.isGlobalShortcutEnabled
            != previousSettings.isGlobalShortcutEnabled {
            globalShortcutController?.setEnabled(
                settings.isGlobalShortcutEnabled
            )
        }

        let previousLayout = OverlayLayout(settings: previousSettings)
        let layout = OverlayLayout(settings: settings)
        if layout != previousLayout {
            updateWindowLayout(
                layout,
                placement: .preserveCurrentEdges,
                animated: true
            )
        }
    }

    private func configureWindow() {
        guard window == nil,
              let window = NSApplication.shared.windows.first(where: {
                  $0 !== customizationWindowController?.window
                      && $0.contentViewController != nil
                      && !($0 is NSPanel)
              }) else { return }
        self.window = window

        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.ignoresMouseEvents = false
        window.isExcludedFromWindowsMenu = true

        let layout = OverlayLayout(settings: settingsStore.settings)
        window.setContentSize(layout.contentSize)
        positionWindowAtStartingCorner(animated: false)
    }

    private func updateWindowLayout(
        _ layout: OverlayLayout,
        placement: WindowPlacement,
        animated: Bool
    ) {
        guard let window else {
            settingsStore.finishTransition()
            return
        }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? window.frame
        let origin = switch placement {
        case .startingCorner(let corner):
            corner.origin(
                for: layout.contentSize,
                in: visibleFrame
            )
        case .preserveCurrentEdges:
            resizedOrigin(
                from: window.frame,
                to: layout.contentSize,
                in: visibleFrame
            )
        }
        let frame = CGRect(origin: origin, size: layout.contentSize)

        guard animated else {
            window.setFrame(frame, display: true)
            settingsStore.finishTransition()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settingsStore.finishTransition()
            }
        })
    }

    private func positionWindowAtStartingCorner(animated: Bool) {
        let layout = OverlayLayout(settings: settingsStore.settings)
        updateWindowLayout(
            layout,
            placement: .startingCorner(settingsStore.settings.startingCorner),
            animated: animated
        )
    }

    private func resizedOrigin(
        from currentFrame: CGRect,
        to contentSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGPoint {
        let proposedX = currentFrame.midX <= visibleFrame.midX
            ? currentFrame.minX
            : currentFrame.maxX - contentSize.width
        let proposedY = currentFrame.midY <= visibleFrame.midY
            ? currentFrame.minY
            : currentFrame.maxY - contentSize.height

        return CGPoint(
            x: proposedX.clamped(
                to: visibleFrame.minX...(visibleFrame.maxX - contentSize.width)
            ),
            y: proposedY.clamped(
                to: visibleFrame.minY...(visibleFrame.maxY - contentSize.height)
            )
        )
    }

    private func showCustomization() {
        if customizationWindowController == nil {
            customizationWindowController = CustomizationWindowController(
                settingsStore: settingsStore
            )
        }
        customizationWindowController?.show()
    }

    private func toggleOverlay() {
        guard let window else { return }

        if isOverlayVisible {
            window.orderOut(nil)
            cameraManager.stopCamera()
            isOverlayVisible = false
        } else {
            window.orderFrontRegardless()
            cameraManager.refreshCameras()
            isOverlayVisible = true
        }

        statusBarController?.setOverlayVisible(isOverlayVisible)
    }
}

private enum WindowPlacement {
    case startingCorner(OverlayCorner)
    case preserveCurrentEdges
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
