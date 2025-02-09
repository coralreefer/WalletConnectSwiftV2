import Foundation

extension JWT {
    struct Claims: Codable, Equatable {
        let iss: String
        let sub: String
        let aud: String
        let iat: Date
        let exp: Date

        func encode() throws -> String {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.dateEncodingStrategy = .secondsSince1970
            let data = try jsonEncoder.encode(self)
            return JWTEncoder.base64urlEncodedString(data: data)
        }
    }
}
