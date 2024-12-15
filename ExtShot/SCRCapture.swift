import Cocoa
import ScreenCaptureKit
import CoreImage
import os

@MainActor
class SCRCapture: NSObject {
    private let logger = Logger(subsystem: "com.extshot.app", category: "screen-capture")
    private var stream: SCStream?
    private var latestFrame: CGImage?
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var rect: NSRect?
    private var config: SCStreamConfiguration?
    private var mainScreen: NSScreen?

    func capture(_ rect: NSRect) async throws -> NSImage {
        logger.info("Starting capture for rect: \(rect.origin.x),\(rect.origin.y) \(rect.width)x\(rect.height)")
        
        // 获取屏幕内容
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            logger.error("未找到显示器")
            throw NSError(domain: "com.extshot.app", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No display found"
            ])
        }
        
        // 创建过滤器，包含所有窗口
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // 创建配置
        mainScreen = NSScreen.main ?? NSScreen.screens[0]
        let scaleFactor = mainScreen?.backingScaleFactor ?? 1.0
        
        config = SCStreamConfiguration()
        config?.width = Int(CGFloat(display.width) * scaleFactor)
        config?.height = Int(CGFloat(display.height) * scaleFactor)
        config?.showsCursor = false
        config?.pixelFormat = kCVPixelFormatType_32BGRA
        config?.queueDepth = 1
        config?.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config?.scalesToFit = false
        
        // 创建并启动流
        if let config = config {
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await stream?.startCapture()
        }
        
        self.rect = rect
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.continuation = continuation
            
            // 5秒后如果还没有收到帧，就超时
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let continuation = self?.continuation {
                    self?.continuation = nil
                    continuation.resume(throwing: NSError(domain: "com.extshot.app", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Screenshot capture timeout"
                    ]))
                }
            }
        }
    }
}

extension SCRCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            logger.error("Stream stopped with error: \(error.localizedDescription)")
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension SCRCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        Task { @MainActor in
            guard let continuation = continuation,
                  let imageBuffer = sampleBuffer.imageBuffer,
                  let rect = rect,
                  let config = config,
                  let mainScreen = mainScreen else {
                return
            }
            
            // 停止捕获
            try? await stream.stopCapture()
            self.continuation = nil
            
            // 创建 CIImage
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext(options: [
                .useSoftwareRenderer: false,
                .workingColorSpace: mainScreen.colorSpace?.cgColorSpace as Any,
                .outputColorSpace: mainScreen.colorSpace?.cgColorSpace as Any
            ])
            
            // 计算裁剪区域
            let scaleFactor = mainScreen.backingScaleFactor
            
            // 获取主屏幕的frame
            let screenFrame = mainScreen.frame
            
            // 转换坐标系
            // 1. 考虑显示器的位置偏移
            let globalX = rect.origin.x - screenFrame.origin.x
            
            // 2. Y轴转换：从左上角原点转换到左上角原点（不需要翻转）
            let globalY = rect.origin.y - screenFrame.origin.y
            
            // 调试信息
            logger.debug("""
                坐标转换详情:
                输入坐标: origin=(\(rect.origin.x), \(rect.origin.y)), size=(\(rect.width), \(rect.height))
                屏幕信息: origin=(\(screenFrame.origin.x), \(screenFrame.origin.y)), size=(\(screenFrame.width), \(screenFrame.height))
                转换结果: globalX=\(globalX), globalY=\(globalY)
                缩放因子: \(scaleFactor)
            """)
            
            // 3. 应用缩放因子并取整
            let cropRect = CGRect(
                x: floor(globalX * scaleFactor),
                y: floor(globalY * scaleFactor),
                width: floor(rect.width * scaleFactor),
                height: floor(rect.height * scaleFactor)
            )
            
            // 裁剪图像
            let croppedImage = ciImage.cropped(to: cropRect)
            
            guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent, format: .BGRA8, colorSpace: mainScreen.colorSpace?.cgColorSpace) else {
                continuation.resume(throwing: NSError(domain: "com.extshot.app", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create screenshot"
                ]))
                return
            }
            
            // 如果是大图(1280x800)，需要缩放处理
            if rect.width == 1280 && rect.height == 800 {
                // 创建缩放后的尺寸
                let targetSize = CGSize(width: 1280, height: 800)
                
                // 创建位图上下文
                let bitmapRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(targetSize.width),
                    pixelsHigh: Int(targetSize.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
                
                // 设置图形上下文
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep!)
                
                // 绘制缩放后的图像
                let nsImage = NSImage(cgImage: cgImage, size: rect.size)
                nsImage.draw(in: NSRect(origin: .zero, size: targetSize))
                
                // 恢复图形上下文
                NSGraphicsContext.restoreGraphicsState()
                
                // 创建新的图像
                let resizedImage = NSImage(size: targetSize)
                resizedImage.addRepresentation(bitmapRep!)
                
                // 保存缩放后的图像
                continuation.resume(returning: resizedImage)
            } else {
                // 其他尺寸直接保存
                let nsImage = NSImage(cgImage: cgImage, size: rect.size)
                continuation.resume(returning: nsImage)
            }
        }
    }
}
