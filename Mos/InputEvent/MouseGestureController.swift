//
//  MouseGestureController.swift
//  Mos
//  鼠标手势运行时协调器 - 把物理按钮的 down/up/move 喂给 MouseGestureRecognizer,
//  识别出手势后查绑定并执行; 未命中的普通单击则重放原始物理点击 (不吞输入).
//
//  关键约束:
//  - 仅当该按钮 (按当前修饰键) 命中了至少一个非单击手势绑定时才介入;
//    否则 InputProcessor 走原有零延迟单击路径, 现有行为完全不变.
//  - 计时与执行通过可注入闭包暴露, 单测可完全确定性地驱动 (无需真实 Timer / 真实 tap).
//

import Cocoa

// MARK: - 计时器抽象 (可注入, 便于测试)
protocol GestureDeadlineScheduling: AnyObject {
    /// 安排在 `fireAt` 绝对时间触发 (相对 now 的延迟), 覆盖之前的安排.
    func schedule(fireAt: TimeInterval, now: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

/// 默认实现: 主 RunLoop Timer.
final class RealGestureDeadlineScheduler: GestureDeadlineScheduling {
    private var timer: Timer?

    func schedule(fireAt: TimeInterval, now: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let delay = max(0, fireAt - now)
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - MouseGestureController
final class MouseGestureController {

    static let shared = MouseGestureController()

    // MARK: 可注入 Seams
    /// 当前时间 (单调时钟), 测试可替换.
    var nowProvider: () -> TimeInterval = { CACurrentMediaTime() }
    /// 计时器工厂.
    var schedulerFactory: () -> GestureDeadlineScheduling = { RealGestureDeadlineScheduler() }
    /// 执行某条绑定的动作 (以一次 down+up tap 形式).
    var actionExecutor: (ButtonBinding, InputEvent) -> Void = MouseGestureController.defaultExecute
    /// 重放原始物理点击 (普通单击未命中绑定时, 不吞输入).
    var clickReplayer: (InputEvent) -> Void = MouseGestureController.defaultReplay
    /// 启用 / 停用 物理拖拽的 motion 观察.
    lazy var motionTracking: (Bool) -> Void = { [weak self] active in
        self?.setRealMotionTapActive(active)
    }

    // MARK: 手势阈值
    var longPressDelay = MouseGestureRecognizer.Config.defaultLongPressDelay
    var multiClickInterval = MouseGestureRecognizer.Config.defaultMultiClickInterval
    var dragDistance = MouseGestureRecognizer.Config.defaultDragDistance

    // MARK: 会话
    private final class Session {
        let recognizer: MouseGestureRecognizer
        let originalDown: InputEvent
        let scheduler: GestureDeadlineScheduling
        let dragArmed: Bool
        init(recognizer: MouseGestureRecognizer, originalDown: InputEvent,
             scheduler: GestureDeadlineScheduling, dragArmed: Bool) {
            self.recognizer = recognizer
            self.originalDown = originalDown
            self.scheduler = scheduler
            self.dragArmed = dragArmed
        }
    }

    private var sessions: [UInt16: Session] = [:]

    /// 是否有按钮正处于手势识别中 (供 InputProcessor 路由 up 事件).
    func isTracking(code: UInt16) -> Bool {
        return sessions[code] != nil
    }

    var hasActiveSessions: Bool { !sessions.isEmpty }

    private var motionInterceptor: Interceptor?

    // MARK: - 入口

    /// 处理鼠标按下. 返回是否进入手势识别 (true = 已 consume, InputProcessor 不再走单击路径).
    func handleDown(_ event: InputEvent) -> Bool {
        // 连击的后续按下: 继续喂给已有识别器, 不重建会话 (否则会丢失点击计数).
        if let session = sessions[event.code] {
            session.recognizer.handleDown(at: naturalLocation(for: event), time: nowProvider())
            rescheduleOrCleanup(code: event.code)
            return true
        }

        let armed = ButtonUtils.shared.armedNonClickGestures(for: event)
        guard !armed.isEmpty else { return false }

        let dragArmed = armed.contains(where: { $0.isDrag })
        let config = MouseGestureRecognizer.Config(
            armedGestures: armed,
            longPressDelay: longPressDelay,
            multiClickInterval: multiClickInterval,
            dragDistance: dragDistance
        )
        let recognizer = MouseGestureRecognizer(config: config)
        let session = Session(
            recognizer: recognizer,
            originalDown: event,
            scheduler: schedulerFactory(),
            dragArmed: dragArmed
        )
        let code = event.code
        // weak session: 否则 session -> recognizer -> onRecognize -> session 形成循环引用.
        recognizer.onRecognize = { [weak self, weak session] gesture in
            guard let session = session else { return }
            self?.dispatch(gesture, for: session, code: code)
        }
        sessions[code] = session

        recognizer.handleDown(at: naturalLocation(for: event), time: nowProvider())
        rescheduleOrCleanup(code: code)
        updateMotionTracking()
        return true
    }

    /// 处理鼠标抬起. 返回是否被手势会话消费.
    func handleUp(_ event: InputEvent) -> Bool {
        guard let session = sessions[event.code] else { return false }
        session.recognizer.handleUp(at: naturalLocation(for: event), time: nowProvider())
        rescheduleOrCleanup(code: event.code)
        return true
    }

    /// 处理物理拖拽 (motion tap 转发, code 来自当前按住的按钮号).
    func handleMove(toCGLocation cgLocation: CGPoint) {
        guard !sessions.isEmpty else { return }
        let location = naturalLocation(fromCGPoint: cgLocation)
        let now = nowProvider()
        for code in Array(sessions.keys) {
            guard let session = sessions[code], session.dragArmed else { continue }
            session.recognizer.handleMove(to: location, time: now)
            rescheduleOrCleanup(code: code)
        }
    }

    /// tap 失效 / 绑定变更 / 禁用时强制清空, 不产生手势.
    func cancelAll() {
        for session in sessions.values {
            session.recognizer.cancel()
            session.scheduler.cancel()
        }
        sessions.removeAll()
        updateMotionTracking()
    }

    // MARK: - 内部

    private func dispatch(_ gesture: MouseGesture, for session: Session, code: UInt16) {
        if let binding = ButtonUtils.shared.getBestMatchingBinding(for: session.originalDown, gesture: gesture) {
            actionExecutor(binding, session.originalDown)
        } else if gesture == .click {
            // 普通单击但没有单击绑定: 重放原始点击, 不吞用户输入.
            clickReplayer(session.originalDown)
        }
        // 其他无匹配的非单击手势: 吞掉 (用户做了该手势但未绑定该修饰键组合).
    }

    private func rescheduleOrCleanup(code: UInt16) {
        guard let session = sessions[code] else { return }
        if let deadline = session.recognizer.pendingDeadline {
            session.scheduler.schedule(fireAt: deadline, now: nowProvider()) { [weak self] in
                self?.timeoutFired(code: code)
            }
            return
        }
        // 无待定计时:
        if session.recognizer.isTracking {
            // 仍在识别中 (按住但未到长按 / 等待拖拽), 保持会话, 取消计时.
            session.scheduler.cancel()
        } else {
            // 序列结束.
            session.scheduler.cancel()
            sessions[code] = nil
            updateMotionTracking()
        }
    }

    private func timeoutFired(code: UInt16) {
        guard let session = sessions[code] else { return }
        session.recognizer.handleTimeout(time: nowProvider())
        rescheduleOrCleanup(code: code)
    }

    private func updateMotionTracking() {
        let needsMotion = sessions.values.contains(where: { $0.dragArmed })
        motionTracking(needsMotion)
    }

    // MARK: - 坐标 (统一为 y 向上的自然坐标)
    private func naturalLocation(for event: InputEvent) -> CGPoint {
        if case .cgEvent(let cgEvent) = event.source {
            return naturalLocation(fromCGPoint: cgEvent.location)
        }
        return NSEvent.mouseLocation
    }

    private func naturalLocation(fromCGPoint cgPoint: CGPoint) -> CGPoint {
        let height = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: cgPoint.x, y: height - cgPoint.y)
    }

    // MARK: - 默认执行 / 重放
    private static func defaultExecute(binding: ButtonBinding, event: InputEvent) {
        var resolved = binding
        resolved.prepareCustomCache()
        guard let action = ShortcutExecutor.shared.resolveAction(
            named: resolved.systemShortcutName,
            binding: resolved
        ) else { return }
        _ = ShortcutExecutor.shared.execute(action: action, phase: .down, inputModifiers: event.modifiers)
        _ = ShortcutExecutor.shared.execute(action: action, phase: .up, inputModifiers: event.modifiers)
    }

    private static func defaultReplay(event: InputEvent) {
        guard let context = ShortcutExecutor.shared.mouseTapReplayContext(for: event) else { return }
        ShortcutExecutor.shared.replayMouseTap(context)
    }

    // MARK: - 物理拖拽 motion tap (需真机验证)
    private static let motionEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))

    private static let motionCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MouseGestureController.shared.cancelAll()
            return Unmanaged.passUnretained(event)
        }
        MouseGestureController.shared.handleMove(toCGLocation: event.location)
        return Unmanaged.passUnretained(event)
    }

    private func setRealMotionTapActive(_ active: Bool) {
        if active {
            guard motionInterceptor == nil else { return }
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
                NSLog("MouseGestureController: failed to start motion tap: \(error)")
                motionInterceptor = nil
            }
        } else {
            motionInterceptor?.stop()
            motionInterceptor = nil
        }
    }
}
