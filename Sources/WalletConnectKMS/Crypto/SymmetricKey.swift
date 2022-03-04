
import Foundation
import CryptoKit

public protocol SymmetricRepresentable {
    var symmetricRepresentation: Data {get}
    var pub: Data {get}
}

public struct SymmetricKey: Equatable {
    
    private let key: CryptoKit.SymmetricKey
    
    public var hexRepresentation: String {
        rawRepresentation.toHexString()
    }

    public init(size: Size = .bits256) {
        switch size {
        case .bits256:
            self.key = CryptoKit.SymmetricKey(size: SymmetricKeySize.bits256)
        }
    }
    
    public init(hex: String) throws {
        let data = Data(hex: hex)
        try self.init(rawRepresentation: data)
    }

}

extension SymmetricKey: GenericPasswordConvertible {
    
    public var rawRepresentation: Data {
        key.withUnsafeBytes {Data(Array($0))}
    }
    
    public init<D>(rawRepresentation data: D) throws where D : ContiguousBytes {
        self.key = CryptoKit.SymmetricKey(data: data)
    }
}

extension SymmetricKey: SymmetricRepresentable {
    public var pub: Data {
        return symmetricRepresentation.sha256()
    }
    
    
    public var symmetricRepresentation: Data {
        return rawRepresentation
    }
}

extension SymmetricKey {
    public enum Size {
        case bits256
    }
}