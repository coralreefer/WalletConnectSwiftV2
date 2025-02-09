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
    var onInvite: ((InviteParams) -> Void)?

    init(networkingInteractor: NetworkInteracting,
         kms: KeyManagementService,
         logger: ConsoleLogging) {
        self.kms = kms
        self.networkingInteractor = networkingInteractor
        self.logger = logger
        setUpResponseHandling()
    }

    func invite(peerPubKey: String, openingMessage: String, account: Account) async throws {
        let selfPubKeyY = try kms.createX25519KeyPair()
        let invite = Invite(message: openingMessage, account: account)
        let peerPublicKeyRaw = Data(hex: peerPubKey)
        let symKeyI = try kms.performKeyAgreement(selfPublicKey: selfPubKeyY, peerPublicKey: peerPubKey)
        let inviteTopic = try AgreementPublicKey(hex: peerPubKey).rawRepresentation.sha256().toHexString()

        try kms.setSymmetricKey(symKeyI.sharedKey, for: inviteTopic)

        let inviteRequestParams = InviteParams(pubKey: selfPubKeyY.hexRepresentation, invite: invite)

        let request = JSONRPCRequest<ChatRequestParams>(params: .invite(inviteRequestParams))

        try await networkingInteractor.subscribe(topic: inviteTopic)

        try await networkingInteractor.request(request, topic: inviteTopic, envelopeType: .type1(pubKey: peerPublicKeyRaw))

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
