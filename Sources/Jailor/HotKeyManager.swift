import AppKit
import Carbon.HIToolbox

/// Registers global Carbon hotkeys (they work while the app is inactive).
final class HotKeyManager {

    var onPalette: (() -> Void)?
    var onFrame: ((Int) -> Void)?
    var onReveal: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let signature: OSType = 0x4A41494C // 'JAIL'

    init() {
        installHandler()
        registerHotKeys()
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handle(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            NSLog("Jailor: could not install hotkey handler (\(status))")
        }
    }

    private func registerHotKeys() {
        // ⌃⌥Space: open the quick-assign palette.
        register(keyCode: UInt32(kVK_Space), id: 1, action: .palette)

        // ⌃⌥R: hide the dashboard and reveal the layout windows.
        register(keyCode: UInt32(kVK_ANSI_R), id: 2, action: .reveal)

        // ⌃⌥1…9: assign the focused window to the matching frame.
        let digitKeyCodes: [Int] = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
            kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        for (index, keyCode) in digitKeyCodes.enumerated() {
            register(keyCode: UInt32(keyCode), id: UInt32(100 + index), action: .frame(index))
        }
    }

    private enum Action {
        case palette
        case reveal
        case frame(Int)
    }

    private func register(keyCode: UInt32, id: UInt32, action: Action) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
            actions[id] = action
        } else {
            NSLog("Jailor: could not register hotkey id \(id) (\(status))")
        }
    }

    private var actions: [UInt32: Action] = [:]

    private func handle(id: UInt32) {
        switch actions[id] {
        case .palette:
            onPalette?()
        case .reveal:
            onReveal?()
        case .frame(let index):
            onFrame?(index)
        case nil:
            break
        }
    }
}
