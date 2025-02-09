import Foundation
import Combine
import WalletConnectUtils
import WalletConnectKMS

public enum SocketConnectionStatus {
    case connected
    case disconnected
}
public final class RelayClient {
    enum RelyerError: Error {
        case subscriptionIdNotFound
    }
    private typealias SubscriptionRequest = JSONRPCRequest<RelayJSONRPC.SubscriptionParams>
    private typealias SubscriptionResponse = JSONRPCResponse<String>
    private typealias RequestAcknowledgement = JSONRPCResponse<Bool>
    private let concurrentQueue = DispatchQueue(label: "com.walletconnect.sdk.relay_client",
                                                attributes: .concurrent)
    let jsonRpcSubscriptionsHistory: JsonRpcHistory<RelayJSONRPC.SubscriptionParams>
    public var onMessage: ((String, String) -> Void)?
    private var dispatcher: Dispatching
    var subscriptions: [String: String] = [:]
    let defaultTtl = 6*Time.hour

    public var socketConnectionStatusPublisher: AnyPublisher<SocketConnectionStatus, Never> {
        socketConnectionStatusPublisherSubject.eraseToAnyPublisher()
    }
    private let socketConnectionStatusPublisherSubject = PassthroughSubject<SocketConnectionStatus, Never>()

    private var subscriptionResponsePublisher: AnyPublisher<JSONRPCResponse<String>, Never> {
        subscriptionResponsePublisherSubject.eraseToAnyPublisher()
    }
    private let subscriptionResponsePublisherSubject = PassthroughSubject<JSONRPCResponse<String>, Never>()
    private var requestAcknowledgePublisher: AnyPublisher<JSONRPCResponse<Bool>, Never> {
        requestAcknowledgePublisherSubject.eraseToAnyPublisher()
    }
    private let requestAcknowledgePublisherSubject = PassthroughSubject<JSONRPCResponse<Bool>, Never>()
    let logger: ConsoleLogging
    static let historyIdentifier = "com.walletconnect.sdk.relayer_client.subscription_json_rpc_record"

    init(
        dispatcher: Dispatching,
        logger: ConsoleLogging,
        keyValueStorage: KeyValueStorage
    ) {
        self.logger = logger
        self.dispatcher = dispatcher

        self.jsonRpcSubscriptionsHistory = JsonRpcHistory<RelayJSONRPC.SubscriptionParams>(logger: logger, keyValueStore: CodableStore<JsonRpcRecord>(defaults: keyValueStorage, identifier: Self.historyIdentifier))
        setUpBindings()
    }

    /// Instantiates Relay Client
    /// - Parameters:
    ///   - relayHost: proxy server host that your application will use to connect to Iridium Network. If you register your project at `www.walletconnect.com` you can use `relay.walletconnect.com`
    ///   - projectId: an optional parameter used to access the public WalletConnect infrastructure. Go to `www.walletconnect.com` for info.
    ///   - keyValueStorage: by default WalletConnect SDK will store sequences in UserDefaults
    ///   - socketConnectionType: socket connection type
    ///   - logger: logger instance
    public convenience init(
        relayHost: String,
        projectId: String,
        keyValueStorage: KeyValueStorage = UserDefaults.standard,
        keychainStorage: KeychainStorageProtocol = KeychainStorage(serviceIdentifier: "com.walletconnect.sdk"),
        socketFactory: WebSocketFactory,
        socketConnectionType: SocketConnectionType = .automatic,
        logger: ConsoleLogging = ConsoleLogger(loggingLevel: .off)
    ) {
        let socketAuthenticator = SocketAuthenticator(
            clientIdStorage: ClientIdStorage(keychain: keychainStorage),
            didKeyFactory: ED25519DIDKeyFactory(),
            relayHost: relayHost
        )
        let relayUrlFactory = RelayUrlFactory(socketAuthenticator: socketAuthenticator)
        let socket = socketFactory.create(with: relayUrlFactory.create(
            host: relayHost,
            projectId: projectId
        ))
        let socketConnectionHandler: SocketConnectionHandler
        switch socketConnectionType {
        case .automatic:
            socketConnectionHandler = AutomaticSocketConnectionHandler(socket: socket)
        case .manual:
            socketConnectionHandler = ManualSocketConnectionHandler(socket: socket)
        }
        let dispatcher = Dispatcher(socket: socket, socketConnectionHandler: socketConnectionHandler, logger: logger)
        self.init(dispatcher: dispatcher, logger: logger, keyValueStorage: keyValueStorage)
    }

    public func connect() throws {
        try dispatcher.connect()
    }

    public func disconnect(closeCode: URLSessionWebSocketTask.CloseCode) throws {
        try dispatcher.disconnect(closeCode: closeCode)
    }

    /// Completes when networking client sends a request, error if it fails on client side
    public func publish(topic: String, payload: String, tag: PublishTag, prompt: Bool = false) async throws {
        let params = RelayJSONRPC.PublishParams(topic: topic, message: payload, ttl: defaultTtl, prompt: prompt, tag: tag.rawValue)
        let request = JSONRPCRequest<RelayJSONRPC.PublishParams>(method: RelayJSONRPC.Method.publish.method, params: params)
        logger.debug("Publishing Payload on Topic: \(topic)")
        let requestJson = try request.json()
        try await dispatcher.send(requestJson)
    }

