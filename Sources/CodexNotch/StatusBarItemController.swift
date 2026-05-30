import AppKit

// 管理右上角状态栏区域里的胶囊浮窗，避免系统状态栏项被隐藏或排到不可见区域。
final class StatusBarItemController: NSObject {
    private let window: NSWindow
    private let pillView: StatusPillView
    private let onActivate: (CGRect?) -> Void
    private var state: NotchState
    private var blinkTimer: Timer?
    private var carouselTimer: Timer?
    private var isBlinkingOn = true
    private var carouselIndex = 0
    private let pillSize = CGSize(width: 112, height: 28)

    init(initialState: NotchState, onActivate: @escaping (CGRect?) -> Void) {
        self.state = initialState
        self.onActivate = onActivate
        self.pillView = StatusPillView(frame: CGRect(origin: .zero, size: pillSize))
        self.window = NSWindow(contentRect: CGRect(origin: .zero, size: pillSize), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        configureWindow()
        configurePillView()
        configureCarouselTimer()
        update(state: initialState)
        window.orderFrontRegardless()
    }

    deinit {
        blinkTimer?.invalidate()
        carouselTimer?.invalidate()
    }

    // 刷新胶囊展示，并根据当前颜色启停闪烁计时器。
    func update(state: NotchState) {
        self.state = state
        normalizeCarouselIndex()
        configureBlinkTimer()
        updatePillView()
        positionWindow()
    }

    // 胶囊浮窗保持无阴影透明背景，由内部 view 画出截图里的深色胶囊。
    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = pillView
        window.ignoresMouseEvents = false
    }

    // 点击胶囊时展开完整会话面板。
    private func configurePillView() {
        pillView.target = self
        pillView.action = #selector(handleClick)
    }

    // 多个红黄灯会话时轮播 tooltip 目标，胶囊文字保持短小不挤占菜单栏。
    private func configureCarouselTimer() {
        carouselTimer?.invalidate()
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.carouselSessions.count > 1 else { return }
            self.carouselIndex = (self.carouselIndex + 1) % self.carouselSessions.count
            self.updatePillView()
        }
    }

    // 红灯和黄灯闪烁，绿灯保持常亮。
    private func configureBlinkTimer() {
        guard currentStatus != .green else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            isBlinkingOn = true
            return
        }
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.isBlinkingOn.toggle()
            self.updatePillView()
        }
    }

    // 按状态同步胶囊圆点、短标题和悬浮提示。
    private func updatePillView() {
        pillView.status = currentStatus
        pillView.title = displayText
        pillView.isBlinkingOn = isBlinkingOn
        pillView.toolTip = tooltipText
    }

    @objc private func handleClick() {
        onActivate(window.frame)
    }

    // 优先贴在硬件刘海左侧的空白状态栏区域，避免遮住右侧系统图标。
    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let origin = statusPillOrigin(on: screen)
        window.setFrame(CGRect(origin: origin, size: pillSize), display: true)
        window.orderFrontRegardless()
    }

    private func statusPillOrigin(on screen: NSScreen) -> CGPoint {
        let y = screen.frame.maxY - pillSize.height - 2
        if let leftArea = screen.auxiliaryTopLeftArea, !leftArea.isEmpty, leftArea.width >= pillSize.width + 16 {
            return CGPoint(x: leftArea.maxX - pillSize.width - 10, y: y)
        }
        let visibleFrame = screen.visibleFrame
        return CGPoint(x: visibleFrame.maxX - pillSize.width - 180, y: y)
    }

    private var carouselSessions: [CodexSession] {
        let activeSessions = state.sessions.filter { $0.status != .green }
        return activeSessions.isEmpty ? Array(state.sessions.prefix(1)) : activeSessions
    }

    private var currentSession: CodexSession? {
        guard !carouselSessions.isEmpty else { return nil }
        return carouselSessions[carouselIndex % carouselSessions.count]
    }

    private var currentStatus: SessionStatus {
        currentSession?.status ?? state.aggregateStatus
    }

    private var progressText: String {
        let total = state.sessions.count
        guard total > 0 else { return "0/0" }
        let completed = state.sessions.filter { $0.status == .green }.count
        return "\(completed)/\(total)"
    }

    private var displayText: String {
        switch currentStatus {
        case .red:
            return currentSession?.attention == .waitingInput ? "待输入" : "异常"
        case .yellow:
            return "运行中"
        case .green:
            return "完成"
        }
    }

    private var tooltipText: String {
        guard let currentSession else { return state.errorMessage == nil ? "Codex：暂无会话" : "Codex：读取错误" }
        return "\(statusText(for: currentSession)) · \(currentSession.displayTitle) · \(currentSession.activityText) · \(progressText)"
    }

    private func normalizeCarouselIndex() {
        let total = carouselSessions.count
        guard total > 0 else {
            carouselIndex = 0
            return
        }
        carouselIndex = carouselIndex % total
    }

    private func statusText(for session: CodexSession) -> String {
        if let attention = session.attention { return attention.shortLabel }
        switch session.status {
        case .red:
            return "失败"
        case .yellow:
            return "运行中"
        case .green:
            return "完成"
        }
    }
}

// 自绘状态胶囊，左侧状态圆点，右侧短文案。
private final class StatusPillView: NSControl {
    var status: SessionStatus = .green { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var isBlinkingOn = true { didSet { needsDisplay = true } }

    // 点击胶囊时走 NSControl 的 target/action，保持和原状态栏入口行为一致。
    override func mouseDown(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        sendAction(action, to: target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.isHighlighted = false
            self?.needsDisplay = true
        }
    }

    // 胶囊绘制成截图里的深色圆角形态。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pillRect = bounds.insetBy(dx: 1.5, dy: 2)
        let background = isHighlighted ? NSColor(calibratedWhite: 0.05, alpha: 0.95) : NSColor(calibratedWhite: 0.07, alpha: 0.90)
        background.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: (pillRect.height - 1) / 2, yRadius: (pillRect.height - 1) / 2)
        border.lineWidth = 0.5
        border.stroke()
        drawStatusDot(in: pillRect)
        drawTitle(in: pillRect)
    }

    // 状态圆点只保留单层实心点，红黄状态按计时器闪烁。
    private func drawStatusDot(in pillRect: NSRect) {
        let dotRect = NSRect(x: pillRect.minX + 10, y: pillRect.midY - 6.5, width: 13, height: 13)
        let dotAlpha = status == .green || isBlinkingOn ? 1.0 : 0.30
        statusColor.withAlphaComponent(dotAlpha).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func drawTitle(in pillRect: NSRect) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.94)]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let textArea = NSRect(x: pillRect.minX + 30, y: pillRect.minY, width: pillRect.width - 39, height: pillRect.height)
        let textSize = attributedTitle.size()
        // 手动按胶囊中线绘制文字，避免 AppKit 段落 rect 的默认基线看起来偏上。
        let drawPoint = NSPoint(x: textArea.midX - textSize.width / 2, y: pillRect.midY - textSize.height / 2)
        attributedTitle.draw(at: drawPoint)
    }

    private var statusColor: NSColor {
        switch status {
        case .red:
            return NSColor(red: 1.0, green: 0.25, blue: 0.22, alpha: 1.0)
        case .yellow:
            return NSColor(red: 0.90, green: 0.96, blue: 0.24, alpha: 1.0)
        case .green:
            return NSColor(red: 0.25, green: 0.86, blue: 0.42, alpha: 1.0)
        }
    }
}
