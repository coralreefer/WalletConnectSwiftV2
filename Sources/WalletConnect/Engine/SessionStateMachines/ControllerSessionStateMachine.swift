
import Foundation
import WalletConnectUtils
import WalletConnectKMS
import Combine

final class ControllerSessionStateMachine: SessionStateMachineValidating {
    
    var onAccountsUpdate: ((String, Set<Account>)->())?
    var onMethodsUpdate: ((String, Set<String>)->())?
    var onEventsUpdate: ((String, Set<String>)->())?
    var onExpiryUpdate: ((String, Date)->())?

    private let sessionStore: WCSessionStorage
    private let relayer: WalletConnectRelaying
    private let kms: KeyManagementServiceProtocol
    private var publishers = [AnyCancellable]()
    private let logger: ConsoleLogging

    init(relay: WalletConnectRelaying,
         kms: KeyManagementServiceProtocol,
         sessionStore: WCSessionStorage,
         logger: ConsoleLogging) {
        self.relayer = relay
        self.kms = kms
        self.sessionStore = sessionStore
        self.logger = logger
        relayer.responsePublisher.sink { [unowned self] response in
            handleResponse(response)
        }.store(in: &publishers)
    }
    
    func updateAccounts(topic: String, accounts: Set<Account>) throws {
        var session = try getSession(for: topic)
        try validateControlledAcknowledged(session)
        session.updateAccounts(accounts)
        sessionStore.setSession(session)
        relayer.request(.wcSessionUpdateAccounts(SessionType.UpdateAccountsParams(accounts: accounts)), onTopic: topic)
    }
    
    func updateMethods(topic: String, methods: Set<String>) throws {
        var session = try getSession(for: topic)
        try validateControlledAcknowledged(session)
        try validateMethods(methods)
        logger.debug("Controller will update methods")
        session.updateMethods(methods)
        sessionStore.setSession(session)
        relayer.request(.wcSessionUpdateMethods(SessionType.UpdateMethodsParams(methods: methods)), onTopic: topic)
    }
    
    func updateEvents(topic: String, events: Set<String>) throws {
        var session = try getSession(for: topic)
        try validateControlledAcknowledged(session)
        try validateEvents(events)
        logger.debug("Controller will update events")
        session.updateEvents(events)
        sessionStore.setSession(session)
        relayer.request(.wcSessionUpdateEvents(SessionType.UpdateEventsParams(events: events)), onTopic: topic)
    }
    
   func updateExpiry(topic: String, by ttl: Int64) throws {
       var session = try getSession(for: topic)
       try validateControlledAcknowledged(session)
       try session.updateExpiry(by: ttl)
       let newExpiry = Int64(session.expiryDate.timeIntervalSince1970 )
       sessionStore.setSession(session)
       relayer.request(.wcSessionUpdateExpiry(SessionType.UpdateExpiryParams(expiry: newExpiry)), onTopic: topic)
   }
    
    // MARK: - Handle Response
    
    private func handleResponse(_ response: WCResponse) {
        switch response.requestParams {
        case .sessionUpdateAccounts:
            handleUpdateAccountsResponse(topic: response.topic, result: response.result)
        case .sessionUpdateMethods:
            handleUpdateMethodsResponse(topic: response.topic, result: response.result)
        case .sessionUpdateEvents:
            handleUpdateEventsResponse(topic: response.topic, result: response.result)
        case .sessionUpdateExpiry:
            handleUpdateExpiryResponse(topic: response.topic, result: response.result)
        default:
            break
        }
    }
    
    private func handleUpdateAccountsResponse(topic: String, result: JsonRpcResult) {
        guard let session = sessionStore.getSession(forTopic: topic) else {
            return
        }
        let accounts = session.accounts
        switch result {
        case .response:
            onAccountsUpdate?(topic, accounts)
        case .error:
            logger.error("Peer failed to update state.")
        }
    }
    
    private func handleUpdateMethodsResponse(topic: String, result: JsonRpcResult) {
        guard let session = sessionStore.getSession(forTopic: topic) else {
            return
        }
        switch result {
        case .response:
            //TODO - state sync
            onMethodsUpdate?(session.topic, session.methods)
        case .error:
            //TODO - state sync
            logger.error("Peer failed to update methods.")
        }
    }
    
    private func handleUpdateEventsResponse(topic: String, result: JsonRpcResult) {
        guard let session = sessionStore.getSession(forTopic: topic) else {
            return
        }
        switch result {
        case .response:
            //TODO - state sync
            onEventsUpdate?(session.topic, session.events)
        case .error:
            //TODO - state sync
            logger.error("Peer failed to update events.")
        }
    }
    
    private func handleUpdateExpiryResponse(topic: String, result: JsonRpcResult) {
        guard let session = sessionStore.getSession(forTopic: topic) else {
            return
        }
        switch result {
        case .response:
            //TODO - state sync
            onExpiryUpdate?(session.topic, session.expiryDate)
        case .error:
            //TODO - state sync
            logger.error("Peer failed to update events.")
        }
    }
    
    // MARK: - Private
    private func getSession(for topic: String) throws -> WCSession {
        if let session = sessionStore.getSession(forTopic: topic) {
            return session
        } else {
            throw WalletConnectError.noSessionMatchingTopic(topic)
        }
    }
    
    private func validateControlledAcknowledged(_ session: WCSession) throws {
        guard session.acknowledged else {
            throw WalletConnectError.sessionNotAcknowledged(session.topic)
        }
        guard session.selfIsController else {
            throw WalletConnectError.unauthorizedNonControllerCall
        }
    }
}