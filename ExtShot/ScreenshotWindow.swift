import AppKit
import os

extension NSNotification.Name {
    static let takeScreenshot = NSNotification.Name("com.extshot.app.takeScreenshot")
}

class ScreenshotPanel: NSPanel {
    private let logger = Logger(subsystem: "com.extshot.app", category: "screenshot-panel")
    private var overlayView: OverlayView!
    private var isReady = false
    var onClose: (() -> Void)?
    
    init(size: CGSize) {
        // 获取主屏幕
        let screen = NSScreen.main ?? NSScreen.screens[0]
        
        // 创建全屏面板
        super.init(
            contentRect: screen.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // 设置面板属性
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false
        
        // 创建覆盖视图
        overlayView = OverlayView(frame: screen.frame, presetSize: size)
        overlayView.onDoubleClick = { [weak self] rect in
            self?.handleScreenshot(rect)
        }
        overlayView.onEscape = { [weak self] in
            self?.handleEscape()
        }
        
        self.contentView = overlayView
        
        // 确保窗口总是能接收键盘事件
        self.makeKey()
        self.makeFirstResponder(overlayView)
        self.becomeKey()
        self.becomeMain()
        
        logger.info("初始化截图面板")
        
        // 延迟标记窗口准备就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isReady = true
            // 确保窗口保持焦点
            self?.makeKey()
            self?.makeFirstResponder(self?.overlayView)
        }
    }
    
    private func handleScreenshot(_ rect: NSRect) {
        logger.info("处理截图请求")
        
        // 如果窗口还没准备好，等待一会儿
        if !isReady {
            logger.info("窗口未就绪，等待200ms")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.handleScreenshot(rect)
            }
            return
        }
        
        // 记录原始坐标
        logger.debug("原始选择框坐标: origin=(\(rect.origin.x), \(rect.origin.y)), size=(\(rect.width), \(rect.height))")
        
        // 将视图坐标转换为窗口坐标
        let windowRect = overlayView.convert(rect, to: nil)
        logger.debug("转换到窗口坐标: origin=(\(windowRect.origin.x), \(windowRect.origin.y)), size=(\(windowRect.width), \(windowRect.height))")
        
        // 将窗口坐标转换为屏幕坐标
        let screenRect = convertToScreen(windowRect)
        logger.debug("转换到屏幕坐标: origin=(\(screenRect.origin.x), \(screenRect.origin.y)), size=(\(screenRect.width), \(screenRect.height))")
        
        // 发送截图通知
        NotificationCenter.default.post(
            name: .takeScreenshot,
            object: nil,
            userInfo: ["rect": screenRect]
        )
        
        // 直接调用 ESC 处理逻辑
        handleEscape()
    }
    
    private func handleEscape() {
        logger.info("处理ESC退出")
        self.orderOut(nil)  // 立即隐藏面板
        self.close()
    }
    
    override func close() {
        logger.info("面板close被调用")
        super.close()
        self.orderOut(nil)  // 确保窗口被隐藏
        self.overlayView = nil  // 清理引用
        onClose?()  // 通知关闭事件
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class OverlayView: NSView {
    private var selectionRect: NSRect
    private var isDragging = false
    private var dragStart: NSPoint?
    private var lastClickTime: TimeInterval = 0
    private let logger = Logger(subsystem: "com.extshot.app", category: "overlay-view")
    
    var onDoubleClick: ((NSRect) -> Void)?
    var onEscape: (() -> Void)?
    
    init(frame: NSRect, presetSize: NSSize) {
        // 计算初始选择框位置（居中）
        self.selectionRect = NSRect(
            x: (frame.width - presetSize.width) / 2,
            y: (frame.height - presetSize.height) / 2,
            width: presetSize.width,
            height: presetSize.height
        )
        
        super.init(frame: frame)
        
        // 添加事件监听
        let trackingArea = NSTrackingArea(
            rect: frame,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        
        // 添加提示文本
        addTipLabel()
        
        // 确保视图可以接收事件
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 允许视图成为第一响应者
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 检查是否是双击
        let clickTime = event.timestamp
        if clickTime - lastClickTime < 0.5 {
            logger.info("检测到双击事件")
            isDragging = false
            dragStart = nil
            onDoubleClick?(selectionRect)
            return
        }
        lastClickTime = clickTime
        
        // 检查是否点击在选择框内
        if NSPointInRect(point, selectionRect) {
            isDragging = true
            dragStart = NSPoint(
                x: point.x - selectionRect.minX,
                y: point.y - selectionRect.minY
            )
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = dragStart else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        
        // 计算新位置
        var newOrigin = NSPoint(
            x: point.x - start.x,
            y: point.y - start.y
        )
        
        // 确保选择框不会超出视图边界
        newOrigin.x = max(0, min(newOrigin.x, bounds.width - selectionRect.width))
        newOrigin.y = max(0, min(newOrigin.y, bounds.height - selectionRect.height))
        
        // 更新选择框位置并重绘
        selectionRect.origin = newOrigin
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        dragStart = nil
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 绘制半透明背景
        NSColor(white: 0, alpha: 0.3).setFill()
        let path = NSBezierPath(rect: bounds)
        let selectionPath = NSBezierPath(rect: selectionRect)
        path.append(selectionPath)
        path.windingRule = .evenOdd
        path.fill()
        
        // 绘制选择框边框
        NSColor.white.setStroke()
        NSBezierPath(rect: selectionRect).stroke()
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            logger.info("用户按下 ESC 键")
            onEscape?()
        }
    }
    
    private func addTipLabel() {
        let tip = NSTextField(frame: NSRect(x: 0, y: frame.height - 50, width: frame.width, height: 30))
        tip.stringValue = "Drag to move • Double-click to capture • Press ESC to exit"
        tip.alignment = .center
        tip.isBezeled = false
        tip.drawsBackground = false
        tip.isEditable = false
        tip.isSelectable = false
        tip.textColor = .white
        addSubview(tip)
    }
}
