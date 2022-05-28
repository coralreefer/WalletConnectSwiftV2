import Foundation

final class TimerTrigger {
    
    private(set) var timer: Timer?
    
    func scheduledTimer(withInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        self.timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: block)
        self.timer = timer
        return timer
    }
    
    func fire() {
        timer?.fire()
    }
}
