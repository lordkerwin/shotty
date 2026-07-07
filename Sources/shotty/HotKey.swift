import Foundation
import Carbon.HIToolbox

// MARK: - Global hotkey (Carbon — works system-wide, no Accessibility permission)

final class HotKey {
    private var ref: EventHotKeyRef?
    private let handler: () -> Void
    private let id: UInt32

    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        id = HotKey.nextID; HotKey.nextID += 1
        HotKey.instances[id] = self
        HotKey.installHandlerIfNeeded()
        let hkID = EventHotKeyID(signature: OSType(0x53485459), id: id) // 'SHTY'
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKey.instances[hkID.id]?.handler()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
