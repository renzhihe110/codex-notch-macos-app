import Combine
import CodexNotchShared
import Foundation

// Maintains the foreground WebSocket subscription to the paired Mac.
final class LANStatusClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published private(set) var snapshot: LANStatusSnapshot?

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var task: URLSessionWebSocketTask?
    private var pairing: LANPairingPayload?
    private var statusHandler: ((ConnectionStatus) -> Void)?
    private var retryAttempt = 0
    private var retryWorkItem: DispatchWorkItem?
    private var shouldRetry = false

    // Opens a WebSocket connection and starts the receive loop.
    func connect(pairing: LANPairingPayload, statusHandler: @escaping (ConnectionStatus) -> Void) {
        retryAttempt = 0
        shouldRetry = true
        open(pairing: pairing, statusHandler: statusHandler)
    }

    private func open(pairing: LANPairingPayload, statusHandler: @escaping (ConnectionStatus) -> Void) {
        disconnect(updateStatus: false)
        shouldRetry = true
        self.pairing = pairing
        self.statusHandler = statusHandler
        statusHandler(.connecting)
        guard let url = webSocketURL(for: pairing) else {
            statusHandler(.incompatibleProtocol)
            return
        }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNextMessage()
    }

    // Closes the active connection and cancels pending foreground retries.
    func disconnect(updateStatus: Bool = true) {
        shouldRetry = false
        retryWorkItem?.cancel()
        retryWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if updateStatus {
            publishStatus(.offline("已断开"))
        }
    }

    private func webSocketURL(for pairing: LANPairingPayload) -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = pairing.host
        components.port = pairing.port
        components.path = LANStatusProtocol.streamPath
        components.queryItems = [
            URLQueryItem(name: "token", value: pairing.token),
            URLQueryItem(name: "v", value: String(pairing.version))
        ]
        return components.url
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveNextMessage()
            case .failure(let error):
                self.handleTransientFailure(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let value):
            data = value
        @unknown default:
            data = nil
        }
        guard let data else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decodedSnapshot = try? decoder.decode(LANStatusSnapshot.self, from: data) else { return }
        guard decodedSnapshot.version == LANStatusProtocol.version else {
            publishStatus(.incompatibleProtocol)
            disconnect(updateStatus: false)
            return
        }
        DispatchQueue.main.async {
            self.retryAttempt = 0
            self.snapshot = decodedSnapshot
            self.statusHandler?(.connected)
        }
    }

    private func handleTransientFailure(_ error: Error) {
        guard shouldRetry else { return }
        publishStatus(.offline(error.localizedDescription))
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard shouldRetry, let pairing, retryAttempt < 5 else { return }
        retryAttempt += 1
        let delay = min(pow(2.0, Double(retryAttempt)), 30.0)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.open(pairing: pairing, statusHandler: self.statusHandler ?? { _ in })
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func publishStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async {
            self.statusHandler?(status)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        publishStatus(.connected)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard shouldRetry else { return }
        if closeCode == .policyViolation {
            publishStatus(.authenticationFailed)
        } else {
            publishStatus(.offline("连接已关闭"))
        }
    }
}
