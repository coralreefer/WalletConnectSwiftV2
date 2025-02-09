import Foundation
import WalletConnectKMS

protocol SocketAuthenticating {
    func createAuthToken() throws -> String
}

struct SocketAuthenticator: SocketAuthenticating {
    private let clientIdStorage: ClientIdStoring
    private let didKeyFactory: DIDKeyFactory
    private let relayHost: String

    init(clientIdStorage: ClientIdStoring, didKeyFactory: DIDKeyFactory, relayHost: String) {
        self.clientIdStorage = clientIdStorage
        self.didKeyFactory = didKeyFactory
        self.relayHost = relayHost
    }

    func createAuthToken() throws -> String {
        let clientIdKeyPair = try clientIdStorage.getOrCreateKeyPair()
        let subject = generateSubject()
        return try createAndSignJWT(subject: subject, keyPair: clientIdKeyPair)
    }

    private func createAndSignJWT(subject: String, keyPair: SigningPrivateKey) throws -> String {
        let issuer = didKeyFactory.make(pubKey: keyPair.publicKey.rawRepresentation, prefix: true)
        let claims = JWT.Claims(iss: issuer, sub: subject, aud: getAudience(), iat: Date(), exp: getExpiry())
        var jwt = JWT(claims: claims)
        try jwt.sign(using: EdDSASigner(keyPair))
        return try jwt.encoded()
    }

    private func generateSubject() -> String {
        return Data.randomBytes(count: 32).toHexString()
    }

    private func getExpiry() -> Date {
        var components = DateComponents()
        components.setValue(1, for: .day)
        // safe to unwrap as the date must be calculated
        return Calendar.current.date(byAdding: components, to: Date())!
    }

    private func getAudience() -> String {
        return "wss://\(relayHost)"
    }
}
