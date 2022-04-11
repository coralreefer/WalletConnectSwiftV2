import XCTest
import WalletConnectUtils
@testable import TestingUtils
import WalletConnectKMS
@testable import WalletConnect

extension Collection where Self.Element == String {
    func toAccountSet() -> Set<Account> {
        Set(self.map { Account($0)! })
    }
}

final class SessionEngineTests: XCTestCase {
    
    var engine: SessionEngine!

    var relayMock: MockedWCRelay!
    var subscriberMock: MockedSubscriber!
    var storageMock: WCSessionStorageMock!
    var cryptoMock: KeyManagementServiceMock!
    
    var topicGenerator: TopicGenerator!
    
    var metadata: AppMetadata!
    
    override func setUp() {
        relayMock = MockedWCRelay()
        subscriberMock = MockedSubscriber()
        storageMock = WCSessionStorageMock()
        cryptoMock = KeyManagementServiceMock()
        topicGenerator = TopicGenerator()
        setupEngine()
    }

    override func tearDown() {
        relayMock = nil
        subscriberMock = nil
        storageMock = nil
        cryptoMock = nil
        topicGenerator = nil
        engine = nil
    }
    
    func setupEngine() {
        metadata = AppMetadata.stub()
        let logger = ConsoleLoggerMock()
        engine = SessionEngine(
            relay: relayMock,
            kms: cryptoMock,
            subscriber: subscriberMock,
            sessionStore: storageMock,
            metadata: metadata,
            logger: logger,
            topicGenerator: topicGenerator.getTopic)
    }
    

    
    func testSessionSettle() {
        let agreementKeys = AgreementKeys.stub()
        let topicB = String.generateTopic()
        cryptoMock.setAgreementSecret(agreementKeys, topic: topicB)
        
        let proposal = SessionProposal.stub(proposerPubKey: AgreementPrivateKey().publicKey.hexRepresentation)
        
        engine.settle(topic: topicB, proposal: proposal, accounts: [])
        
        XCTAssertTrue(storageMock.hasSequence(forTopic: topicB), "Responder must persist session on topic B")
        XCTAssert(subscriberMock.didSubscribe(to: topicB), "Responder must subscribe for topic B")
        XCTAssertTrue(relayMock.didCallRequest, "Responder must send session settle payload on topic B")
    }
    
    func testHandleSessionSettle() {
        let sessionTopic = String.generateTopic()
        cryptoMock.setAgreementSecret(AgreementKeys.stub(), topic: sessionTopic)
        var didCallBackOnSessionApproved = false
        engine.onSessionSettle = { _ in
            didCallBackOnSessionApproved = true
        }
        
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubSettle(topic: sessionTopic))
        
