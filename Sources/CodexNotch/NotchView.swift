import SwiftUI

// 驱动刘海视图的轻量状态，便于 AppKit 窗口控制器同步展开尺寸。
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState
    @Published var isExpanded: Bool
    // 展开来源决定面板顶角：胶囊入口用圆顶，刘海入口用平顶。
    @Published var isPresentedFromCapsule: Bool
    @Published var jumpError: String?
    @Published var collapsedHeight: CGFloat
    @Published var selectedSessionIndex: Int

    init(state: NotchState, isExpanded: Bool = false, collapsedHeight: CGFloat = NotchWindowMetrics.defaultCollapsedHeight) {
        self.state = state
        self.isExpanded = isExpanded
        self.isPresentedFromCapsule = false
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
    let onToggleMode: () -> Void
    @State private var collapsedCarouselIndex = 0
    // 展开态布局常量放在 NotchWindowMetrics，确保视图和窗口按同一尺寸模型收缩。
    // 收起态轮播红黄灯会话，避免多个任务时只看到最新一条。
    private let collapsedCarouselTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            notchHeader
            if model.isExpanded {
                expandedList
            }
        }
        .padding(.horizontal, model.isExpanded ? NotchWindowMetrics.expandedHorizontalInset : 0)
        .padding(.bottom, model.isExpanded ? NotchWindowMetrics.expandedBottomInset : 0)
        .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
        .clipped()
        .background(notchBackground.fill(Color.black.opacity(0.94)))
        .overlay(notchBackground.stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.04), lineWidth: 1))
        .foregroundStyle(.white)
        // 根视图使用矩形命中区域，保证悬停进入刘海边缘时也能触发展开。
        .contentShape(Rectangle())
        .contextMenu {
            // 右键菜单提供模式切换、设置和退出入口。
            Button("切换到胶囊模式") {
                onToggleMode()
            }
            Divider()
            Button("设置...") {
                onOpenSettings()
            }
            Divider()
            Button("退出 Codex Notch") {
                onQuit()
            }
        }
        .onReceive(collapsedCarouselTimer) { _ in
            advanceCollapsedCarousel()
        }
        .onChange(of: model.state.sessions) { _ in
            normalizeCollapsedCarouselIndex()
        }
    }

    // 胶囊模式展开为完整圆角浮层；刘海模式继续方形顶部贴合菜单栏。
    private var notchBackground: NotchBackgroundShape {
        NotchBackgroundShape(topRadius: model.isExpanded && model.isPresentedFromCapsule ? 18 : 0, bottomRadius: model.isExpanded ? 18 : 12)
    }

    // 根视图尺寸和 AppKit 窗口尺寸保持一致，避免 NSHostingView 用内容理想尺寸反向撑大窗口。
    private var viewSize: CGSize {
        model.isExpanded ? NotchWindowMetrics.expandedSize(for: model.state, collapsedHeight: model.collapsedHeight, hasJumpError: model.jumpError != nil) : CGSize(width: NotchWindowMetrics.collapsedWidth, height: model.collapsedHeight)
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
        model.isExpanded ? NotchWindowMetrics.expandedHeaderHeight(collapsedHeight: model.collapsedHeight) : model.collapsedHeight
    }

    // 列表高度由窗口总高反推，内容不足时跟随收缩，内容过多时在内部滚动。
    private var expandedListHeight: CGFloat {
        NotchWindowMetrics.expandedScrollHeight(for: model.state, collapsedHeight: model.collapsedHeight, hasJumpError: model.jumpError != nil)
    }

    // 收起态显示状态点、最新对话短句和完成进度，保持在状态栏高度内。
    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 7) {
            let currentSession = collapsedDisplaySession
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 14)
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
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 14)
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
        .padding(.horizontal, NotchWindowMetrics.expandedRowInnerInset)
        .contentShape(Rectangle())
    }

    // 展开态展示最近会话列表，点击行只抛出回调给后续路由任务。
    private var expandedList: some View {
        VStack(spacing: NotchWindowMetrics.expandedListSpacing) {
            Divider()
                .frame(height: NotchWindowMetrics.expandedDividerHeight)
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
            // 列表区域随内容收缩，超过最大窗口高度时在内部滚动而不是撑破窗口。
            ScrollViewReader { proxy in
                ScrollView {
                    if visibleSessions.isEmpty {
                        Text("暂无活跃会话")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    } else {
                        VStack(spacing: NotchWindowMetrics.expandedListSpacing) {
                            ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, isSelected: index == model.selectedSessionIndex, onOpen: {
                                    onSelectSession(session)
                                })
                                .id(session.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
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
            .frame(maxWidth: .infinity)
        }
    }

    // 展开态固定只展示前 8 条，键盘选择和滚动也限定在同一可见集合内。
    private var visibleSessions: [CodexSession] {
        Array(model.state.sessions.prefix(NotchWindowMetrics.visibleSessionLimit))
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
        HStack(spacing: 8) {
            StatusDot(status: session.status, size: 12)
                .frame(width: 14, alignment: .center)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

// 状态灯使用插画化深蓝外壳、白色描边和大比例发光灯面，贴近智能交通插画风格。
private struct StatusDot: View {
    let status: SessionStatus
    let size: CGFloat
    @State private var isBlinking = true

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.27), Color(red: 0.02, green: 0.06, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(Color.white.opacity(0.78), lineWidth: max(0.7, size * 0.075))
                .padding(size * 0.05)
            Circle()
                .stroke(Color(red: 0.01, green: 0.03, blue: 0.06).opacity(0.95), lineWidth: max(1.2, size * 0.16))
                .padding(size * 0.10)
            Circle()
                .fill(RadialGradient(colors: [highlightColor.opacity(0.95 * dotOpacity), color.opacity(dotOpacity), deepColor.opacity(dotOpacity)], center: UnitPoint(x: 0.40, y: 0.34), startRadius: 0, endRadius: size * 0.46))
                .padding(size * 0.16)
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: max(0.5, size * 0.035))
                .padding(size * 0.16)
            // 点阵直接落在放大的彩色灯面上，强化参考图里的数字化玻璃质感。
            ForEach(Self.textureOffsets.indices, id: \.self) { index in
                let offset = Self.textureOffsets[index]
                Circle()
                    .fill(Color.white.opacity(0.18 * dotOpacity))
                    .frame(width: max(1, size * 0.055), height: max(1, size * 0.055))
                    .offset(x: offset.x * size, y: offset.y * size)
            }
            Circle()
                .trim(from: 0.58, to: 0.78)
                .stroke(Color.white.opacity(0.76 * dotOpacity), style: StrokeStyle(lineWidth: max(1, size * 0.09), lineCap: .round))
                .padding(size * 0.22)
                .rotationEffect(.degrees(-18))
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.40 * dotOpacity), radius: max(1.2, size * 0.16), x: 0, y: 0)
        .task(id: status) {
            isBlinking = true
            guard status != .green else { return }
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                isBlinking = false
            }
        }
    }

    private var color: Color {
        switch status {
        case .red:
            return Color(red: 1.0, green: 0.25, blue: 0.22)
        case .yellow:
            return Color(red: 1.0, green: 0.92, blue: 0.10)
        case .green:
            return Color(red: 0.25, green: 0.86, blue: 0.42)
        }
    }

    private var highlightColor: Color {
        switch status {
        case .red:
            return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .yellow:
            return Color(red: 1.0, green: 0.83, blue: 0.25)
        case .green:
            return Color(red: 0.40, green: 0.95, blue: 0.58)
        }
    }

    private var deepColor: Color {
        switch status {
        case .red:
            return Color(red: 0.42, green: 0.01, blue: 0.0)
        case .yellow:
            return Color(red: 0.64, green: 0.32, blue: 0.0)
        case .green:
            return Color(red: 0.0, green: 0.34, blue: 0.12)
        }
    }

    private var dotOpacity: Double {
        guard status != .green else { return 1.0 }
        return isBlinking ? 1.0 : 0.45
    }

    private static let textureOffsets: [CGPoint] = [
        CGPoint(x: -0.18, y: -0.20),
        CGPoint(x: 0.0, y: -0.22),
        CGPoint(x: 0.18, y: -0.20),
        CGPoint(x: -0.28, y: -0.04),
        CGPoint(x: -0.10, y: -0.04),
        CGPoint(x: 0.10, y: -0.04),
        CGPoint(x: 0.28, y: -0.04),
        CGPoint(x: -0.18, y: 0.12),
        CGPoint(x: 0.0, y: 0.12),
        CGPoint(x: 0.18, y: 0.12),
        CGPoint(x: -0.08, y: 0.28),
        CGPoint(x: 0.10, y: 0.28)
    ]
}
