import SwiftUI
import Carbon
import os

@main
struct ExtShotApp: App {
    // 使用 StateObject 确保 AppDelegate 在整个应用生命周期内存在
    @StateObject private var appDelegate = AppDelegateObject()
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// 创建一个 ObservableObject 来管理 AppDelegate
@MainActor
class AppDelegateObject: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var eventHandlers: [EventHotKeyRef] = []
    private var hotKeyCallbacks = HotKeyCallbacks.shared
    private let logger = Logger(subsystem: "com.extshot.app", category: "app")
    private var screenshotPanel: ScreenshotPanel?
    private var isCapturing = false
    
    // 保持对自身的强引用
    private static var shared: AppDelegateObject?
    
    override init() {
        super.init()
        AppDelegateObject.shared = self
        
        // 清理可能存在的窗口
        cleanupExistingWindows()
        
        // 注册快捷键
        registerHotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey | shiftKey), id: UInt32(1)) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.showScreenshotPanel(size: CGSize(width: 1280, height: 800))
            }
        }
        
        registerHotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey | shiftKey), id: UInt32(2)) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.showScreenshotPanel(size: CGSize(width: 640, height: 400))
            }
        }
        
        // 注册截图通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshotNotification(_:)),
            name: .takeScreenshot,
            object: nil
        )
    }
    
    private func cleanupExistingWindows() {
        // 关闭所有可能存在的窗口
        NSApp.windows.forEach { window in
            if window is ScreenshotPanel {
                window.close()
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 应用启动时清理窗口
        cleanupExistingWindows()
        
        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Take Screenshot")
        }
        
        // 创建菜单
        let menu = NSMenu()
        
        // 添加预设尺寸选项
        let largeItem = NSMenuItem(title: "Large (1280 x 800)", action: #selector(takeLargeScreenshot), keyEquivalent: "1")
        largeItem.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(largeItem)
        
        let smallItem = NSMenuItem(title: "Small (640 x 400)", action: #selector(takeSmallScreenshot), keyEquivalent: "2")
        smallItem.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(smallItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        logger.info("开始注册热键")
        
        // 在应用启动时请求屏幕录制权限
        Task {
            let capture = SCRCapture()
            _ = await capture.checkScreenCapturePermission()
        }
    }
    
    private func showScreenshotPanel(size: CGSize) {
        // 如果正在截图，忽略新的请求
        guard !isCapturing else {
            logger.info("正在截图中，忽略新的截图请求")
            return
        }
        
        logger.info("准备显示新的截图面板")
        
        // 清理所有现有窗口
        cleanupExistingWindows()
        
        // 创建新面板
        isCapturing = true
        let panel = ScreenshotPanel(size: size)
        panel.onClose = { [weak self] in
            guard let self = self else { return }
            self.logger.info("面板关闭回调被触发")
            self.isCapturing = false
            self.screenshotPanel = nil
        }
        
        panel.makeKeyAndOrderFront(nil)
        screenshotPanel = panel
        
        logger.info("显示截图面板，预设尺寸: \(size.width)x\(size.height)")
    }
    
    @objc private func handleScreenshotNotification(_ notification: Notification) {
        guard let rect = notification.userInfo?["rect"] as? NSRect else {
            logger.error("无法从通知中获取截图区域")
            return
        }
        
        logger.info("收到截图通知，准备关闭面板")
        
        // 先关闭面板和重置状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let panel = self.screenshotPanel {
                self.logger.info("正在关闭面板")
                panel.orderOut(nil)
                panel.close()
                self.screenshotPanel = nil
                self.isCapturing = false
            }
            
            // 开始截图
            Task {
                do {
                    let capture = SCRCapture()
                    let image = try await capture.capture(rect)
                    self.handleCapturedImage(image)
                } catch {
                    self.logger.error("截图失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func takeLargeScreenshot() {
        showScreenshotPanel(size: CGSize(width: 1280, height: 800))
    }
    
    @objc private func takeSmallScreenshot() {
        showScreenshotPanel(size: CGSize(width: 640, height: 400))
    }
    
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, callback: @escaping () -> Void) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        
        hotKeyID.signature = OSType(id)
        hotKeyID.id = id
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let hotKeyRef = hotKeyRef {
            eventHandlers.append(hotKeyRef)
            hotKeyCallbacks.callbacks[id] = callback
        } else {
            logger.error("热键注册失败: status=\(status, privacy: .public)")
        }
    }
    
    private func handleCapturedImage(_ image: NSImage) {
        logger.info("截图完成")
        
        // 创建文件名
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        var baseFilename = "screenshot-\(Int(1280))x\(Int(800))-\(timestamp)"
        
        // 获取下载目录路径
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            var fileURL = downloadsURL.appendingPathComponent(baseFilename).appendingPathExtension("png")
            let fileManager = FileManager.default
            
            // 如果文件已存在，添加序号
            var counter = 1
            while fileManager.fileExists(atPath: fileURL.path) {
                baseFilename = "screenshot-\(Int(1280))x\(Int(800))-\(timestamp)-\(counter)"
                fileURL = downloadsURL.appendingPathComponent(baseFilename).appendingPathExtension("png")
                counter += 1
            }
            
            // 将图片保存为PNG，使用最高质量
            if let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData) {
                let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                    .compressionFactor: 1.0  // 最高质量
                ]
                if let pngData = bitmapImage.representation(using: .png, properties: properties) {
                    do {
                        try pngData.write(to: fileURL)
                        logger.info("截图已保存: \(fileURL.path)")
                        
                        // 在访达中显示文件
                        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                    } catch {
                        logger.error("保存截图失败: \(error.localizedDescription)")
                        // 显示错误提示
                        let alert = NSAlert()
                        alert.messageText = "保存截图失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                    }
                } else {
                    logger.error("创建PNG数据失败")
                }
            } else {
                logger.error("创建位图表示失败")
            }
        }
    }
    
    deinit {
        logger.info("AppDelegate 被释放")
        // 注销热键
        for handler in eventHandlers {
            UnregisterEventHotKey(handler)
        }
        
        Task { @MainActor in
            // 清理共享实例
            AppDelegateObject.shared = nil
        }
    }
}

// 快捷键 ID 枚举
enum HotKeyIDs: UInt32 {
    case largeScreenshot = 1
    case smallScreenshot = 2
}