        XCTAssertTrue(storageMock.getSequence(forTopic: sessionTopic)!.acknowledged, "Proposer must store acknowledged session on topic B")
        XCTAssertTrue(relayMock.didRespondSuccess, "Proposer must send acknowledge on settle request")
        XCTAssertTrue(didCallBackOnSessionApproved, "Proposer's engine must call back with session")
    }
    
    func testHandleSessionSettleAcknowledge() {
        let session = WCSession.stub(isSelfController: true, acknowledged: false)
        storageMock.setSequence(session)
        var didCallBackOnSessionApproved = false
        engine.onSessionSettle = { _ in
            didCallBackOnSessionApproved = true
        }
        
        let settleResponse = JSONRPCResponse(id: 1, result: AnyCodable(true))
        let response = WCResponse(
            topic: session.topic,
            chainId: nil,
            requestMethod: .sessionSettle,
            requestParams: .sessionSettle(SessionType.SettleParams.stub()),
            result: .response(settleResponse))
        relayMock.onResponse?(response)

        XCTAssertTrue(storageMock.getSequence(forTopic: session.topic)!.acknowledged, "Responder must acknowledged session")
        XCTAssertTrue(didCallBackOnSessionApproved, "Responder's engine must call back with session")
    }
    
    func testHandleSessionSettleError() {
        let privateKey = AgreementPrivateKey()
        let session = WCSession.stub(isSelfController: false, selfPrivateKey: privateKey, acknowledged: false)
        storageMock.setSequence(session)
        cryptoMock.setAgreementSecret(AgreementKeys.stub(), topic: session.topic)
        try! cryptoMock.setPrivateKey(privateKey)

        let response = WCResponse(
            topic: session.topic,
            chainId: nil,
            requestMethod: .sessionSettle,
            requestParams: .sessionSettle(SessionType.SettleParams.stub()),
            result: .error(JSONRPCErrorResponse(id: 1, error: JSONRPCErrorResponse.Error(code: 0, message: ""))))
        relayMock.onResponse?(response)

        XCTAssertNil(storageMock.getSequence(forTopic: session.topic), "Responder must remove session")
        XCTAssertTrue(subscriberMock.didUnsubscribe(to: session.topic), "Responder must unsubscribe topic B")
        XCTAssertFalse(cryptoMock.hasAgreementSecret(for: session.topic), "Responder must remove agreement secret")
        XCTAssertFalse(cryptoMock.hasPrivateKey(for: session.self.publicKey!), "Responder must remove private key")
    }

    // MARK: - Update call tests
    
    func testUpdateSuccess() throws {
        let updateAccounts = ["std:0:0"]
        let session = WCSession.stub(isSelfController: true)
        storageMock.setSequence(session)
        try engine.updateAccounts(topic: session.topic, accounts: updateAccounts.toAccountSet())
        XCTAssertTrue(relayMock.didCallRequest)
    }
    
    func testUpdateErrorIfNonController() {
        let updateAccounts = ["std:0:0"]
        let session = WCSession.stub(isSelfController: false)
        storageMock.setSequence(session)
        XCTAssertThrowsError(try engine.updateAccounts(topic: session.topic, accounts: updateAccounts.toAccountSet()), "Update must fail if called by a non-controller.")
    }
    
    func testUpdateErrorSessionNotFound() {
        let updateAccounts = ["std:0:0"]
        XCTAssertThrowsError(try engine.updateAccounts(topic: "", accounts: updateAccounts.toAccountSet()), "Update must fail if there is no session matching the target topic.")
    }
    
    func testUpdateErrorSessionNotSettled() {
        let updateAccounts = ["std:0:0"]
        let session = WCSession.stub(acknowledged: false)
        storageMock.setSequence(session)
        XCTAssertThrowsError(try engine.updateAccounts(topic: session.topic, accounts: updateAccounts.toAccountSet()), "Update must fail if session is not on settled state.")
    }
    
    // MARK: - Update peer response tests
    
    func testUpdatePeerSuccess() {
        let session = WCSession.stub(isSelfController: false)
        storageMock.setSequence(session)
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateAccounts(topic: session.topic))
        XCTAssertTrue(relayMock.didRespondSuccess)
    }
    
    func testUpdatePeerErrorAccountInvalid() {
        let session = WCSession.stub(isSelfController: false)
        storageMock.setSequence(session)
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateAccounts(topic: session.topic, accounts: ["0"]))
        XCTAssertFalse(relayMock.didRespondSuccess)
        XCTAssertEqual(relayMock.lastErrorCode, 1003)
    }
    
    func testUpdatePeerErrorNoSession() {
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateAccounts(topic: ""))
        XCTAssertFalse(relayMock.didRespondSuccess)
        XCTAssertEqual(relayMock.lastErrorCode, 1301)
    }

    func testUpdatePeerErrorUnauthorized() {
        let session = WCSession.stub(isSelfController: true) // Peer is not a controller
        storageMock.setSequence(session)
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateAccounts(topic: session.topic))
        XCTAssertFalse(relayMock.didRespondSuccess)
        XCTAssertEqual(relayMock.lastErrorCode, 3003)
    }
    
    // MARK: - Session Update expiry on updating client
    
    func testUpdateExpirySuccess() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: true, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let twoDays = 2*Time.day
        XCTAssertNoThrow(try engine.updateExpiry(topic: session.topic, by: Int64(twoDays)))
        let extendedSession = engine.getSettledSessions().first{$0.topic == session.topic}!
        XCTAssertEqual(extendedSession.expiryDate.timeIntervalSinceReferenceDate, TimeTraveler.dateByAdding(days: 2).timeIntervalSinceReferenceDate, accuracy: 1)
    }
    
    func testUpdateExpirySessionNotSettled() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: false, expiryDate: tomorrow, acknowledged: false)
        storageMock.setSequence(session)
        let twoDays = 2*Time.day
        XCTAssertThrowsError(try engine.updateExpiry(topic: session.topic, by: Int64(twoDays)))
    }
    
    func testUpdateExpiryOnNonControllerClient() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: false, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let twoDays = 2*Time.day
        XCTAssertThrowsError(try engine.updateExpiry(topic: session.topic, by: Int64(twoDays)))
    }
    
    func testUpdateExpiryTtlTooHigh() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: true, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let tenDays = 10*Time.day
        XCTAssertThrowsError(try engine.updateExpiry(topic: session.topic, by: Int64(tenDays)))
    }
    
    func testUpdateExpiryTtlTooLow() {
        let dayAfterTommorow = TimeTraveler.dateByAdding(days: 2)
        let session = WCSession.stub(isSelfController: true, expiryDate: dayAfterTommorow)
        storageMock.setSequence(session)
        let oneDay = Int64(1*Time.day)
        XCTAssertThrowsError(try engine.updateExpiry(topic: session.topic, by: oneDay))
    }
    
    //MARK: - Handle Session Extend call from peer
    
    func testPeerUpdateExpirySuccess() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: false, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let twoDaysFromNowTimestamp = Int64(TimeTraveler.dateByAdding(days: 2).timeIntervalSince1970)
        
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateExpiry(topic: session.topic, expiry: twoDaysFromNowTimestamp))
        let extendedSession = engine.getSettledSessions().first{$0.topic == session.topic}!
        print(extendedSession.expiryDate)
        
        XCTAssertEqual(extendedSession.expiryDate.timeIntervalSince1970, TimeTraveler.dateByAdding(days: 2).timeIntervalSince1970, accuracy: 1)
    }
    
    func testPeerUpdateExpiryUnauthorized() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: true, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let twoDaysFromNowTimestamp = Int64(TimeTraveler.dateByAdding(days: 2).timeIntervalSince1970)
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateExpiry(topic: session.topic, expiry: twoDaysFromNowTimestamp))
        let potentiallyExtendedSession = engine.getSettledSessions().first{$0.topic == session.topic}!
        XCTAssertEqual(potentiallyExtendedSession.expiryDate.timeIntervalSinceReferenceDate, tomorrow.timeIntervalSinceReferenceDate, accuracy: 1, "expiry date has been extended for peer non controller request ")
    }
    
    func testPeerUpdateExpiryTtlTooHigh() {
        let tomorrow = TimeTraveler.dateByAdding(days: 1)
        let session = WCSession.stub(isSelfController: false, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let tenDaysFromNowTimestamp = Int64(TimeTraveler.dateByAdding(days: 10).timeIntervalSince1970)
        
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateExpiry(topic: session.topic, expiry: tenDaysFromNowTimestamp))
        let potentaillyExtendedSession = engine.getSettledSessions().first{$0.topic == session.topic}!
        XCTAssertEqual(potentaillyExtendedSession.expiryDate.timeIntervalSinceReferenceDate, tomorrow.timeIntervalSinceReferenceDate, accuracy: 1, "expiry date has been extended despite ttl to high")
    }
    
    func testPeerUpdateExpiryTtlTooLow() {
        let tomorrow = TimeTraveler.dateByAdding(days: 2)
        let session = WCSession.stub(isSelfController: false, expiryDate: tomorrow)
        storageMock.setSequence(session)
        let oneDayFromNowTimestamp = Int64(TimeTraveler.dateByAdding(days: 10).timeIntervalSince1970)
        
        subscriberMock.onReceivePayload?(WCRequestSubscriptionPayload.stubUpdateExpiry(topic: session.topic, expiry: oneDayFromNowTimestamp))
        let potentaillyExtendedSession = engine.getSettledSessions().first{$0.topic == session.topic}!
        XCTAssertEqual(potentaillyExtendedSession.expiryDate.timeIntervalSinceReferenceDate, tomorrow.timeIntervalSinceReferenceDate, accuracy: 1, "expiry date has been extended despite ttl to low")
    }
    
    
    // TODO: Upgrade acknowledgement tests
}
