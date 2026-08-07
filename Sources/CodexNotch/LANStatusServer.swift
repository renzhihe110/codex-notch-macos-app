import CodexNotchShared
import Combine
import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket

// Exposes the local-network status publisher lifecycle to the app and settings UI.
enum LANStatusServerState: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case failed(message: String)

    var displayText: String {
        switch self {
        case .stopped:
            return "未启动"
        case .starting:
            return "启动中"
        case .running(let port):
            return "运行中：\(port)"
        case .failed(let message):
            return "启动失败：\(message)"
        }
    }
}

// Owns the SwiftNIO listener and broadcasts display-safe snapshots to authenticated iOS clients.
final class LANStatusServer: ObservableObject {
    static let shared = LANStatusServer()

    @Published private(set) var state: LANStatusServerState = .stopped

    private let registry = LANWebSocketClientRegistry()
    private let snapshotQueue = DispatchQueue(label: "local.codex.notch.lan.snapshot")
    private var latestSnapshotText: String?
    private var pairingStore: PairingStore?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    // Starts the WebSocket server on all interfaces so paired iPhones can connect over the LAN.
    func start(pairingStore: PairingStore) {
        guard eventLoopGroup == nil else { return }
        self.pairingStore = pairingStore
        state = .starting
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededFuture(()) }
                return self.configure(channel: channel)
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        bootstrap.bind(host: "0.0.0.0", port: pairingStore.port).whenComplete { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let channel):
                    self?.serverChannel = channel
                    self?.state = .running(port: pairingStore.port)
                case .failure(let error):
                    self?.state = .failed(message: error.localizedDescription)
                    self?.shutdownEventLoop()
                }
            }
        }
    }

    // Stops the listener and all active client channels without touching the macOS notch UI state.
    func stop() {
        registry.closeAll()
        serverChannel?.close(promise: nil)
        serverChannel = nil
        shutdownEventLoop()
        state = .stopped
    }

    // Encodes and broadcasts the latest display snapshot to every authenticated client.
    func broadcast(snapshot: LANStatusSnapshot) {
        guard let text = encode(snapshot: snapshot) else { return }
        snapshotQueue.sync {
            latestSnapshotText = text
        }
        registry.broadcast(text: text)
    }

    // Disconnects current clients so a token reset takes effect immediately.
    func disconnectClients() {
        registry.closeAll()
    }

    private func configure(channel: Channel) -> EventLoopFuture<Void> {
        let httpHandler = LANHTTPStatusHandler()
        let httpHandlerName = "lan-http-status"
        let upgrader = NIOWebSocketServerUpgrader(shouldUpgrade: { [weak self] channel, head in
            guard self?.isAuthorizedWebSocketRequest(head) == true else { return channel.eventLoop.makeSucceededFuture(nil) }
            return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
        }, upgradePipelineHandler: { [weak self] channel, _ in
            guard let self else { return channel.eventLoop.makeSucceededFuture(()) }
            return channel.pipeline.addHandler(LANWebSocketHandler(registry: self.registry, initialSnapshotProvider: { [weak self] in self?.currentSnapshotText() }))
        })
        let upgradeConfiguration = NIOHTTPServerUpgradeConfiguration(upgraders: [upgrader], completionHandler: { context in
            context.pipeline.removeHandler(name: httpHandlerName, promise: nil)
        })
        return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfiguration).flatMap {
            channel.pipeline.addHandler(httpHandler, name: httpHandlerName)
        }
    }

    private func isAuthorizedWebSocketRequest(_ head: HTTPRequestHead) -> Bool {
        guard let components = URLComponents(string: "http://localhost\(head.uri)"), components.path == LANStatusProtocol.streamPath else { return false }
        let items = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            guard let value = item.value else { return }
            result[item.name] = value
        }
        guard let token = items["token"], let versionValue = items["v"], Int(versionValue) == LANStatusProtocol.version else { return false }
        return pairingStore?.isToken(token) == true
    }

    private func currentSnapshotText() -> String? {
        snapshotQueue.sync {
            latestSnapshotText
        }
    }

    private func encode(snapshot: LANStatusSnapshot) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func shutdownEventLoop() {
        let group = eventLoopGroup
        eventLoopGroup = nil
        group?.shutdownGracefully { _ in }
    }
}

// Handles non-WebSocket requests with lightweight health responses for manual LAN checks.
private final class LANHTTPStatusHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
        case .end:
            sendResponse(context: context)
        default:
            break
        }
    }

    private func sendResponse(context: ChannelHandlerContext) {
        guard let requestHead else { return }
        let status: HTTPResponseStatus = requestHead.uri == "/health" ? .ok : .notFound
        let bodyText = status == .ok ? #"{"status":"ok"}"# : #"{"error":"not_found"}"#
        var buffer = context.channel.allocator.buffer(capacity: bodyText.utf8.count)
        buffer.writeString(bodyText)
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json; charset=utf-8")
        headers.add(name: "content-length", value: String(buffer.readableBytes))
        let head = HTTPResponseHead(version: requestHead.version, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
