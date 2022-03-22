import XCTest
@testable import WalletConnect
@testable import TestingUtils
@testable import WalletConnectKMS
import WalletConnectUtils

func deriveTopic(publicKey: String, privateKey: AgreementPrivateKey) -> String {
    try! KeyManagementService.generateAgreementSecret(from: privateKey, peerPublicKey: publicKey).derivedTopic()
}

final class PairingEngineTests: XCTestCase {
    
    var engine: PairingEngine!
    
    var relayMock: MockedWCRelay!
    var subscriberMock: MockedSubscriber!
    var storageMock: PairingSequenceStorageMock!
    var cryptoMock: KeyManagementServiceMock!
    var proposalPayloadsStore: KeyValueStore<WCRequestSubscriptionPayload>!
    
    var topicGenerator: TopicGenerator!
    
    override func setUp() {
        relayMock = MockedWCRelay()
        subscriberMock = MockedSubscriber()
        storageMock = PairingSequenceStorageMock()
        cryptoMock = KeyManagementServiceMock()
        topicGenerator = TopicGenerator()
        proposalPayloadsStore = KeyValueStore<WCRequestSubscriptionPayload>(defaults: RuntimeKeyValueStorage(), identifier: "")
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
        let meta = AppMetadata.stub()
        let logger = ConsoleLoggerMock()
        engine = PairingEngine(
            relay: relayMock,
            kms: cryptoMock,
            subscriber: subscriberMock,
            sequencesStore: storageMock,
            metadata: meta,
            logger: logger,
            topicGenerator: topicGenerator.getTopic,
            proposalPayloadsStore: proposalPayloadsStore)
    }
    
    func testPairMultipleTimesOnSameURIThrows() {
        let uri = WalletConnectURI.stub()
        for i in 1...10 {
            if i == 1 {
                XCTAssertNoThrow(try engine.pair(uri))
            } else {
                XCTAssertThrowsError(try engine.pair(uri))
            }
        }
    }
    
    func testCreate() {
        let uri = engine.create()!
        XCTAssert(cryptoMock.hasSymmetricKey(for: uri.topic), "Proposer must store the symmetric key matching the URI.")
        XCTAssert(storageMock.hasSequence(forTopic: uri.topic), "The engine must store a pairing after creating one")
        XCTAssert(subscriberMock.didSubscribe(to: uri.topic), "Proposer must subscribe to pairing topic.")
        XCTAssert(storageMock.getSequence(forTopic: uri.topic)?.isActive == false, "Recently created pairing must be inactive.")
    }
    
    func testPair() {
        let uri = WalletConnectURI.stub()
        let topic = uri.topic
        try! engine.pair(uri)
        XCTAssert(subscriberMock.didSubscribe(to: topic), "Responder must subscribe to pairing topic.")
        XCTAssert(cryptoMock.hasSymmetricKey(for: topic), "Responder must store the symmetric key matching the pairing topic")
        XCTAssert(storageMock.hasSequence(forTopic: topic), "The engine must store a pairing")
    }
    
    func testPropose() {
        let pairing = Pairing.stub()
        let topicA = pairing.topic
        let permissions = SessionPermissions.stub()
        let relayOptions = RelayProtocolOptions(protocol: "", data: nil)
        
        engine.propose(pairingTopic: pairing.topic, permissions: permissions, blockchains: [], relay: relayOptions) {_ in}
        
        guard let publishTopic = relayMock.requests.first?.topic,
              let proposal = relayMock.requests.first?.request.sessionProposal else {
                  XCTFail("Proposer must publish a proposal request."); return
              }
        XCTAssert(cryptoMock.hasPrivateKey(for: proposal.proposer.publicKey), "Proposer must store the private key matching the public key sent through the proposal.")
        //        XCTAssert(storageMock.hasProposal(on: topicA), "The engine must store a proposal ")
        XCTAssertEqual(publishTopic, topicA)
    }
    
    func testReceiveProposal() {
        let pairing = Pairing.stub()
        let topicA = pairing.topic
        var sessionProposed = false
        let proposerPubKey = AgreementPrivateKey().publicKey.hexRepresentation
        let proposal = SessionProposal.stub(proposerPubKey: proposerPubKey)
        let request = WCRequest(method: .sessionPropose, params: .sessionPropose(proposal))
        let payload = WCRequestSubscriptionPayload(topic: topicA, wcRequest: request)
        engine.onSessionProposal = { _ in
            sessionProposed = true
        }
        subscriberMock.onReceivePayload?(payload)
        XCTAssertNotNil(try! proposalPayloadsStore.get(key: proposal.proposer.publicKey), "Proposer must store proposal payload")
        XCTAssertTrue(sessionProposed)
    }
    
    func testRespondProposal() {
        // Client receives a proposal
        let topicA = String.generateTopic()
        let proposerPubKey = AgreementPrivateKey().publicKey.hexRepresentation
        let proposal = SessionProposal.stub(proposerPubKey: proposerPubKey)
        let request = WCRequest(method: .sessionPropose, params: .sessionPropose(proposal))
        let payload = WCRequestSubscriptionPayload(topic: topicA, wcRequest: request)
        subscriberMock.onReceivePayload?(payload)
        
        let topicB = engine.respondSessionPropose(proposal: proposal)!
        
        XCTAssert(cryptoMock.hasAgreementSecret(for: topicB), "Responder must store agreement key for topic B")
        XCTAssertEqual(relayMock.didRespondOnTopic!, topicA, "Responder must respond on topic A")
    }
    
