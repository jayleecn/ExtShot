import AppKit
import os

extension NSNotification.Name {
    static let takeScreenshot = NSNotification.Name("com.extshot.app.takeScreenshot")
}

class ScreenshotPanel: NSPanel {
    private let logger = Logger(subsystem: "com.extshot.app", category: "screenshot-panel")
    private var overlayView: OverlayView!
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
        self.makeFirstResponder(overlayView)
        
        logger.info("初始化截图面板")
    }
    
    private func handleScreenshot(_ rect: NSRect) {
        logger.info("处理截图请求")
        
        // 先发送通知
        NotificationCenter.default.post(
            name: .takeScreenshot,
            object: nil,
            userInfo: ["rect": rect]
        )
        
        // 确保在主线程关闭面板
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            logger.info("关闭截图面板")
            self.orderOut(nil)  // 立即隐藏面板
            self.close()
        }
    }
    
    private func handleEscape() {
        logger.info("处理ESC退出")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.orderOut(nil)  // 立即隐藏面板
            self.close()
        }
    }
    
    override func close() {
        logger.info("面板close被调用")
        orderOut(nil)  // 确保面板被隐藏
        super.close()
        onClose?()
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
        
        if NSPointInRect(point, selectionRect) {
            isDragging = true
            dragStart = NSPoint(
                x: point.x - selectionRect.minX,
                y: point.y - selectionRect.minY
            )
            
            // 检查是否是双击
            let clickTime = event.timestamp
            if clickTime - lastClickTime < 0.5 {
                logger.info("检测到双击事件")
                isDragging = false
                onDoubleClick?(selectionRect)
                return
            }
            lastClickTime = clickTime
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }
        
        var newOrigin = NSPoint(
            x: point.x - start.x,
            y: point.y - start.y
        )
        
        // 确保选择框不会超出视图边界
        newOrigin.x = max(0, min(newOrigin.x, bounds.width - selectionRect.width))
        newOrigin.y = max(0, min(newOrigin.y, bounds.height - selectionRect.height))
        
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
