//
//  MeScreenApp.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

import SwiftUI
import Combine

@main
struct MeScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.cameraManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Remove most menu items but keep Quit working
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }

            // Ensure Quit works
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
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var window: NSWindow?
    let cameraManager = CameraManager(
        startCamera: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the compiled bundle icon instead of looking for a loose PNG file.
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = appIcon
        }

        // Setup status bar first
        statusBarController = StatusBarController(cameraManager: cameraManager)
        statusBarController?.setupStatusBar()

        // Keep MeScreen out of the Dock; all controls live in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        // Observe size changes and update window size
        cameraManager.$windowSize
            .sink { [weak self] _ in
                self?.updateWindowSize()
            }
            .store(in: &cancellables)

        // Try on the next run-loop pass. applicationDidUpdate provides a
        // deterministic fallback until SwiftUI has installed its window.
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    func applicationDidUpdate(_ notification: Notification) {
        guard window == nil else { return }
        configureWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraManager.stopCamera()
    }

    func configureWindow() {
        guard window == nil,
              let window = NSApplication.shared.windows.first(where: {
                  $0.contentViewController != nil && !($0 is NSPanel)
              }) else { return }
        self.window = window

        // Make window float on top and draggable
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear  // Transparent background!
        window.isOpaque = false
        window.hasShadow = false  // Turn OFF window shadow - ContentView has its own
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.ignoresMouseEvents = false

        // Set the content size based only on cameraManager.windowSize.rawValue
        let contentSize = cameraManager.windowSize.rawValue
        window.setContentSize(NSSize(width: contentSize, height: contentSize))

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - contentSize - 20
            let y = screenFrame.maxY - contentSize - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func updateWindowSize() {
        guard let window else {
            // Do not leave the preview hidden if a size command arrives before
            // SwiftUI has finished creating the window.
            if cameraManager.isTransitioning {
                cameraManager.finishTransition()
            }
            return
        }

        let contentSize = cameraManager.windowSize.rawValue

        // Animate the size change (0.45s for a smooth, unhurried resize)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setContentSize(NSSize(width: contentSize, height: contentSize))
        }, completionHandler: { [weak self] in
            // NSAnimationContext does not annotate this callback as main-actor
            // isolated, even though AppKit invokes it on the main thread.
            Task { @MainActor [weak self] in
                self?.cameraManager.finishTransition()
            }
        })
    }
}
