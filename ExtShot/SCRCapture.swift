import Foundation
import CoreGraphics
import AppKit
import os

class SCRCapture {
    private let logger = Logger(subsystem: "com.extshot.app", category: "screen-capture")
    
    // MARK: - Public Methods
    func checkScreenCapturePermission() async -> Bool {
        // 使用 CGWindowListCreateImage 检查权限
        let testImage = CGWindowListCreateImage(.null, .optionOnScreenOnly, kCGNullWindowID, [])
        let hasPermission = testImage != nil
        if hasPermission {
            logger.info("Screen capture permission granted")
        } else {
            logger.error("Screen capture permission check failed")
        }
        return hasPermission
    }
    
    func capture(_ rect: NSRect) async throws -> NSImage {
        logger.info("Starting capture for rect: \(rect.origin.x),\(rect.origin.y) \(rect.width)x\(rect.height)")
        
        // 确保捕获区域在屏幕范围内
        let mainScreen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = mainScreen.frame
        let scaleFactor = mainScreen.backingScaleFactor
        
        let safeRect = NSRect(
            x: max(0, min(rect.origin.x, screenFrame.width - rect.width)),
            y: max(0, min(rect.origin.y, screenFrame.height - rect.height)),
            width: min(rect.width, screenFrame.width),
            height: min(rect.height, screenFrame.height)
        )
        
        // 转换坐标系（Cocoa 坐标系 -> Core Graphics 坐标系）
        let flippedRect = CGRect(
            x: safeRect.origin.x,
            y: screenFrame.height - safeRect.origin.y - safeRect.height,
            width: safeRect.width,
            height: safeRect.height
        )
        
        // 创建截图
        guard let cgImage = CGWindowListCreateImage(
            flippedRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.shouldBeOpaque]
        ) else {
            logger.error("Failed to create screenshot")
            throw NSError(domain: "com.extshot.app", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法创建截图",
                NSLocalizedFailureReasonErrorKey: "请确保已授予屏幕录制权限"
            ])
        }
        
        // 创建 NSImage
        let size = NSSize(width: safeRect.width, height: safeRect.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        
        logger.info("Screenshot captured successfully")
        return nsImage
    }
}