    /// Completes with an acknowledgement from the relay network.
    @discardableResult public func publish(
        topic: String,
        payload: String,
        tag: PublishTag,
        prompt: Bool = false,
        onNetworkAcknowledge: @escaping ((Error?) -> Void)) -> Int64 {
        let params = RelayJSONRPC.PublishParams(topic: topic, message: payload, ttl: defaultTtl, prompt: prompt, tag: tag.rawValue)
        let request = JSONRPCRequest<RelayJSONRPC.PublishParams>(method: RelayJSONRPC.Method.publish.method, params: params)
        let requestJson = try! request.json()
        logger.debug("iridium: Publishing Payload on Topic: \(topic)")
        var cancellable: AnyCancellable?
        dispatcher.send(requestJson) { [weak self] error in
            if let error = error {
                self?.logger.debug("Failed to Publish Payload, error: \(error)")
                cancellable?.cancel()
                onNetworkAcknowledge(error)
            }
        }
        cancellable = requestAcknowledgePublisher
            .filter {$0.id == request.id}
            .sink { (_) in
            cancellable?.cancel()
                onNetworkAcknowledge(nil)
        }
        return request.id
    }

    @available(*, renamed: "subscribe(topic:)")
    public func subscribe(topic: String, completion: @escaping (Error?) -> Void) {
        logger.debug("iridium: Subscribing on Topic: \(topic)")
        let params = RelayJSONRPC.SubscribeParams(topic: topic)
        let request = JSONRPCRequest(method: RelayJSONRPC.Method.subscribe.method, params: params)
        let requestJson = try! request.json()
        var cancellable: AnyCancellable?
        dispatcher.send(requestJson) { [weak self] error in
            if let error = error {
                self?.logger.debug("Failed to Subscribe on Topic \(error)")
                cancellable?.cancel()
                completion(error)
            } else {
                completion(nil)
            }
        }
        cancellable = subscriptionResponsePublisher
            .filter {$0.id == request.id}
            .sink { [weak self] (subscriptionResponse) in
            cancellable?.cancel()
                self?.concurrentQueue.async(flags: .barrier) {
                    self?.subscriptions[topic] = subscriptionResponse.result
                }
        }
    }

    public func subscribe(topic: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            subscribe(topic: topic) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    @discardableResult public func unsubscribe(topic: String, completion: @escaping ((Error?) -> Void)) -> Int64? {
        guard let subscriptionId = subscriptions[topic] else {
            completion(RelyerError.subscriptionIdNotFound)
            return nil
        }
        logger.debug("iridium: Unsubscribing on Topic: \(topic)")
        let params = RelayJSONRPC.UnsubscribeParams(id: subscriptionId, topic: topic)
        let request = JSONRPCRequest(method: RelayJSONRPC.Method.unsubscribe.method, params: params)
        let requestJson = try! request.json()
        var cancellable: AnyCancellable?
        jsonRpcSubscriptionsHistory.delete(topic: topic)
        dispatcher.send(requestJson) { [weak self] error in
            if let error = error {
                self?.logger.debug("Failed to Unsubscribe on Topic")
                cancellable?.cancel()
                completion(error)
            } else {
                self?.concurrentQueue.async(flags: .barrier) {
                    self?.subscriptions[topic] = nil
                }
                completion(nil)
            }
        }
        cancellable = requestAcknowledgePublisher
            .filter {$0.id == request.id}
            .sink { (_) in
                cancellable?.cancel()
                completion(nil)
            }
        return request.id
    }

    private func setUpBindings() {
        dispatcher.onMessage = { [weak self] payload in
            self?.handlePayloadMessage(payload)
        }
        dispatcher.onConnect = { [unowned self] in
            self.socketConnectionStatusPublisherSubject.send(.connected)
        }
    }

    private func handlePayloadMessage(_ payload: String) {
        if let request = tryDecode(SubscriptionRequest.self, from: payload), validate(request: request, method: .subscription) {
            do {
                try jsonRpcSubscriptionsHistory.set(topic: request.params.data.topic, request: request)
                onMessage?(request.params.data.topic, request.params.data.message)
                acknowledgeSubscription(requestId: request.id)
            } catch {
                logger.info("Relay Client Info: Json Rpc Duplicate Detected")
            }
        } else if let response = tryDecode(RequestAcknowledgement.self, from: payload) {
            requestAcknowledgePublisherSubject.send(response)
        } else if let response = tryDecode(SubscriptionResponse.self, from: payload) {
            subscriptionResponsePublisherSubject.send(response)
        } else if let response = tryDecode(JSONRPCErrorResponse.self, from: payload) {
            logger.error("Received error message from iridium network, code: \(response.error.code), message: \(response.error.message)")
        } else {
            logger.error("Unexpected response from network")
        }
    }

    private func validate<T>(request: JSONRPCRequest<T>, method: RelayJSONRPC.Method) -> Bool {
        return request.method.contains(method.name)
    }

    private func tryDecode<T: Decodable>(_ type: T.Type, from payload: String) -> T? {
        if let data = payload.data(using: .utf8),
           let response = try? JSONDecoder().decode(T.self, from: data) {
            return response
        } else {
            return nil
        }
    }

    private func acknowledgeSubscription(requestId: Int64) {
        let response = JSONRPCResponse(id: requestId, result: AnyCodable(true))
        let responseJson = try! response.json()
        _ = try? jsonRpcSubscriptionsHistory.resolve(response: JsonRpcResult.response(response))
        dispatcher.send(responseJson) { [weak self] error in
            if let error = error {
                self?.logger.debug("Failed to Respond for request id: \(requestId), error: \(error)")
            }
        }
    }
}
