import Foundation
import NIO
import NIOWebSocket

// Tracks authenticated WebSocket channels and broadcasts display snapshots to them.
final class LANWebSocketClientRegistry {
    private let queue = DispatchQueue(label: "local.codex.notch.lan.clients")
    private var channels: [ObjectIdentifier: Channel] = [:]

    func add(_ channel: Channel) {
        queue.sync {
            channels[ObjectIdentifier(channel)] = channel
        }
    }

    func remove(_ channel: Channel) {
        queue.sync {
            _ = channels.removeValue(forKey: ObjectIdentifier(channel))
        }
    }

    // Sends one text frame per active client and drops inactive channels before the next broadcast.
    func broadcast(text: String) {
        let activeChannels = queue.sync { Array(channels.values) }
        for channel in activeChannels {
            guard channel.isActive else {
                remove(channel)
                continue
            }
            write(text: text, to: channel)
        }
    }

    // Closes every authenticated connection, used when the server stops or pairing credentials rotate.
    func closeAll() {
        let activeChannels = queue.sync { Array(channels.values) }
        queue.sync {
            channels.removeAll()
        }
        for channel in activeChannels {
            channel.close(promise: nil)
        }
    }

    private func write(text: String, to channel: Channel) {
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .text, data: buffer), promise: nil)
    }
}

// Handles one authenticated WebSocket connection after the HTTP upgrade succeeds.
final class LANWebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let registry: LANWebSocketClientRegistry
    private let initialSnapshotProvider: () -> String?

    init(registry: LANWebSocketClientRegistry, initialSnapshotProvider: @escaping () -> String?) {
        self.registry = registry
        self.initialSnapshotProvider = initialSnapshotProvider
    }

    func handlerAdded(context: ChannelHandlerContext) {
        registry.add(context.channel)
        if let snapshot = initialSnapshotProvider() {
            write(text: snapshot, context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        registry.remove(context.channel)
        context.fireChannelInactive()
    }

    // Responds to protocol control frames and ignores client text frames because this protocol is server-push only.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .connectionClose:
            context.close(promise: nil)
        case .ping:
            let payload = frame.data
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: payload)), promise: nil)
        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        registry.remove(context.channel)
        context.close(promise: nil)
    }

    private func write(text: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: buffer)), promise: nil)
    }
}
