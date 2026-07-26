@preconcurrency import Carbon.HIToolbox
import AppKit

enum GlobalShortcutDefinition {
    static let keyEquivalent = "m"
    static let displayName = "⇧⌥⌘M"
    static let modifierFlags: NSEvent.ModifierFlags = [
        .command,
        .option,
        .shift,
    ]
    static let carbonKeyCode = UInt32(kVK_ANSI_M)
    static let carbonModifiers = UInt32(cmdKey | optionKey | shiftKey)
}

@MainActor
final class GlobalShortcutController {
    private static let hotKeySignature: FourCharCode = 0x4D655363 // MeSc
    private static let hotKeyIdentifier: UInt32 = 1

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        installEventHandler()
    }

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            registerHotKeyIfNeeded()
        } else {
            unregisterHotKey()
        }
    }

    func invalidate() {
        unregisterHotKey()
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.performAction()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
    }

    private func registerHotKeyIfNeeded() {
        guard hotKeyReference == nil else { return }

        let identifier = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        RegisterEventHotKey(
            GlobalShortcutDefinition.carbonKeyCode,
            GlobalShortcutDefinition.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }

    private func unregisterHotKey() {
        guard let hotKeyReference else { return }
        UnregisterEventHotKey(hotKeyReference)
        self.hotKeyReference = nil
    }

    private func performAction() {
        action()
    }
}
