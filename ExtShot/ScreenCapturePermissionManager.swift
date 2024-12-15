import Foundation
import ScreenCaptureKit
import os

@MainActor
class ScreenCapturePermissionManager: NSObject {
    static let shared = ScreenCapturePermissionManager()
    private let logger = Logger(subsystem: "com.extshot.app", category: "permission")
    
    private override init() {
        super.init()
    }
    
    func checkAndRequestPermission() async -> Bool {
        do {
            // 尝试获取可共享内容，这会自动触发系统权限请求弹窗
            _ = try await SCShareableContent.current
            return true
        } catch {
            logger.warning("Screen capture permission denied: \(error.localizedDescription)")
            return false
        }
    }
}
