import Foundation
import WalletConnectKMS
import WalletConnectUtils
import Combine

class InviteService {
    private var publishers = [AnyCancellable]()
    let networkingInteractor: NetworkInteracting
    let logger: ConsoleLogging
    let kms: KeyManagementService

    var onNewThread: ((String) -> Void)?
    var onInvite: ((Invite) -> Void)?

    init(networkingInteractor: NetworkInteracting,
         kms: KeyManagementService,
         logger: ConsoleLogging) {
        self.kms = kms
        self.networkingInteractor = networkingInteractor
        self.logger = logger
        setUpResponseHandling()
    }

    func invite(peerPubKey: String, openingMessage: String, account: Account) async throws {
        print("💄peer pub key from registry \(peerPubKey)")
        let selfPubKeyY = try kms.createX25519KeyPair()
        let invite = Invite(message: openingMessage, account: account, pubKey: selfPubKeyY.hexRepresentation)
        let symKeyI = try kms.performKeyAgreement(selfPublicKey: selfPubKeyY, peerPublicKey: peerPubKey)
        let inviteTopic = try AgreementPublicKey(hex: peerPubKey).rawRepresentation.sha256().toHexString()
        try kms.setSymmetricKey(symKeyI.sharedKey, for: inviteTopic)

        print("💄 - agreement pubkey - \(selfPubKeyY.hexRepresentation)")
        print("inviter sym key \(symKeyI.sharedKey.hexRepresentation)")

        let request = JSONRPCRequest<ChatRequestParams>(params: .invite(invite))

        // 2. Proposer subscribes to topic R which is the hash of the derived symKey
        let responseTopic = symKeyI.derivedTopic()

        try kms.setSymmetricKey(symKeyI.sharedKey, for: responseTopic)

        try await networkingInteractor.subscribe(topic: responseTopic)

        try await networkingInteractor.request(request, topic: inviteTopic, envelopeType: .type1(pubKey: selfPubKeyY.rawRepresentation))

        logger.debug("invite sent on topic: \(inviteTopic)")
    }

    private func setUpResponseHandling() {
        networkingInteractor.responsePublisher
            .sink { [unowned self] response in
                switch response.requestParams {
                case .invite:
                    handleInviteResponse(response)
                default:
                    return
                }
            }.store(in: &publishers)
    }

    private func handleInviteResponse(_ response: ChatResponse) {
        switch response.result {
        case .response(let jsonrpc):
            do {
                let inviteResponse = try jsonrpc.result.get(InviteResponse.self)
                logger.debug("Invite has been accepted")
                guard case .invite(let inviteParams) = response.requestParams else { return }
                Task { try await createThread(selfPubKeyHex: inviteParams.pubKey, peerPubKey: inviteResponse.pubKey)}
            } catch {
                logger.debug("Handling invite response has failed")
            }
        case .error:
            logger.debug("Invite has been rejected")
            // TODO - remove keys, clean storage
        }
    }

    private func createThread(selfPubKeyHex: String, peerPubKey: String) async throws {
        let selfPubKey = try AgreementPublicKey(hex: selfPubKeyHex)
        let agreementKeys = try kms.performKeyAgreement(selfPublicKey: selfPubKey, peerPublicKey: peerPubKey)
        let threadTopic = agreementKeys.derivedTopic()
        try await networkingInteractor.subscribe(topic: threadTopic)
        onNewThread?(threadTopic)
        // TODO - remove symKeyI
    }
}
