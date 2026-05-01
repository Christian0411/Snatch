import AppKit
import Carbon.HIToolbox
import os
import SnatchKit

/// Carbon-based global hotkey registration. Uses `RegisterEventHotKey`
/// (pre-routed; intercepts before the focused app sees the keypress)
/// rather than `NSEvent.addGlobalMonitorForEvents` (post-routed).
@MainActor
final class HotkeyRegistrar {
    private let handler: () -> Void
    private let escHandler: () -> Void
    private var globalHotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static let globalHotKeyID: UInt32 = 1
    private static let escHotKeyID: UInt32 = 2
    private static let signature: OSType = OSType(0x534E4348)  // 'SNCH'

    /// Static dispatch table — Carbon callbacks can't capture `self`.
    private static var routes: [UInt32: () -> Void] = [:]

    init(onGlobal: @escaping () -> Void, onEsc: @escaping () -> Void) {
        self.handler = onGlobal
        self.escHandler = onEsc
    }

    /// Convenience init for the original single-callback shape used in
    /// AppDelegate; routes to onGlobal only. Esc is unused unless
    /// `registerEsc()` is called separately.
    convenience init(handler: @escaping () -> Void) {
        self.init(onGlobal: handler, onEsc: {})
    }

    func registerGlobal() {
        installEventHandlerOnce()
        Self.routes[Self.globalHotKeyID] = handler

        // ⇧⌘6 — keyCode 22 ('6' on US layout) + cmd + shift
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.globalHotKeyID)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_6),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            Log.system.error("RegisterEventHotKey ⇧⌘6 failed: \(status, privacy: .public)")
            return
        }
        globalHotKeyRef = ref
    }

    func registerEsc() {
        guard escHotKeyRef == nil else { return }
        installEventHandlerOnce()
        Self.routes[Self.escHotKeyID] = escHandler

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.escHotKeyID)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,                              // no modifiers
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            Log.system.error("RegisterEventHotKey Esc failed: \(status, privacy: .public)")
            return
        }
        escHotKeyRef = ref
    }

    func unregisterEsc() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
        Self.routes[Self.escHotKeyID] = nil
    }

    func unregisterAll() {
        if let ref = globalHotKeyRef {
            UnregisterEventHotKey(ref)
            globalHotKeyRef = nil
        }
        unregisterEsc()
        Self.routes.removeAll()
    }

    private func installEventHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, _ in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if err == noErr {
                let id = hkID.id
                DispatchQueue.main.async {
                    HotkeyRegistrar.routes[id]?()
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &eventHandler)
    }
}
