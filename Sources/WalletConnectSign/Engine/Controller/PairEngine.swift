
import Foundation
import WalletConnectKMS

actor PairEngine {
    private let networkingInteractor: NetworkInteracting
    private let kms: KeyManagementServiceProtocol
    private let pairingStore: WCPairingStorage
    
    init(networkingInteractor: NetworkInteracting,
         kms: KeyManagementServiceProtocol,
         pairingStore: WCPairingStorage) {
        self.networkingInteractor = networkingInteractor
        self.kms = kms
        self.pairingStore = pairingStore
    }
    
    func pair(_ uri: WalletConnectURI) async throws {
        guard !hasPairing(for: uri.topic) else {
            throw WalletConnectError.pairingAlreadyExist
        }
//        guard debouncer.signal(uri) else { return }
        var pairing = WCPairing(uri: uri)
        try await networkingInteractor.subscribe(topic: pairing.topic)
        let symKey = try! SymmetricKey(hex: uri.symKey) // FIXME: Malformed QR code from external source can crash the SDK
        try! kms.setSymmetricKey(symKey, for: pairing.topic)
        pairing.activate()
        pairingStore.setPairing(pairing)
    }
    
    func hasPairing(for topic: String) -> Bool {
        return pairingStore.hasPairing(forTopic: topic)
    }
}

class Debouncer<T: Hashable> {
    
    typealias TimerProvider = (TimeInterval, Bool, @escaping (Timer) -> Void) -> Timer
    
    private(set) var debounced: Set<T> = []
    
    private let delay: TimeInterval
    
    private let queue: DispatchQueue
    
    private let timerProvider: TimerProvider
    
    init(delay: TimeInterval,
         queue: DispatchQueue = DispatchQueue(label: ""),
         timerProvider: @escaping TimerProvider = Timer.scheduledTimer) {
        self.delay = delay
        self.queue = queue
        self.timerProvider = timerProvider
    }
    
    func signal(_ value: T) -> Bool {
        queue.sync {
            if debounced.contains(value) {
                return false
            }
            debounced.insert(value)
            _ = timerProvider(delay, false) { [weak self] _ in
                self?.reset(value)
            }
            return true
        }
    }
    
    private func reset(_ value: T) {
        _ = queue.sync {
            debounced.remove(value)
        }
    }
}
