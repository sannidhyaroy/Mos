//
//  MouseGestureCapture.swift
//  Mos
//  录制期间的手势捕获 - 把用户在某个鼠标按钮上做的动作识别成 MouseGesture.
//
//  与运行时的 MouseGestureController 区别:
//  - 这里 "全手势布防" (任何手势都要能被识别出来), 因为录制时还不知道用户想绑哪个.
//  - 自带一个 listen-only 的 motion tap 用于拖拽方向判定 (录制 tap 是消费型的, 不能
//    用来观察移动, 否则会冻结指针).
//

import Cocoa

final class MouseGestureCapture {

    private let recognizer: MouseGestureRecognizer
    private let scheduler: GestureDeadlineScheduling = RealGestureDeadlineScheduler()
    private let now: () -> TimeInterval

    /// 识别完成回调 (主线程).
    var onRecognized: ((MouseGesture) -> Void)?

    private(set) var isActive = false
    private var motionInterceptor: Interceptor?
    private var scrollInterceptor: Interceptor?

    /// 录制时布防全部非单击手势, 任何动作都能被识别.
    private static let allGestures: Set<MouseGesture> = [
        .longPress, .doubleClick, .tripleClick,
        .dragUp, .dragDown, .dragLeft, .dragRight,
        .scrollUp, .scrollDown, .scrollLeft, .scrollRight,
    ]

    init(now: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.now = now
        let config = MouseGestureRecognizer.Config(armedGestures: Self.allGestures)
        self.recognizer = MouseGestureRecognizer(config: config)
        self.recognizer.onRecognize = { [weak self] gesture in
            self?.finish(gesture)
        }
    }

    // MARK: - 驱动

    /// 按下 (每次物理按下都要调用, 包括连击的第 2/3 次). location 为自然坐标 (y 向上).
    func down(at location: CGPoint) {
        if !isActive {
            isActive = true
            startMotionTap()
        }
        recognizer.handleDown(at: location, time: now())
        reschedule()
    }

    func up(at location: CGPoint) {
        guard isActive else { return }
        recognizer.handleUp(at: location, time: now())
        reschedule()
    }

    func move(to location: CGPoint) {
        guard isActive else { return }
        recognizer.handleMove(to: location, time: now())
        reschedule()
    }

    /// 滚轮滚动 (录制期间由 listen-only 滚动 tap 转发). dx/dy 为 CGEvent 原始 delta.
    func scroll(dx: CGFloat, dy: CGFloat) {
        guard isActive else { return }
        recognizer.handleScroll(dx: dx, dy: dy, time: now())
        reschedule()
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        recognizer.cancel()
        scheduler.cancel()
        stopMotionTap()
    }

    // MARK: - 内部

    private func reschedule() {
        guard isActive else { return }
        if let deadline = recognizer.pendingDeadline {
            scheduler.schedule(fireAt: deadline, now: now()) { [weak self] in
                guard let self = self, self.isActive else { return }
                self.recognizer.handleTimeout(time: self.now())
                self.reschedule()
            }
        } else {
            scheduler.cancel()
        }
    }

    private func finish(_ gesture: MouseGesture) {
        guard isActive else { return }
        isActive = false
        scheduler.cancel()
        stopMotionTap()
        onRecognized?(gesture)
    }

    // MARK: - 坐标
    static func naturalLocation(fromCGPoint cgPoint: CGPoint) -> CGPoint {
        let height = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: cgPoint.x, y: height - cgPoint.y)
    }

    // MARK: - listen-only motion tap (录制期间观察指针移动以判定拖拽方向)
    private static let motionEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))

    /// 当前活跃的捕获实例 (录制同一时刻只有一个). motion tap 回调通过它转发移动.
    private static weak var active: MouseGestureCapture?

    private static let motionCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        guard let capture = MouseGestureCapture.active else {
            return Unmanaged.passUnretained(event)
        }
        let location = MouseGestureCapture.naturalLocation(fromCGPoint: event.location)
        DispatchQueue.main.async {
            capture.move(to: location)
        }
        return Unmanaged.passUnretained(event)
    }

    private func startMotionTap() {
        guard motionInterceptor == nil else { return }
        Self.active = self
        do {
            let interceptor = try Interceptor(
                event: Self.motionEventMask,
                handleBy: Self.motionCallback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
            motionInterceptor = interceptor
        } catch {
            NSLog("MouseGestureCapture: failed to start motion tap: \(error)")
            motionInterceptor = nil
        }
        startScrollTap()
    }

    private func stopMotionTap() {
        if Self.active === self {
            Self.active = nil
        }
        motionInterceptor?.stop()
        motionInterceptor = nil
        stopScrollTap()
    }

    // MARK: - listen-only scroll tap (录制期间观察滚轮以判定滚轮手势方向)
    private static let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

    private static let scrollCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, let capture = MouseGestureCapture.active else {
            return Unmanaged.passUnretained(event)
        }
        let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        DispatchQueue.main.async {
            capture.scroll(dx: CGFloat(dx), dy: CGFloat(dy))
        }
        return Unmanaged.passUnretained(event)
    }

    private func startScrollTap() {
        guard scrollInterceptor == nil else { return }
        do {
            let interceptor = try Interceptor(
                event: Self.scrollEventMask,
                handleBy: Self.scrollCallback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
            scrollInterceptor = interceptor
        } catch {
            NSLog("MouseGestureCapture: failed to start scroll tap: \(error)")
            scrollInterceptor = nil
        }
    }

    private func stopScrollTap() {
        scrollInterceptor?.stop()
        scrollInterceptor = nil
    }
}
