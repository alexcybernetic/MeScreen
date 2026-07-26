//
//  StatusBarController.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

import AppKit
import Combine

private struct StatusMenuSettings: Equatable {
    let windowSize: WindowSize
    let isGlobalShortcutEnabled: Bool
}

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let cameraManager: CameraManager
    private let settingsStore: OverlaySettingsStore
    private let customizeAction: @MainActor () -> Void
    private let toggleOverlayAction: @MainActor () -> Void
    private var isOverlayVisible = true
    private var isMenuUpdateScheduled = false
    private var cancellables = Set<AnyCancellable>()

    init(
        cameraManager: CameraManager,
        settingsStore: OverlaySettingsStore,
        customizeAction: @escaping @MainActor () -> Void,
        toggleOverlayAction: @escaping @MainActor () -> Void
    ) {
        self.cameraManager = cameraManager
        self.settingsStore = settingsStore
        self.customizeAction = customizeAction
        self.toggleOverlayAction = toggleOverlayAction

        cameraManager.$availableCameras
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleMenuUpdate()
            }
            .store(in: &cancellables)

        cameraManager.$currentCamera
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleMenuUpdate()
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map {
                StatusMenuSettings(
                    windowSize: $0.windowSize,
                    isGlobalShortcutEnabled: $0.isGlobalShortcutEnabled
                )
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleMenuUpdate()
            }
            .store(in: &cancellables)

        cameraManager.$cameraState
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleMenuUpdate()
            }
            .store(in: &cancellables)
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "video.circle.fill", accessibilityDescription: "MeScreen")
            button.setAccessibilityLabel("MeScreen")
        }

        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        let toggleTitle = isOverlayVisible ? "Hide Overlay" : "Show Overlay"
        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleOverlay),
            keyEquivalent: settingsStore.settings.isGlobalShortcutEnabled
                ? GlobalShortcutDefinition.keyEquivalent
                : ""
        )
        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = GlobalShortcutDefinition
            .modifierFlags
        toggleItem.image = NSImage(
            systemSymbolName: isOverlayVisible ? "eye.slash" : "eye",
            accessibilityDescription: toggleTitle
        )
        menu.addItem(toggleItem)

        let customizeItem = NSMenuItem(
            title: "Customize…",
            action: #selector(showCustomization),
            keyEquivalent: ","
        )
        customizeItem.target = self
        customizeItem.keyEquivalentModifierMask = [.command]
        customizeItem.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "Customize"
        )
        menu.addItem(customizeItem)
        menu.addItem(NSMenuItem.separator())

        // Size selection section with icon
        let sizeHeader = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeHeader.image = NSImage(systemSymbolName: "aspectratio", accessibilityDescription: "Size")
        menu.addItem(sizeHeader)
        menu.addItem(NSMenuItem.separator())

        for size in WindowSize.allCases {
            let sizeItem = NSMenuItem(title: size.displayName, action: #selector(selectSize(_:)), keyEquivalent: "")
            sizeItem.target = self
            sizeItem.representedObject = size
            sizeItem.state = size == settingsStore.settings.windowSize ? .on : .off

            // Add icon based on size
            let iconName = switch size {
            case .small: "circle.fill"
            case .medium: "circle.circle"
            case .large: "circle.circle.fill"
            }
            sizeItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: size.displayName)
            menu.addItem(sizeItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Camera selection section with icon
        let cameraHeader = NSMenuItem(title: "Cameras", action: nil, keyEquivalent: "")
        cameraHeader.image = NSImage(systemSymbolName: "video", accessibilityDescription: "Cameras")
        menu.addItem(cameraHeader)
        menu.addItem(NSMenuItem.separator())

        if !isOverlayVisible {
            let inactiveItem = NSMenuItem(
                title: "Camera is off while the overlay is hidden.",
                action: nil,
                keyEquivalent: ""
            )
            inactiveItem.isEnabled = false
            inactiveItem.image = NSImage(
                systemSymbolName: "video.slash",
                accessibilityDescription: "Camera off"
            )
            menu.addItem(inactiveItem)
        } else if let statusMessage = cameraManager.cameraState.menuMessage {
            let statusItem = NSMenuItem(
                title: statusMessage,
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            statusItem.image = NSImage(
                systemSymbolName: cameraManager.cameraState.symbolName,
                accessibilityDescription: statusMessage
            )
            menu.addItem(statusItem)
        }

        if isOverlayVisible && cameraManager.availableCameras.isEmpty {
            let noCamera = NSMenuItem(title: "No cameras found", action: nil, keyEquivalent: "")
            noCamera.isEnabled = false
            noCamera.image = NSImage(systemSymbolName: "video.slash", accessibilityDescription: "No cameras")
            menu.addItem(noCamera)
        } else if isOverlayVisible {
            for camera in cameraManager.availableCameras {
                let menuItem = NSMenuItem(
                    title: camera.name,
                    action: #selector(selectCamera(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = camera
                menuItem.state = camera == cameraManager.currentCamera ? .on : .off

                // Icon for camera type
                let iconName = camera.isExternal ? "video.fill" : "video.circle.fill"
                menuItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: camera.name)
                menu.addItem(menuItem)
            }
        }

        if cameraManager.cameraState == .permissionDenied {
            let settingsItem = NSMenuItem(
                title: "Open Camera Settings",
                action: #selector(openCameraSettings),
                keyEquivalent: ""
            )
            settingsItem.target = self
            settingsItem.image = NSImage(
                systemSymbolName: "gear",
                accessibilityDescription: "Open Camera Settings"
            )
            menu.addItem(settingsItem)
        }

        let refresh = NSMenuItem(
            title: "Refresh Cameras",
            action: #selector(refreshCameras),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = isOverlayVisible
        refresh.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Refresh"
        )
        menu.addItem(refresh)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About MeScreen", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About MeScreen")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit MeScreen", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func selectSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? WindowSize else { return }
        settingsStore.changeSize(to: size)
    }

    @objc func toggleOverlay() {
        toggleOverlayAction()
    }

    @objc func showCustomization() {
        customizeAction()
    }

    @objc func refreshCameras() {
        guard isOverlayVisible else { return }
        cameraManager.refreshCameras()
    }

    @objc func openCameraSettings() {
        cameraManager.openCameraSettings()
    }

    @objc func selectCamera(_ sender: NSMenuItem) {
        guard let camera = sender.representedObject as? CameraDescriptor else { return }
        cameraManager.switchCamera(to: camera)
    }

    @objc func showAbout() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Your camera, always in view.\n\n",
            attributes: [.paragraphStyle: paragraphStyle]
        )

        if let projectURL = URL(string: "https://github.com/alexcybernetic/mescreen") {
            credits.append(
                NSAttributedString(
                    string: "github.com/alexcybernetic/mescreen",
                    attributes: [
                        .foregroundColor: NSColor.linkColor,
                        .link: projectURL,
                        .paragraphStyle: paragraphStyle
                    ]
                )
            )
        }

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "MeScreen",
            .applicationVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Development",
            .credits: credits
        ]

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    func setOverlayVisible(_ isVisible: Bool) {
        guard isVisible != isOverlayVisible else { return }
        isOverlayVisible = isVisible
        updateMenu()
    }

    private func scheduleMenuUpdate() {
        guard !isMenuUpdateScheduled else { return }
        isMenuUpdateScheduled = true

        // @Published emits before its stored property is committed. Rebuild on
        // the next main-loop turn so every menu item reads one coherent state.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMenuUpdateScheduled = false
            self.updateMenu()
        }
    }

#if DEBUG
    var menuForTesting: NSMenu? {
        statusItem?.menu
    }
#endif
}
