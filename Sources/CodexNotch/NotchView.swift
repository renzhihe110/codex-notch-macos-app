import SwiftUI

// 驱动刘海视图的轻量状态，便于 AppKit 窗口控制器同步展开尺寸。
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState
    @Published var isExpanded: Bool
    @Published var jumpError: String?
    @Published var collapsedHeight: CGFloat
    @Published var selectedSessionIndex: Int

    init(state: NotchState, isExpanded: Bool = false, collapsedHeight: CGFloat = NotchWindowMetrics.defaultCollapsedHeight) {
        self.state = state
        self.isExpanded = isExpanded
        self.collapsedHeight = collapsedHeight
        self.selectedSessionIndex = 0
    }
}

// 展示桌面顶部刘海和展开后的多会话列表。
struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    let onSelectSession: (CodexSession) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onHoverChanged: (Bool) -> Void
    @State private var collapsedCarouselIndex = 0
    // 列表高度贴合 320pt 展开窗口，避免底部出现大块空白。
    private let expandedListHeight: CGFloat = 254
    // 展开态把分割线前的留白并入首行区域，确保首行内容按整行视觉中线居中。
    private let expandedHeaderBottomInset: CGFloat = 8
    // 收起态轮播红黄灯会话，避免多个任务时只看到最新一条。
    private let collapsedCarouselTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            notchHeader
            if model.isExpanded {
                expandedList
            }
        }
        .padding(.horizontal, model.isExpanded ? 12 : 0)
        .padding(.bottom, model.isExpanded ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(notchBackground.fill(Color.black.opacity(0.94)))
        .overlay(notchBackground.stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.04), lineWidth: 1))
        .foregroundStyle(.white)
        // 根视图使用矩形命中区域，保证悬停进入刘海边缘时也能触发展开。
        .contentShape(Rectangle())
        .contextMenu {
            // 右键菜单提供无菜单栏场景下的设置和退出入口。
            Button("设置...") {
                onOpenSettings()
            }
            Divider()
            Button("退出 Codex Notch") {
                onQuit()
            }
        }
        // SwiftUI 直接监听当前视图悬停，避免 AppKit tracking area 被托管视图命中测试影响。
        .onHover { isHovered in
            onHoverChanged(isHovered)
        }
        .onReceive(collapsedCarouselTimer) { _ in
            advanceCollapsedCarousel()
        }
        .onChange(of: model.state.sessions) { _ in
            normalizeCollapsedCarouselIndex()
        }
    }

    // 展开态也保持方形顶部，避免面板离开状态栏刘海的视觉形态。
    private var notchBackground: NotchBackgroundShape {
        NotchBackgroundShape(topRadius: 0, bottomRadius: model.isExpanded ? 18 : 12)
    }

    // 顶部区域在收起和展开时都显示当前 thread 摘要。
    private var notchHeader: some View {
        Group {
            if model.isExpanded {
                expandedHeader
            } else {
                collapsedHeader
            }
        }
        .frame(height: notchHeaderHeight)
    }

    // 收起态沿用状态栏高度，展开态首行包含下方留白以匹配分割线前的真实行高。
    private var notchHeaderHeight: CGFloat {
        model.isExpanded ? model.collapsedHeight + expandedHeaderBottomInset : model.collapsedHeight
    }

    // 收起态显示状态点、最新对话短句和完成进度，保持在状态栏高度内。
    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 7) {
            let currentSession = collapsedDisplaySession
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 10)
            Text(collapsedTitle(for: currentSession))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 16, alignment: .center)
                .id(currentSession?.id ?? "empty")
            Text(collapsedProgressText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .monospacedDigit()
                .frame(height: 14, alignment: .center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    // 收起态优先轮播红黄灯会话，没有红黄灯时只展示最近一条会话。
    private var collapsedCarouselSessions: [CodexSession] {
        let activeSessions = model.state.sessions.filter { $0.status != .green }
        return activeSessions.isEmpty ? Array(model.state.sessions.prefix(1)) : activeSessions
    }

    private var collapsedDisplaySession: CodexSession? {
        guard !collapsedCarouselSessions.isEmpty else { return nil }
        return collapsedCarouselSessions[collapsedCarouselPosition]
    }

    private var collapsedCarouselPosition: Int {
        guard !collapsedCarouselSessions.isEmpty else { return 0 }
        return collapsedCarouselIndex % collapsedCarouselSessions.count
    }

    private var collapsedProgressText: String {
        let total = model.state.sessions.count
        guard total > 0 else { return "0/0" }
        let completed = model.state.sessions.filter { $0.status == .green }.count
        return "\(completed)/\(total)"
    }

    private func advanceCollapsedCarousel() {
        let total = collapsedCarouselSessions.count
        guard !model.isExpanded, total > 1 else { return }
        // 轮播切换只影响收起态文字，不触发展开面板布局变化。
        collapsedCarouselIndex = (collapsedCarouselIndex + 1) % total
    }

    private func normalizeCollapsedCarouselIndex() {
        let total = collapsedCarouselSessions.count
        guard total > 0 else {
            collapsedCarouselIndex = 0
            return
        }
        collapsedCarouselIndex = collapsedCarouselIndex % total
    }

    // 展开态优先展示最新 thread 和它的当前状态。
    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            let currentSession = model.state.sessions.first
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 10)
            Text(collapsedTitle(for: currentSession))
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .frame(height: model.collapsedHeight, alignment: .center)
            Text(collapsedStatusText(for: currentSession))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .frame(height: model.collapsedHeight, alignment: .center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    // 展开态展示最近会话列表，点击行只抛出回调给后续路由任务。
    private var expandedList: some View {
        VStack(spacing: 6) {
            Divider()
                .overlay(Color.white.opacity(0.12))
            if let jumpError = model.jumpError {
                Text(jumpError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 展开态展示 reader 的短错误，避免首次失败被误判为健康。
            if let readerError = model.state.errorMessage {
                Text(shortError(readerError))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 固定列表区域高度，超过窗口可用空间时在内部滚动而不是撑破窗口。
            ScrollViewReader { proxy in
                ScrollView {
                    if visibleSessions.isEmpty {
                        Text("暂无活跃会话")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, isSelected: index == model.selectedSessionIndex, onOpen: {
                                    onSelectSession(session)
                                })
                                .id(session.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: model.selectedSessionIndex) { _ in
                    scrollSelectedSession(with: proxy)
                }
                .onChange(of: model.isExpanded) { isExpanded in
                    if isExpanded {
                        scrollSelectedSession(with: proxy)
                    }
                }
            }
            .frame(height: expandedListHeight)
        }
    }

    // 展开态固定只展示前 8 条，键盘选择和滚动也限定在同一可见集合内。
    private var visibleSessions: [CodexSession] {
        Array(model.state.sessions.prefix(8))
    }

    // 键盘选择行变化时把目标行带回视野，避免选中项滚到不可见区域。
    private func scrollSelectedSession(with proxy: ScrollViewProxy) {
        guard visibleSessions.indices.contains(model.selectedSessionIndex) else { return }
        proxy.scrollTo(visibleSessions[model.selectedSessionIndex].id, anchor: .center)
    }

    private func relativeText(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return "\(hours) 小时前"
    }

    private func collapsedTitle(for session: CodexSession?) -> String {
        guard let session else { return model.state.errorMessage == nil ? "暂无会话" : "读取错误" }
        if let latestMessage = session.latestMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !latestMessage.isEmpty {
            return latestMessage
        }
        let title = session.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? session.id : title
    }

    private func collapsedStatusText(for session: CodexSession?) -> String {
        guard let session else { return model.state.errorMessage == nil ? "空闲" : "失败" }
        if let attention = session.attention {
            return attention.shortLabel
        }
        let signal = [session.lastEvent, session.errorHint].compactMap { $0 }.joined(separator: " ").lowercased()
        switch session.status {
        case .red:
            return "失败"
        case .yellow:
            if signal.contains("permission") || signal.contains("approval") || signal.contains("needs_input") || signal.contains("waiting") || signal.contains("wait") {
                return "等待"
            }
            if signal.contains("blocked") || signal.contains("timeout") {
                return "阻塞"
            }
            return "运行中"
        case .green:
            return "完成"
        }
    }

    // 展开态只展示短错误，避免系统错误占满刘海空间。
    private func shortError(_ message: String) -> String {
        String(message.prefix(96))
    }
}

// 单行会话信息，保持紧凑的桌面工具风格。
private struct SessionRow: View {
    let session: CodexSession
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(status: session.status, size: 9)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    if let latestMessage = session.latestMessage {
                        Text(latestMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(session.cwdHint)
                            .lineLimit(1)
                        Text(session.activityText)
                            .lineLimit(1)
                        if let attention = session.attention {
                            Text(attention.shortLabel)
                                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.34))
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.50))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: session.latestMessage == nil ? 46 : 58)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(isSelected ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1))
    }
}

// 自定义刘海背景支持方形顶部和圆角底部，避免收起态从状态栏里露出完整胶囊边。
private struct NotchBackgroundShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = min(max(0, topRadius), rect.width / 2, rect.height / 2)
        let bottom = min(max(0, bottomRadius), rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        if top > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top), control: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        if bottom > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        if bottom > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        if top > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

// 统一状态灯颜色，供收起态和行视图复用。
private struct StatusDot: View {
    let status: SessionStatus
    let size: CGFloat
    @State private var isBlinking = false

    var body: some View {
        ZStack {
            // 固定外圈尺寸，只动画渐变透明度和阴影，避免 transform 触发窗口约束重算。
            Circle()
                .fill(RadialGradient(colors: [haloColor.opacity(haloInnerOpacity), haloColor.opacity(haloMiddleOpacity), haloColor.opacity(haloOuterOpacity), haloColor.opacity(0.0)], center: .center, startRadius: 0, endRadius: haloSize / 2))
                .frame(width: haloSize, height: haloSize)
            Circle()
                .fill(color.opacity(coreOpacity))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.26), lineWidth: 0.6))
                .shadow(color: haloColor.opacity(shadowOpacity), radius: shadowRadius)
        }
        .frame(width: haloSize + 2, height: haloSize + 2)
        .task(id: status) {
            isBlinking = false
            guard shouldBlink else { return }
            // 避开窗口展开/收起的约束更新窗口期，稳定后再启动闪烁灯。
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }

    private var haloSize: CGFloat {
        size + 18
    }

    private var color: Color {
        switch status {
        case .red:
            return Color(red: 1.0, green: 0.25, blue: 0.22)
        case .yellow:
            return Color(red: 0.90, green: 0.96, blue: 0.24)
        case .green:
            return Color(red: 0.25, green: 0.86, blue: 0.42)
        }
    }

    // 只有红灯和黄灯闪烁，绿灯代表完成态并保持常亮。
    private var shouldBlink: Bool {
        switch status {
        case .red, .yellow:
            return true
        case .green:
            return false
        }
    }

    // 黄色单独使用偏柠檬的光晕色，避免呼吸边缘落到橙红观感。
    private var haloColor: Color {
        switch status {
        case .yellow:
            return Color(red: 0.78, green: 1.0, blue: 0.12)
        case .red, .green:
            return color
        }
    }

    // 红黄灯通过核心透明度完成闪烁，绿灯保持完成态常亮。
    private var coreOpacity: Double {
        switch status {
        case .red, .yellow:
            return isBlinking ? 1.0 : 0.30
        case .green:
            return 1.0
        }
    }

    private var haloInnerOpacity: Double {
        switch status {
        case .red:
            return isBlinking ? 0.88 : 0.08
        case .yellow:
            return isBlinking ? 0.72 : 0.10
        case .green:
            return 0.28
        }
    }

    private var haloMiddleOpacity: Double {
        switch status {
        case .red:
            return isBlinking ? 0.30 : 0.02
        case .yellow:
            return isBlinking ? 0.26 : 0.04
        case .green:
            return 0.08
        }
    }

    private var haloOuterOpacity: Double {
        switch status {
        case .red:
            return isBlinking ? 0.08 : 0.0
        case .yellow:
            return isBlinking ? 0.06 : 0.0
        case .green:
            return 0.02
        }
    }

    private var shadowOpacity: Double {
        switch status {
        case .red:
            return isBlinking ? 0.88 : 0.12
        case .yellow:
            return isBlinking ? 0.54 : 0.14
        case .green:
            return 0.42
        }
    }

    private var shadowRadius: CGFloat {
        switch status {
        case .red:
            return isBlinking ? 9 : 1.5
        case .yellow:
            return isBlinking ? 7 : 2
        case .green:
            return 4
        }
    }
}
