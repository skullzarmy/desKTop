import AppKit
import Carbon

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var isEnabled: Bool

    public init(keyCode: UInt32, modifiers: UInt32, isEnabled: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    public var displayString: String {
        guard isEnabled else { return "Disabled" }
        var parts = ""
        if (modifiers & UInt32(controlKey)) != 0 { parts += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { parts += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { parts += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { parts += "⌘" }
        parts += Self.keyLabel(for: keyCode)
        return parts
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    public static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_RightArrow: return "→"
        case kVK_LeftArrow: return "←"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key(\(keyCode))"
        }
    }
}

public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case nextArtwork = 1
    case previousArtwork = 2
    case togglePause = 3
    case peekHUD = 4
    case toggleDesktopIcons = 5
    case toggleInteractive = 6

    public var keyCode: UInt32 {
        switch self {
        case .nextArtwork: return UInt32(kVK_RightArrow)
        case .previousArtwork: return UInt32(kVK_LeftArrow)
        case .togglePause: return UInt32(kVK_Space)
        case .peekHUD: return UInt32(kVK_ANSI_I)
        case .toggleDesktopIcons: return UInt32(kVK_ANSI_D)
        case .toggleInteractive: return UInt32(kVK_ANSI_K)
        }
    }

    public var modifiers: UInt32 {
        return UInt32(cmdKey | shiftKey)
    }

    public var defaultBinding: HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifiers: modifiers, isEnabled: true)
    }

    public var shortcutLabel: String {
        defaultBinding.displayString
    }

    public var title: String {
        switch self {
        case .nextArtwork: return "Next Artwork"
        case .previousArtwork: return "Previous Artwork"
        case .togglePause: return "Pause / Resume Rotation"
        case .peekHUD: return "Show Artwork Plaque HUD"
        case .toggleDesktopIcons: return "Toggle Hide Desktop Icons"
        case .toggleInteractive: return "Toggle Interactive Canvas"
        }
    }
}

/// Registers system-wide Carbon hotkeys without requiring macOS Accessibility permissions
@MainActor
public final class GlobalHotkeyManager {
    public static let shared = GlobalHotkeyManager()

    private static let defaultsKey = "customGlobalHotkeys"

    public var onAction: ((HotkeyAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isEnabled: Bool = false
    private var isRecordingSuspended: Bool = false
    private var customBindings: [UInt32: HotkeyBinding] = [:]

    private init() {
        loadCustomBindings()
    }

    public func binding(for action: HotkeyAction) -> HotkeyBinding {
        customBindings[action.rawValue] ?? action.defaultBinding
    }

    public func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        customBindings[action.rawValue] = binding
        saveCustomBindings()
        reloadBindings()
    }

    public func resetBindingsToDefaults() {
        customBindings.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        reloadBindings()
    }

    public func setRecordingSuspended(_ suspended: Bool) {
        guard isRecordingSuspended != suspended else { return }
        isRecordingSuspended = suspended
        if suspended {
            unregisterAll()
        } else if isEnabled {
            registerAll()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled == isEnabled { return }
        isEnabled = enabled
        if enabled && !isRecordingSuspended {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    private func reloadBindings() {
        unregisterAll()
        if isEnabled && !isRecordingSuspended {
            registerAll()
        }
    }

    private func loadCustomBindings() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else {
            return
        }
        var loaded: [UInt32: HotkeyBinding] = [:]
        for (key, value) in decoded {
            if let raw = UInt32(key) {
                loaded[raw] = value
            }
        }
        customBindings = loaded
    }

    private func saveCustomBindings() {
        var encodable: [String: HotkeyBinding] = [:]
        for (raw, binding) in customBindings {
            encodable[String(raw)] = binding
        }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func registerAll() {
        unregisterAll()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr, let action = HotkeyAction(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onAction?(action)
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        let signature: OSType = 0x444B5450 // 'DKTP'
        for action in HotkeyAction.allCases {
            let currentBinding = binding(for: action)
            guard currentBinding.isEnabled else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: action.rawValue)
            let regStatus = RegisterEventHotKey(
                currentBinding.keyCode,
                currentBinding.modifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if regStatus == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    public func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
