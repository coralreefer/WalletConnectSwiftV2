import XCTest
@testable import WalletConnectSign
//@testable import TestingUtils

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


final class DebouncerTests: XCTestCase {
    
    var trigger: TimerTrigger!
    
    override func setUp() {
        let trigger = TimerTrigger()
    }
    
    func testDebounce() {
        let debouncer = Debouncer<Int>(delay: 0)
        XCTAssertTrue(debouncer.signal(0))
    }
    
    func testDifferentValuesPassthrough() {
        let debouncer = Debouncer<Int>(delay: 0)
        XCTAssertTrue(debouncer.signal(0))
        XCTAssertTrue(debouncer.signal(1))
    }
    
    func testSignalSameValueDebounce() {
        let debouncer = Debouncer<Int>(delay: 0)
        _ = debouncer.signal(0)
        XCTAssertFalse(debouncer.signal(0))
    }
    
    func testSignalDebounceResetAfterDelay() {
        let trigger = TimerTrigger()
        let debouncer = Debouncer<Int>(delay: 1, timerProvider: trigger.scheduledTimer)
        _ = debouncer.signal(0)
        trigger.fire()
        XCTAssertTrue(debouncer.signal(0))
    }
    
    func testConcurrentDebounce() {
        let debouncer = Debouncer<Int>(delay: 0)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = debouncer.signal(0)
        }
        XCTAssertEqual(debouncer.debounced.count, 1)
    }
    
    func testConcurrentDebouncePassthroughMix() {
        let debouncer = Debouncer<Int>(delay: 1)
        let allowCount = Int.random(in: 1...10)
        DispatchQueue.concurrentPerform(iterations: 100) {
            _ = debouncer.signal($0 % allowCount)
        }
        XCTAssertEqual(debouncer.debounced.count, allowCount)
    }
    
    func testConcurrentPassthrough() {
        let debouncer = Debouncer<Int>(delay: 1)
        DispatchQueue.concurrentPerform(iterations: 100) {
            _ = debouncer.signal($0)
        }
        XCTAssertEqual(debouncer.debounced.count, 100)
    }
    
//    func testC() async {
//        let q = DispatchQueue(label: "t")
//        var sut: Debouncer! = Debouncer(queue: q)
//        weak var ref = sut
//        let uri = WalletConnectURI.stub()
//
//        await sut.debounce("aaa", block: pair(uri))
//        await sut.debounce("aaa", block: pair(uri))
//        await sut.debounce("aaa", block: pair(uri))
//        q.sync {
////            XCTAssert(sut.debounced.count == 0)
//            print("end")
//        }
//        XCTAssert(sut.debounced.count == 0)
//        sut = nil
//        XCTAssertNil(ref)
//    }
//
//    func testD() {
//        let q = DispatchQueue(label: "t")
//        let sut = Debouncer(queue: q)
//        let uri = WalletConnectURI.stub()
//
//        DispatchQueue.concurrentPerform(iterations: 100) { i in
//            Task {
//                await sut.debounce("aaa\(i)", block: pair(uri))
//            }
//        }
//    }
//
//    func pair(_ uri: WalletConnectURI) {
//        print("PAIR CALL: \(uri.absoluteString)")
//    }
}
