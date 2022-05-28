import Foundation

final class Debouncer<T: Hashable> {
    
    typealias TimerProvider = (TimeInterval, Bool, @escaping (Timer) -> Void) -> Timer
    
    private(set) var debounced: Set<T> = []
    
    private let delay: TimeInterval
    private let timerProvider: TimerProvider
    private let queue = DispatchQueue(label: "")
    
    init(delay: TimeInterval, timerProvider: @escaping TimerProvider = Timer.scheduledTimer) {
        self.delay = delay
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
