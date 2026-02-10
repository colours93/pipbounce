import Cocoa

func installHotkey() {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = UInt32(event.flags.rawValue >> 16) & 0xFFF
            if keyCode == settings.hotkeyCode && flags == settings.hotkeyFlags {
                settings.enabled.toggle()
                print(settings.enabled ? "Dodge enabled (hotkey)" : "Dodge paused (hotkey)")
                return nil
            }
            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    ) else {
        print("Failed to create hotkey tap")
        return
    }

    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("Hotkey registered")
}
