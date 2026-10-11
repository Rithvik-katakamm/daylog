import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey via Carbon's RegisterEventHotKey. Old API, but it's still the
/// one that works without asking for Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32

    /// Default: ⌥L ("L" for log). Each hotkey needs a distinct `id`.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_L), modifiers: UInt32 = UInt32(optionKey), id: UInt32 = 1,
         action: @escaping () -> Void) {
        self.action = action
        self.id = id
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let hk = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every hotkey handler sees every hotkey press: only act on our own id, and
            // pass the rest along so the other handlers get them.
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == hk.id else { return OSStatus(eventNotHandledErr) }
            print("hotkey: pressed id=\(hk.id)"); fflush(stdout)
            DispatchQueue.main.async { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let hotKeyID = EventHotKeyID(signature: OSType(0x44594C47), id: id)  // 'DYLG'
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        // Non-zero means another app already owns this combination (or the handler failed).
        print("hotkey \(id): handler=\(installed) register=\(registered)"); fflush(stdout)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
