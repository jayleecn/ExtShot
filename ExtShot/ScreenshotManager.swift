import Cocoa
import ScreenCaptureKit
import CoreImage
import CoreMedia
import os

@MainActor
class ScreenshotManager: NSObject {
    @MainActor static let shared = ScreenshotManager()
    private var isCapturing = false
    private let logger = Logger(subsystem: "com.extshot.app", category: "screenshot")
    private var activeDelegate: CaptureDelegate?
    
    private override init() {
        super.init()
    }
    
    func takeScreenshot(size: CGSize) async {
        guard !isCapturing else { return }
        
        do {
            isCapturing = true
            defer { isCapturing = false }
            
            // Get main display
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                print("No display found")
                return
            }
            
            // 创建截图配置
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.showsCursor = false
            
            // 创建过滤器
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // 创建流
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // Create a single frame collector
            let frameCollector = SingleFrameCollector()
            
            // Add stream output
            try await addStreamOutput(frameCollector, to: stream)
            
            // Start capture
            try await stream.startCapture()
            
            // Wait for the frame
            if let cgImage = try await frameCollector.capture() {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                if let resized = nsImage.resize(to: size) {
                    await save(image: resized)
                }
            }
            
            // Stop capture
            try await stream.stopCapture()
        } catch {
            print("Error taking screenshot: \(error)")
        }
    }
    
    func takeScreenshot(rect: NSRect) async throws {
        guard !isCapturing else {
            logger.warning("已有截图任务在进行中")
            return
        }
        
        logger.info("开始新的截图任务: x=\(rect.origin.x, privacy: .public), y=\(rect.origin.y, privacy: .public), width=\(rect.size.width, privacy: .public), height=\(rect.size.height, privacy: .public)")
        isCapturing = true
        defer { isCapturing = false }
        
        logger.info("获取屏幕内容")
        let content = try await SCShareableContent.current
        
        guard let display = content.displays.first else {
            logger.error("未找到显示器")
            throw NSError(domain: "com.extshot.app", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        logger.info("找到显示器: width=\(display.width, privacy: .public), height=\(display.height, privacy: .public)")
        
        // 创建截图配置
        logger.info("配置截图参数")
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false
        
        // 创建过滤器
        logger.info("创建内容过滤器")
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // 创建流
        logger.info("创建截图流")
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        // 等待截图完成
        logger.info("等待截图完成")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = CaptureDelegate(stream: stream, continuation: continuation, rect: rect)
            self.activeDelegate = delegate
            
            // 使用同步方法添加输出
            do {
                logger.info("添加流输出")
                try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .main)
                Task {
                    do {
                        logger.info("开始捕获")
                        try await stream.startCapture()
                    } catch {
                        logger.error("开始捕获失败: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                logger.error("添加流输出失败: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func addStreamOutput(_ frameCollector: SingleFrameCollector, to stream: SCStream) async throws {
        try stream.addStreamOutput(frameCollector, type: .screen, sampleHandlerQueue: .main)
    }
    
    private func save(image: NSImage) async {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        
        let fileURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExtShot_\(timestamp).png")
        
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: fileURL)
            } catch {
                print("Error saving screenshot: \(error)")
            }
        }
    }
}

extension ScreenshotManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        
        Task { @MainActor in
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext()
            
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let screenshot = NSImage(cgImage: cgImage, size: ciImage.extent.size)
            
            // 保存截图
            if let tiffData = screenshot.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = dateFormatter.string(from: Date())
                
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let fileURL = downloadsURL.appendingPathComponent("ExtShot_\(timestamp).png")
                
                do {
                    try pngData.write(to: fileURL)
                    print("Screenshot saved to: \(fileURL.path)")
                    
                    // 播放截图音效
                    NSSound(named: "Pop")?.play()
                } catch {
                    print("Failed to save screenshot: \(error.localizedDescription)")
                }
            }
        }
    }
}

private class SingleFrameCollector: NSObject, SCStreamOutput {
    private var continuation: CheckedContinuation<CGImage?, Error>?
    
    func capture() async throws -> CGImage? {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<CGImage?, Error>) in
            guard let self = self else {
                continuation.resume(throwing: NSError(domain: "ExtShot", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Self is deallocated"]))
                return
            }
            guard self.continuation == nil else {
                continuation.resume(throwing: NSError(domain: "ExtShot", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Capture already in progress"]))
                return
            }
            self.continuation = continuation
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let continuation = continuation,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        
        self.continuation = nil
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            continuation.resume(returning: cgImage)
        } else {
            continuation.resume(throwing: NSError(domain: "ExtShot", code: -2, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"]))
        }
    }
}

private class CaptureDelegate: NSObject, SCStreamOutput {
    private let stream: SCStream
    private let continuation: CheckedContinuation<Void, Error>
    private let captureRect: NSRect
    private var hasProcessedFrame = false
    private let logger = Logger(subsystem: "com.extshot.app", category: "screenshot")
    
    init(stream: SCStream, continuation: CheckedContinuation<Void, Error>, rect: NSRect) {
        self.stream = stream
        self.continuation = continuation
        self.captureRect = rect
        super.init()
    }
    
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !hasProcessedFrame,
              type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        
        hasProcessedFrame = true
        
        Task { @MainActor in
            do {
                logger.info("开始处理截图数据")
                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                let context = CIContext()
                
                logger.info("裁剪图像: x=\(self.captureRect.origin.x, privacy: .public), y=\(self.captureRect.origin.y, privacy: .public), width=\(self.captureRect.size.width, privacy: .public), height=\(self.captureRect.size.height, privacy: .public)")
                let croppedImage = ciImage.cropped(to: captureRect)
                
                guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else {
                    logger.error("创建CGImage失败")
                    throw NSError(domain: "com.extshot.app", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image"])
                }
                
                logger.info("转换为NSImage")
                let screenshot = NSImage(cgImage: cgImage, size: captureRect.size)
                
                // 保存截图
                logger.info("准备保存PNG数据")
                guard let tiffData = screenshot.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                    logger.error("创建PNG数据失败")
                    throw NSError(domain: "com.extshot.app", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = dateFormatter.string(from: Date())
                
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let fileURL = downloadsURL.appendingPathComponent("ExtShot_\(timestamp).png")
                
                logger.info("保存文件到: \(fileURL.path, privacy: .public)")
                try pngData.write(to: fileURL)
                NSSound(named: "Pop")?.play()
                
                logger.info("停止捕获")
                try await stream.stopCapture()
                logger.info("截图完成")
                continuation.resume()
                
            } catch {
                logger.error("处理截图失败: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation.resume(throwing: error)
    }
}

extension NSImage {
    func resize(to newSize: CGSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize))
        
        return newImage
    }
}
