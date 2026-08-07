import SwiftUI

// 驱动刘海视图的轻量状态，便于 AppKit 窗口控制器同步展开尺寸。
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState
    @Published var isExpanded: Bool
    // 展开来源决定面板顶角：胶囊入口用圆顶，刘海入口用平顶。
    @Published var isPresentedFromCapsule: Bool
    @Published var jumpError: String?
    @Published var collapsedHeight: CGFloat
    @Published var expandedScale: CGFloat
    @Published var selectedSessionIndex: Int
    @Published var isPinned: Bool

    init(state: NotchState, isExpanded: Bool = false, collapsedHeight: CGFloat = NotchWindowMetrics.defaultCollapsedHeight) {
        self.state = state
        self.isExpanded = isExpanded
        self.isPresentedFromCapsule = false
        self.collapsedHeight = collapsedHeight
        self.expandedScale = 1
        self.selectedSessionIndex = 0
        self.isPinned = false
    }
}

// 展示桌面顶部刘海和展开后的多会话列表。
struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    let onSelectSession: (CodexSession) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onToggleMode: () -> Void
    let onTogglePin: () -> Void
    let onClose: () -> Void
    // 监听共享字体偏好，确保刘海和悬浮面板会即时应用新字体。
    @ObservedObject private var fontSettings = FontSettings.shared
    // 监听项目目录颜色偏好，用户选色后立即刷新悬浮任务行。
    @ObservedObject private var directoryColorSettings = DirectoryColorSettings.shared
    // 监听悬浮面板尺寸偏好，窗口缩放时让 SwiftUI 内容立即跟随新尺寸。
    @ObservedObject private var floatingDashboardSettings = FloatingDashboardSettings.shared
    @State private var collapsedCarouselIndex = 0
    // 展开态布局常量放在 NotchWindowMetrics，确保视图和窗口按同一尺寸模型收缩。
    // 收起态轮播红黄灯会话，避免多个任务时只看到最新一条。
    private let collapsedCarouselTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.isExpanded && model.isPresentedFromCapsule {
                floatingDashboard
            } else {
                notchBody
            }
        }
        .foregroundStyle(.white)
        .font(fontSettings.font(size: 13))
        // 根视图使用矩形命中区域，保证无边框 Dashboard 内部都能可靠接收事件。
        .contentShape(Rectangle())
        .contextMenu {
            Button(model.isPresentedFromCapsule ? "切换到刘海居中模式" : "切换到悬浮模式") {
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

    // 刘海和热键入口继续使用原布局，悬浮模式改造不会进入这条路径。
    private var notchBody: some View {
        VStack(spacing: 0) {
            notchHeader
            if model.isExpanded {
                expandedList
            }
        }
        .padding(.horizontal, model.isExpanded ? NotchWindowMetrics.expandedHorizontalInset * expandedContentScale : 0)
        .padding(.bottom, model.isExpanded ? NotchWindowMetrics.expandedBottomInset * expandedContentScale : 0)
        .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
        .clipped()
        .background(notchBackground.fill(Color.black.opacity(0.94)))
        .overlay(notchBackground.stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.04), lineWidth: 1))
    }

    // 胶囊模式展开为完整圆角浮层；刘海模式继续方形顶部贴合菜单栏。
    private var notchBackground: NotchBackgroundShape {
        NotchBackgroundShape(topRadius: model.isExpanded && model.isPresentedFromCapsule ? 18 : 0, bottomRadius: model.isExpanded ? 18 : 12)
    }

    // 根视图尺寸和 AppKit 窗口尺寸保持一致，避免 NSHostingView 用内容理想尺寸反向撑大窗口。
    private var viewSize: CGSize {
        if model.isExpanded && model.isPresentedFromCapsule { return floatingDashboardSettings.size }
        return model.isExpanded ? NotchWindowMetrics.expandedSize(for: model.state, collapsedHeight: model.collapsedHeight, hasJumpError: model.jumpError != nil, scale: model.expandedScale) : CGSize(width: NotchWindowMetrics.collapsedWidth, height: model.collapsedHeight)
    }

    // 热键大窗口按 expandedScale 放大展开态内容，普通展开保持 1 倍。
    private var expandedContentScale: CGFloat {
        model.isExpanded ? model.expandedScale : 1
    }

    // 悬浮模式按用户保存的尺寸显示单列 Dashboard，不再绘制猫咪和面板之间的连接段。
    private var floatingDashboard: some View {
        floatingCard
            .frame(width: floatingDashboardSettings.size.width, height: floatingDashboardSettings.size.height)
    }

    // Dashboard 卡片使用完整黑色圆角外壳，内部直接排列任务行和底部 Token 摘要。
    private var floatingCard: some View {
        VStack(spacing: 10) {
            floatingHeader
                .frame(height: 30)
            floatingTaskList
                .frame(height: floatingTaskListHeight)
            tokenSummaryFooter
                .frame(height: 38)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(width: floatingDashboardSettings.size.width, height: floatingDashboardSettings.size.height)
        // 石墨外壳与任务卡分层，避免半透明青蓝色污染整块面板。
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.055, green: 0.063, blue: 0.071)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(red: 0.165, green: 0.188, blue: 0.216), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // 标题栏提供真实的常驻、设置和关闭行为，并显示图钉选中态。
    private var floatingHeader: some View {
        HStack(spacing: 9) {
            floatingAssistantIcon
                .font(fontSettings.font(size: 18, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.20, green: 0.78, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 24)
            Text("Codex 悬浮助手")
                .font(fontSettings.font(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            // 跳转失败保留在标题栏提示，避免移除任务分组后丢失反馈。
            if let jumpError = model.jumpError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(fontSettings.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                    .help(jumpError)
            }
            Spacer(minLength: 0)
            floatingHeaderButton(systemName: model.isPinned ? "pin.fill" : "pin", help: model.isPinned ? "取消常驻" : "常驻面板", isActive: model.isPinned, action: onTogglePin)
            floatingHeaderButton(systemName: "gearshape", help: "打开设置", action: onOpenSettings)
            floatingHeaderButton(systemName: "xmark", help: "关闭面板", action: onClose)
        }
        .padding(.horizontal, 4)
    }

    // visionpro 在新系统上更接近参考标识，macOS 13 保留可见的 CPU 回退。
    @ViewBuilder private var floatingAssistantIcon: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: "visionpro")
        } else {
            Image(systemName: "cpu")
        }
    }

    private func floatingHeaderButton(systemName: String, help: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(fontSettings.font(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color(red: 0.44, green: 0.76, blue: 1.0) : .white.opacity(0.66))
                .frame(width: 26, height: 26)
                .background(Circle().fill(isActive ? Color(red: 0.08, green: 0.28, blue: 0.68).opacity(0.70) : Color.clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // 主区最多展示 15 条真实主任务，超过可视区域时在卡片内滚动。
    private var floatingTaskList: some View {
        Group {
            if floatingVisibleSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(fontSettings.font(size: 22))
                    Text("暂无任务")
                        .font(fontSettings.font(size: 12))
                }
                .foregroundStyle(.white.opacity(0.40))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(floatingVisibleSessions) { session in
                            floatingTaskRow(session)
                        }
                    }
                    // 顶部和两侧保留与任务间距一致的空白，避免首行与边缘描边被裁切。
                    .padding([.top, .horizontal], 6)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Token 仅在底部汇总，输入值包含缓存并单独标出其中缓存量。
    private var tokenSummaryFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            // 分割线下方单独占满余下高度，与任务卡左边缘对齐且上下居中。
            HStack(spacing: 0) {
                Text(tokenSummaryText)
                    .font(fontSettings.font(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var floatingVisibleSessions: [CodexSession] {
        Array(model.state.sessions.prefix(15))
    }

    // 固定的标题栏、底部摘要、间距和内边距共占 102pt，其余高度都交给可滚动任务区。
    private var floatingTaskListHeight: CGFloat { max(0, floatingDashboardSettings.size.height - 102) }

    private func floatingTaskRow(_ session: CodexSession) -> some View {
        Button {
            onSelectSession(session)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: floatingTaskSymbol(session))
                    .font(fontSettings.font(size: 14, weight: .semibold))
                    .foregroundStyle(floatingTaskAccent(session))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(floatingTaskStatusBackground(session)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(fontSettings.font(size: 19.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                    // 项目目录单独着色并放在开头，保证长消息截断后仍可识别。
                    HStack(spacing: 0) { Text(session.cwdHint).foregroundStyle(directoryColorSettings.color); Text(floatingTaskSubtitleDetails(session)) }
                        .font(fontSettings.font(size: 15))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(floatingStatusText(for: session))
                    .font(fontSettings.font(size: 15))
                    .foregroundStyle(floatingTaskColor(session))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Capsule().fill(floatingTaskStatusBackground(session)))
            }
            .padding(.horizontal, 10)
            .frame(height: 62)
            .background(ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.090, green: 0.102, blue: 0.118))
                // 运行态在内容下方绘制彗星矩阵，保持任务文字和按钮命中不受影响。
                if isFloatingTaskRunning(session) { RunningTaskCometBackground() }
            }.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isFloatingTaskRunning(session) ? Color(red: 0.941, green: 0.725, blue: 0.325).opacity(0.82) : Color(red: 0.165, green: 0.188, blue: 0.216), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // 只有当前文案语义为运行中的黄灯任务播放粒子，等待处理和停滞状态保持静止。
    private func isFloatingTaskRunning(_ session: CodexSession) -> Bool {
        session.status == .yellow && session.attention == nil
    }

    // 图标与状态标签都仅反映真实会话状态，任务标题不再影响颜色。
    private func floatingTaskAccent(_ session: CodexSession) -> Color {
        return floatingTaskColor(session)
    }

    private func floatingTaskColor(_ session: CodexSession) -> Color {
        switch session.status {
        case .red:
            return Color(red: 0.878, green: 0.478, blue: 0.463)
        case .yellow:
            return Color(red: 0.851, green: 0.604, blue: 0.212)
        case .green:
            return Color(red: 0.204, green: 0.827, blue: 0.600)
        }
    }

    // 深色状态底保留可读性，并让翡翠色只落在完成态，琥珀色只用于需关注任务。
    private func floatingTaskStatusBackground(_ session: CodexSession) -> Color {
        switch session.status {
        case .red:
            return Color(red: 0.282, green: 0.149, blue: 0.165)
        case .yellow:
            return Color(red: 0.231, green: 0.176, blue: 0.106)
        case .green:
            return Color(red: 0.071, green: 0.247, blue: 0.220)
        }
    }

    private func floatingTaskSymbol(_ session: CodexSession) -> String {
        let title = session.displayTitle.lowercased()
        if title.contains("文档") || title.contains("说明") || title.contains("readme") || title.hasPrefix("pr ") || title.contains("pull request") { return "doc.text" }
        if title.contains("修复") || title.contains("bug") { return "ladybug" }
        if title.contains("测试") || title.contains("运行") { return "checkmark.circle" }
        if title.contains("代码") || title.contains("组件") || title.contains("插件") { return "cube" }
        switch session.status {
        case .red:
            return "exclamationmark.triangle"
        case .yellow:
            return "gearshape.2"
        case .green:
            return "checkmark.circle"
        }
    }

    // 剩余副标题沿用弱化颜色，目录本身由独立 Text 使用用户选择的颜色。
    private func floatingTaskSubtitleDetails(_ session: CodexSession) -> String {
        let latestMessage = session.latestMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let latestMessage, !latestMessage.isEmpty { return " · \(latestMessage) · \(session.activityText)" }
        return " · \(session.activityText)"
    }

    private func floatingStatusText(for session: CodexSession) -> String {
        session.status == .green && session.attention == nil ? "已完成" : collapsedStatusText(for: session)
    }

    private var tokenSummaryText: String {
        let usage = model.state.todayTokenUsage
        let warning = usage.errorMessage == nil ? "" : " · 统计不完整"
        return "输入 \(compactTokenCount(usage.inputTokens))，其中缓存 \(compactTokenCount(usage.cachedInputTokens))；输出 \(compactTokenCount(usage.outputTokens))；总 \(compactTokenCount(usage.totalTokens))\(warning)"
    }

    private func compactTokenCount(_ value: Int64) -> String {
        if value >= 1_000_000 {
            return "\((Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...2))))M"
        }
        if value >= 1_000 {
            return "\((Double(value) / 1_000).formatted(.number.precision(.fractionLength(0...2))))K"
        }
        return value.formatted(.number.grouping(.automatic))
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
        model.isExpanded ? NotchWindowMetrics.expandedHeaderHeight(collapsedHeight: model.collapsedHeight, scale: expandedContentScale) : model.collapsedHeight
    }

    // 列表高度由窗口总高反推，内容不足时跟随收缩，内容过多时在内部滚动。
    private var expandedListHeight: CGFloat {
        NotchWindowMetrics.expandedScrollHeight(for: model.state, collapsedHeight: model.collapsedHeight, hasJumpError: model.jumpError != nil, scale: model.expandedScale)
    }

    // 收起态显示状态点、最新对话短句和完成进度，保持在状态栏高度内。
    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 7) {
            let currentSession = collapsedDisplaySession
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 14)
            Text(collapsedTitle(for: currentSession))
                .font(fontSettings.font(size: 13))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 16, alignment: .center)
                .id(currentSession?.id ?? "empty")
            Text(collapsedProgressText)
                .font(fontSettings.font(size: 11))
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
        HStack(alignment: .center, spacing: 8 * expandedContentScale) {
            let currentSession = model.state.sessions.first
            StatusDot(status: currentSession?.status ?? model.state.aggregateStatus, size: 14 * expandedContentScale)
            Text(collapsedTitle(for: currentSession))
                .font(fontSettings.font(size: 14 * expandedContentScale))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .frame(height: model.collapsedHeight * expandedContentScale, alignment: .center)
            Text(collapsedStatusText(for: currentSession))
                .font(fontSettings.font(size: 12 * expandedContentScale))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .frame(height: model.collapsedHeight * expandedContentScale, alignment: .center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, NotchWindowMetrics.expandedRowInnerInset * expandedContentScale)
        .contentShape(Rectangle())
    }

    // 展开态展示最近会话列表，点击行只抛出回调给后续路由任务。
    private var expandedList: some View {
        VStack(spacing: NotchWindowMetrics.expandedListSpacing * expandedContentScale) {
            Divider()
                .frame(height: NotchWindowMetrics.expandedDividerHeight)
                .overlay(Color.white.opacity(0.12))
            if let jumpError = model.jumpError {
                Text(jumpError)
                    .font(fontSettings.font(size: 11 * expandedContentScale))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 展开态展示 reader 的短错误，避免首次失败被误判为健康。
            if let readerError = model.state.errorMessage {
                Text(shortError(readerError))
                    .font(fontSettings.font(size: 11 * expandedContentScale))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.58))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 列表区域随内容收缩，超过最大窗口高度时在内部滚动而不是撑破窗口。
            ScrollViewReader { proxy in
                ScrollView {
                    if visibleSessions.isEmpty {
                        Text("暂无活跃会话")
                            .font(fontSettings.font(size: 13 * expandedContentScale))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, minHeight: 46 * expandedContentScale)
                    } else {
                        VStack(spacing: NotchWindowMetrics.expandedListSpacing * expandedContentScale) {
                            ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, isSelected: index == model.selectedSessionIndex, scale: expandedContentScale, onOpen: {
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

// 彗星矩阵使用时间轴和 Canvas 直接绘制，避免为每颗粒子创建独立 SwiftUI 视图。
private struct RunningTaskCometBackground: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private static let particles: [CometParticle] = [
        CometParticle(verticalPosition: 0.16, delay: 0.00, duration: 2.50, trailLength: 24, thickness: 1.4, isEmerald: false),
        CometParticle(verticalPosition: 0.31, delay: 0.23, duration: 2.50, trailLength: 18, thickness: 1.2, isEmerald: false),
        CometParticle(verticalPosition: 0.47, delay: 0.46, duration: 2.50, trailLength: 28, thickness: 1.5, isEmerald: true),
        CometParticle(verticalPosition: 0.68, delay: 0.69, duration: 2.50, trailLength: 20, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.82, delay: 0.92, duration: 2.50, trailLength: 26, thickness: 1.4, isEmerald: false),
        CometParticle(verticalPosition: 0.24, delay: 1.15, duration: 2.50, trailLength: 16, thickness: 1.1, isEmerald: true),
        CometParticle(verticalPosition: 0.57, delay: 1.38, duration: 2.50, trailLength: 22, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.75, delay: 1.61, duration: 2.50, trailLength: 30, thickness: 1.5, isEmerald: false),
        CometParticle(verticalPosition: 0.39, delay: 1.84, duration: 2.50, trailLength: 19, thickness: 1.2, isEmerald: true),
        CometParticle(verticalPosition: 0.90, delay: 2.07, duration: 2.50, trailLength: 24, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.10, delay: 2.30, duration: 2.50, trailLength: 21, thickness: 1.2, isEmerald: false)
    ]

    @ViewBuilder var body: some View {
        if accessibilityReduceMotion {
            cometLayer(elapsed: 0.92)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                cometLayer(elapsed: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    // 单个 Canvas 同时绘制扫描光带、彗星拖尾和粒子头，减少运行态刷新开销。
    private func cometLayer(elapsed: TimeInterval) -> some View {
        Canvas { context, size in
            let amber = Color(red: 0.941, green: 0.725, blue: 0.325)
            let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)
            let scanProgress = CGFloat(elapsed.truncatingRemainder(dividingBy: 2.5) / 2.5)
            let scanWidth = max(48, size.width * 0.28)
            let scanX = -scanWidth + (size.width + scanWidth * 2) * scanProgress
            var scanPath = Path()
            scanPath.move(to: CGPoint(x: scanX + scanWidth * 0.18, y: 0))
            scanPath.addLine(to: CGPoint(x: scanX + scanWidth, y: 0))
            scanPath.addLine(to: CGPoint(x: scanX + scanWidth * 0.82, y: size.height))
            scanPath.addLine(to: CGPoint(x: scanX, y: size.height))
            scanPath.closeSubpath()
            context.fill(scanPath, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: amber.opacity(0.04), location: 0.24), .init(color: amber.opacity(0.16), location: 0.64), .init(color: .clear, location: 1)]), startPoint: CGPoint(x: scanX, y: size.height / 2), endPoint: CGPoint(x: scanX + scanWidth, y: size.height / 2)))

            for particle in Self.particles {
                let progress = CGFloat((elapsed + particle.delay).truncatingRemainder(dividingBy: particle.duration) / particle.duration)
                let headX = -particle.trailLength + (size.width + particle.trailLength * 2) * progress
                let drift = CGFloat(sin((elapsed + particle.delay) * 1.6)) * 1.6 + (0.5 - progress) * 8
                let headY = particle.verticalPosition * size.height + drift
                let fadeIn = min(1, progress / 0.12)
                let fadeOut = min(1, (1 - progress) / 0.18)
                let opacity = max(0, min(fadeIn, fadeOut))
                let color = particle.isEmerald ? emerald : amber
                let trailStart = CGPoint(x: headX - particle.trailLength, y: headY)
                let trailEnd = CGPoint(x: headX, y: headY)
                var trailPath = Path()
                trailPath.move(to: trailStart)
                trailPath.addLine(to: trailEnd)

                var glowContext = context
                glowContext.opacity = Double(opacity * 0.14)
                glowContext.stroke(trailPath, with: .color(color), style: StrokeStyle(lineWidth: particle.thickness + 2, lineCap: .round))

                var trailContext = context
                trailContext.opacity = Double(opacity)
                trailContext.stroke(trailPath, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.34), location: 0.52), .init(color: color, location: 1)]), startPoint: trailStart, endPoint: trailEnd), style: StrokeStyle(lineWidth: particle.thickness, lineCap: .round))
                trailContext.fill(Path(ellipseIn: CGRect(x: headX - 1.3, y: headY - 1.3, width: 2.6, height: 2.6)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// 粒子参数使用固定种子，保证任务列表刷新后仍保持稳定的视觉密度。
private struct CometParticle {
    let verticalPosition: CGFloat
    let delay: TimeInterval
    let duration: TimeInterval
    let trailLength: CGFloat
    let thickness: CGFloat
    let isEmerald: Bool
}

// 单行会话信息，保持紧凑的桌面工具风格。
private struct SessionRow: View {
    let session: CodexSession
    let isSelected: Bool
    let scale: CGFloat
    let onOpen: () -> Void
    // 列表行单独观察字体设置，避免 SwiftUI 复用行时保留旧字体。
    @ObservedObject private var fontSettings = FontSettings.shared

    var body: some View {
        HStack(spacing: 8 * scale) {
            StatusDot(status: session.status, size: 12 * scale)
                .frame(width: 14 * scale, alignment: .center)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(session.displayTitle)
                        .font(fontSettings.font(size: 14 * scale))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    if let latestMessage = session.latestMessage {
                        Text(latestMessage)
                            .font(fontSettings.font(size: 11 * scale))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6 * scale) {
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
                    .font(fontSettings.font(size: 11 * scale))
                    .foregroundStyle(.white.opacity(0.50))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .frame(height: (session.latestMessage == nil ? 46 : 58) * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).stroke(isSelected ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1))
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
            if status == .green {
                Circle()
                    .fill(Color(red: 0.58, green: 1.0, blue: 0.78).opacity(0.26))
                    .frame(width: max(2, size * 0.18), height: max(2, size * 0.18))
                    .offset(x: -size * 0.10, y: -size * 0.12)
            } else {
                // 红黄灯保留点阵和弧光，绿灯不画这些高亮，避免小尺寸下看成黄绿叠加。
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
            return Color(red: 0.08, green: 0.82, blue: 0.42)
        }
    }

    private var highlightColor: Color {
        switch status {
        case .red:
            return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .yellow:
            return Color(red: 1.0, green: 0.83, blue: 0.25)
        case .green:
            return Color(red: 0.18, green: 0.98, blue: 0.58)
        }
    }

    private var deepColor: Color {
        switch status {
        case .red:
            return Color(red: 0.42, green: 0.01, blue: 0.0)
        case .yellow:
            return Color(red: 0.64, green: 0.32, blue: 0.0)
        case .green:
            return Color(red: 0.0, green: 0.30, blue: 0.18)
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
