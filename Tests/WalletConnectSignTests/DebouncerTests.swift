import XCTest
@testable import WalletConnectSign

final class DebouncerTests: XCTestCase {
    
    var debouncer: Debouncer<Int>!
    var trigger: TimerTrigger!
    
    override func setUp() {
        trigger = TimerTrigger()
        debouncer = Debouncer(delay: 99, timerProvider: trigger.scheduledTimer)
    }
    
    override func tearDown() {
        trigger.timer?.invalidate()
        debouncer = nil
        trigger = nil
    }
    
    func testDebouncerAllowDifferentValues() {
        XCTAssertTrue(debouncer.signal(0))
        XCTAssertTrue(debouncer.signal(1))
    }
    
    func testDebouncerBlockSameValues() {
        XCTAssertTrue(debouncer.signal(0))
        XCTAssertFalse(debouncer.signal(0))
    }
    
    func testDebouncerResetAfterDelay() {
        _ = debouncer.signal(0)
        trigger.fire()
        XCTAssertTrue(debouncer.signal(0))
    }
    
    func testConcurrentDebounce() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = debouncer.signal(0)
        }
        XCTAssertEqual(debouncer.debounced.count, 1)
    }
    
    func testConcurrentDebouncePassthroughMix() {
        let allowCount = Int.random(in: 1...10)
        DispatchQueue.concurrentPerform(iterations: 100) {
            _ = debouncer.signal($0 % allowCount)
        }
        XCTAssertEqual(debouncer.debounced.count, allowCount)
    }
    
    func testConcurrentPassthrough() {
        DispatchQueue.concurrentPerform(iterations: 100) {
            _ = debouncer.signal($0)
        }
        XCTAssertEqual(debouncer.debounced.count, 100)
    }
}
