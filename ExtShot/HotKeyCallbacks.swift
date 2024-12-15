import Foundation
import Carbon

@MainActor
class HotKeyCallbacks {
    static let shared = HotKeyCallbacks()
    var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    
    private init() {
        installEventHandler()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        var handlerRef: EventHandlerRef?
        
        // 安装事件处理器
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if status == noErr {
                    if let callback = HotKeyCallbacks.shared.callbacks[hotKeyID.id] {
                        DispatchQueue.main.async {
                            callback()
                        }
                    }
                }
                
                return CallNextEventHandler(nextHandler, theEvent)
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        
        if status == noErr {
            eventHandler = handlerRef
        }
    }
    
    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