    func testHandleSessionProposeResponse() {
        let uri = engine.create()!
        let pairing = storageMock.getSequence(forTopic: uri.topic)!
        let topicA = pairing.topic
        let permissions = SessionPermissions.stub()
        let relayOptions = RelayProtocolOptions(protocol: "", data: nil)
        
        // Client proposes session
        engine.propose(pairingTopic: pairing.topic, permissions: permissions, blockchains: [], relay: relayOptions){_ in}
        
        guard let request = relayMock.requests.first?.request,
              let proposal = relayMock.requests.first?.request.sessionProposal else {
                  XCTFail("Proposer must publish session proposal request"); return
              }
        
        // Client receives proposal response response
        let responder = AgreementPeer.stub()
        let proposalResponse = SessionType.ProposeResponse(relay: relayOptions, responder: responder)
        
        let jsonRpcResponse = JSONRPCResponse<AnyCodable>(id: request.id, result: AnyCodable.decoded(proposalResponse))
        let response = WCResponse(topic: topicA,
                                  chainId: nil,
                                  requestMethod: request.method,
                                  requestParams: request.params,
                                  result: .response(jsonRpcResponse))
        
        var sessionTopic: String!
        
        engine.onProposeResponse = { topic in
            sessionTopic = topic
        }
        relayMock.onPairingResponse?(response)
        let privateKey = try! cryptoMock.getPrivateKey(for: proposal.proposer.publicKey)!
        let topicB = deriveTopic(publicKey: responder.publicKey, privateKey: privateKey)
        
        let storedPairing = storageMock.getSequence(forTopic: topicA)!

        XCTAssert(storedPairing.isActive)
        XCTAssertEqual(topicB, sessionTopic, "Responder engine calls back with session topic")
    }
    
    func testSessionProposeError() {
        let uri = engine.create()!
        let pairing = storageMock.getSequence(forTopic: uri.topic)!
        let topicA = pairing.topic
        let permissions = SessionPermissions.stub()
        let relayOptions = RelayProtocolOptions(protocol: "", data: nil)
        
        // Client propose session
        engine.propose(pairingTopic: pairing.topic, permissions: permissions, blockchains: [], relay: relayOptions){_ in}
        
        guard let request = relayMock.requests.first?.request,
              let proposal = relayMock.requests.first?.request.sessionProposal else {
                  XCTFail("Proposer must publish session proposal request"); return
              }
        
        let response = WCResponse.stubError(forRequest: request, topic: topicA)
        relayMock.onPairingResponse?(response)
        
        XCTAssert(subscriberMock.didUnsubscribe(to: pairing.topic), "Proposer must not unsubscribe if pairing is inactive.")
        XCTAssertFalse(storageMock.hasSequence(forTopic: pairing.topic), "Proposer must not delete an active pairing.")
        XCTAssertFalse(cryptoMock.hasSymmetricKey(for: pairing.topic), "Proposer must not delete symmetric key if pairing is inactive.")
        XCTAssertFalse(cryptoMock.hasPrivateKey(for: proposal.proposer.publicKey), "Proposer must remove private key for rejected session")
    }
    
    func testSessionProposeErrorOnActivePairing() {
        let uri = engine.create()!
        let pairing = storageMock.getSequence(forTopic: uri.topic)!
        let topicA = pairing.topic
        let permissions = SessionPermissions.stub()
        let relayOptions = RelayProtocolOptions(protocol: "", data: nil)
        
        // Client propose session
        engine.propose(pairingTopic: pairing.topic, permissions: permissions, blockchains: [], relay: relayOptions){_ in}
        
        guard let request = relayMock.requests.first?.request,
              let proposal = relayMock.requests.first?.request.sessionProposal else {
                  XCTFail("Proposer must publish session proposal request"); return
              }
        
        var storedPairing = storageMock.getSequence(forTopic: topicA)!
        storedPairing.activate()
        storageMock.setSequence(storedPairing)
        
        let response = WCResponse.stubError(forRequest: request, topic: topicA)
        relayMock.onPairingResponse?(response)
        
        XCTAssertFalse(subscriberMock.didUnsubscribe(to: pairing.topic), "Proposer must not unsubscribe if pairing is active.")
        XCTAssert(storageMock.hasSequence(forTopic: pairing.topic), "Proposer must not delete an active pairing.")
        XCTAssert(cryptoMock.hasSymmetricKey(for: pairing.topic), "Proposer must not delete symmetric key if pairing is active.")
        XCTAssertFalse(cryptoMock.hasPrivateKey(for: proposal.proposer.publicKey), "Proposer must remove private key for rejected session")
    }
    
    func testExtendPairingExpiryOnProposeResponse() {
        
    }
    
    func testPairingExpiration() {
        let uri = engine.create()!
        let pairing = storageMock.getSequence(forTopic: uri.topic)!
        storageMock.onSequenceExpiration?(pairing)
        XCTAssertFalse(cryptoMock.hasSymmetricKey(for: uri.topic))
        XCTAssert(subscriberMock.didUnsubscribe(to: uri.topic))
    }
}
