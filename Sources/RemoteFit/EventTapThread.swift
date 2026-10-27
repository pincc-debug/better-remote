import Foundation

/// One dedicated thread + run loop for all input event taps, so a busy main
/// thread (AX calls, window listing, layout) can never delay system mouse input.
final class EventTapThread: Thread, @unchecked Sendable {
    static let shared: EventTapThread = {
        let thread = EventTapThread()
        thread.name = "local.RemoteFit.event-taps"
        thread.qualityOfService = .userInteractive
        thread.start()
        thread.ready.wait()
        return thread
    }()

    private let ready = DispatchSemaphore(value: 0)
    private(set) var runLoop: CFRunLoop!

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A source keeps the run loop alive before any tap is attached.
        var context = CFRunLoopSourceContext()
        let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
        CFRunLoopAddSource(runLoop, keepAlive, .commonModes)
        ready.signal()
        while !isCancelled { CFRunLoopRun() }
    }

    var isCurrent: Bool { Thread.current === self }

    /// Runs `block` on the tap thread without waiting.
    func async(_ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `block` on the tap thread and waits; only for short setup/teardown work.
    func sync<T>(_ block: @escaping () -> T) -> T {
        if isCurrent { return block() }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        nonisolated(unsafe) let work = block
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            result = work()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return result!
    }

    /// A one-shot or repeating timer on the tap thread's run loop.
    func timer(after interval: TimeInterval, repeats: Bool, _ fire: @escaping @Sendable () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in fire() }
        CFRunLoopAddTimer(runLoop, timer as CFRunLoopTimer, .commonModes)
        return timer
    }
}
