//
//  MouseGestureRecognizer.swift
//  Mos
//  纯函数式鼠标手势状态机 - 把一串 down/move/up/timeout 输入识别成 MouseGesture
//
//  设计原则:
//  - 完全确定性: 不持有真实 Timer, 不读系统时间. 所有时间由调用方以参数传入.
//    需要计时时, 通过 `pendingDeadline` 告诉宿主 "请在这个绝对时间点回调 handleTimeout".
//    这样可在单测里完全驱动, 无需异步等待.
//  - 只在 "有非单击手势被绑定" 时才需要它 (armedGestures 非空). 纯单击按钮走原有零延迟路径.
//  - 识别出的手势仅限 armedGestures 命中范围; 多击则按已绑定的最大次数判定上限.
//

import Cocoa

final class MouseGestureRecognizer {

    // MARK: - Config
    struct Config {
        /// 长按判定阈值 (按住多久算长按)
        var longPressDelay: TimeInterval
        /// 多击间隔上限 (两次点击间隔超过则不再视为连击)
        var multiClickInterval: TimeInterval
        /// 拖拽位移阈值 (移动超过多少点算拖拽)
        var dragDistance: CGFloat
        /// 该按钮当前绑定的非单击手势集合 (决定需要识别哪些手势 / 是否需要等待)
        var armedGestures: Set<MouseGesture>

        static let defaultLongPressDelay: TimeInterval = 0.35
        static let defaultMultiClickInterval: TimeInterval = 0.30
        static let defaultDragDistance: CGFloat = 10

        init(
            armedGestures: Set<MouseGesture>,
            longPressDelay: TimeInterval = Config.defaultLongPressDelay,
            multiClickInterval: TimeInterval = Config.defaultMultiClickInterval,
            dragDistance: CGFloat = Config.defaultDragDistance
        ) {
            self.armedGestures = armedGestures
            self.longPressDelay = longPressDelay
            self.multiClickInterval = multiClickInterval
            self.dragDistance = dragDistance
        }
    }

    // MARK: - State
    private enum Phase: Equatable {
        case idle
        /// 按钮按下中 (clickCount = 含本次在内的累计点击数)
        case pressed
        /// 抬起后等待是否还有下一次点击
        case waitingForNextClick
        /// 已在按住期间识别出手势 (长按/拖拽), 等待物理抬起以收尾, 不再产生点击
        case recognizedAwaitingRelease
    }

    private let config: Config
    private var phase: Phase = .idle
    private var clickCount = 0
    private var pressDownLocation: CGPoint = .zero

    /// 宿主需要安排的下一次 timeout 绝对时间 (nil = 不需要计时).
    /// 每次 handle* 之后读取, 用于 (重新)安排单个定时器.
    private(set) var pendingDeadline: TimeInterval?

    /// 识别出手势时回调 (宿主据此查绑定并执行).
    var onRecognize: ((MouseGesture) -> Void)?

    /// 当前是否处于一段未完成的识别过程 (宿主据此决定是否拦截后续事件).
    var isTracking: Bool { phase != .idle }

    init(config: Config) {
        self.config = config
    }

    // MARK: - 多击上限
    /// 已绑定手势里最大点击次数 (含基础单击 = 1).
    private var maxArmedClicks: Int {
        var maxClicks = 1
        if config.armedGestures.contains(.doubleClick) { maxClicks = max(maxClicks, 2) }
        if config.armedGestures.contains(.tripleClick) { maxClicks = max(maxClicks, 3) }
        return maxClicks
    }

    private var hasArmedMultiClick: Bool {
        config.armedGestures.contains(.doubleClick) || config.armedGestures.contains(.tripleClick)
    }

    private var hasArmedDrag: Bool {
        config.armedGestures.contains(where: { $0.isDrag })
    }

    private static func gesture(forClickCount count: Int) -> MouseGesture {
        switch count {
        case ..<2:  return .click
        case 2:     return .doubleClick
        default:    return .tripleClick   // 4+ 次封顶为三击
        }
    }

    // MARK: - 输入处理

    /// 按钮按下
    func handleDown(at location: CGPoint, time: TimeInterval) {
        switch phase {
        case .idle:
            clickCount = 1
        case .waitingForNextClick:
            clickCount += 1
        case .pressed, .recognizedAwaitingRelease:
            // 异常顺序 (没收到 up 又来 down): 重置后当作新的一次
            clickCount = 1
        }
        phase = .pressed
        pressDownLocation = location

        // 仅在首次按下且绑定了长按时安排长按计时.
        if clickCount == 1 && config.armedGestures.contains(.longPress) {
            pendingDeadline = time + config.longPressDelay
        } else {
            pendingDeadline = nil
        }
    }

    /// 按住期间指针移动
    func handleMove(to location: CGPoint, time: TimeInterval) {
        guard phase == .pressed, hasArmedDrag else { return }
        let dx = location.x - pressDownLocation.x
        let dy = location.y - pressDownLocation.y
        guard hypot(dx, dy) >= config.dragDistance else { return }

        let direction = MouseGesture.dragGesture(dx: dx, dy: dy)
        guard config.armedGestures.contains(direction) else {
            // 移动方向未绑定: 放弃手势识别, 转为等待物理抬起 (避免误判成点击)
            phase = .recognizedAwaitingRelease
            pendingDeadline = nil
            return
        }
        phase = .recognizedAwaitingRelease
        pendingDeadline = nil
        emit(direction)
    }

    /// 按钮抬起
    func handleUp(at location: CGPoint, time: TimeInterval) {
        switch phase {
        case .recognizedAwaitingRelease:
            reset()
        case .pressed:
            if hasArmedMultiClick && clickCount < maxArmedClicks {
                phase = .waitingForNextClick
                pendingDeadline = time + config.multiClickInterval
            } else {
                let recognized = Self.gesture(forClickCount: clickCount)
                emit(recognized)
                reset()
            }
        case .idle, .waitingForNextClick:
            break
        }
    }

    /// 计时器触发 (宿主在 pendingDeadline 时间点调用)
    func handleTimeout(time: TimeInterval) {
        switch phase {
        case .pressed:
            // 长按计时到点, 仍在按住 → 长按
            guard config.armedGestures.contains(.longPress) else {
                pendingDeadline = nil
                return
            }
            phase = .recognizedAwaitingRelease
            pendingDeadline = nil
            emit(.longPress)
        case .waitingForNextClick:
            // 连击窗口结束 → 按累计次数判定
            let recognized = Self.gesture(forClickCount: clickCount)
            emit(recognized)
            reset()
        case .idle, .recognizedAwaitingRelease:
            pendingDeadline = nil
        }
    }

    /// 强制结束 (如 tap 被系统禁用 / 绑定变更): 不产生任何手势.
    func cancel() {
        reset()
    }

    // MARK: - Helpers
    private func emit(_ gesture: MouseGesture) {
        onRecognize?(gesture)
    }

    private func reset() {
        phase = .idle
        clickCount = 0
        pendingDeadline = nil
    }
}
