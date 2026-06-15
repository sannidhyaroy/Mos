//
//  MouseGesture.swift
//  Mos
//  鼠标手势模型 - 描述一个按钮触发器附带的手势类型
//  (单击 / 长按 / 双击 / 三击 / 四方向拖拽)
//
//  设计要点:
//  - rawValue 是稳定字符串, 直接进入持久化 JSON (canary 友好, 不要随意改).
//  - `.click` 是默认值, 旧配置 (没有 gesture 字段) 一律视为 `.click`, 保证向后兼容.
//  - 主键 (左/右键) 不允许任何手势绑定, 避免用户把基础功能锁死.
//

import Cocoa

// MARK: - MouseGesture
/// 鼠标手势类型
///
/// 注意: rawValue 进入持久化, 修改即破坏旧配置. 新增手势只追加, 不要重命名已有 case.
enum MouseGesture: String, Codable, Equatable, CaseIterable {
    /// 普通单击 (按下即触发, 与历史行为一致)
    case click
    /// 长按 (按住超过阈值不松开)
    case longPress
    /// 双击
    case doubleClick
    /// 三击
    case tripleClick
    /// 按住并向上拖拽
    case dragUp
    /// 按住并向下拖拽
    case dragDown
    /// 按住并向左拖拽
    case dragLeft
    /// 按住并向右拖拽
    case dragRight
    /// 按住并向上滚动滚轮
    case scrollUp
    /// 按住并向下滚动滚轮
    case scrollDown
    /// 按住并向左滚动 (滚轮左倾 / 水平滚动)
    case scrollLeft
    /// 按住并向右滚动 (滚轮右倾 / 水平滚动)
    case scrollRight

    // MARK: - 分类

    /// 是否为普通单击 (默认手势)
    var isClick: Bool { self == .click }

    /// 完成识别需要等待 (多击 / 长按 / 拖拽都不能在第一次按下时立刻判定)
    /// `.click` 不需要等待, 可在按下时立即触发, 保持原有零延迟手感.
    var requiresDeferredRecognition: Bool { self != .click }

    /// 是否为按住类手势 (长按)
    var requiresHold: Bool { self == .longPress }

    /// 是否为拖拽类手势
    var isDrag: Bool {
        switch self {
        case .dragUp, .dragDown, .dragLeft, .dragRight:
            return true
        default:
            return false
        }
    }

    /// 是否为滚轮类手势 (按住按钮 + 滚动)
    var isScroll: Bool {
        switch self {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return true
        default:
            return false
        }
    }

    /// 多击次数 (单击=1, 双击=2, 三击=3); 非多击手势返回 nil.
    var clickCount: Int? {
        switch self {
        case .click:
            return 1
        case .doubleClick:
            return 2
        case .tripleClick:
            return 3
        default:
            return nil
        }
    }

    // MARK: - 主键限制

    /// 是否为主键 (左/右键). 覆盖原生 code 0/1 *以及* Logi 转发的左右键 (MosCode 1003/1004).
    /// Logi 左右键不会回落到原生 0/1, 必须单独识别, 否则手势限制会漏掉它们.
    static func isPrimaryMouseButton(_ code: UInt16) -> Bool {
        if KeyCode.mouseMainKeys.contains(code) { return true }
        return LogiCenter.shared.isPrimaryMouseButton(forMosCode: code)
    }

    /// 主键 (左/右键, 含 Logi 转发) 是否允许该手势.
    /// 全部禁止 — 避免用户在主键上误绑手势导致无法正常点击.
    static func isAllowed(_ gesture: MouseGesture, forMouseCode code: UInt16) -> Bool {
        if isPrimaryMouseButton(code) {
            return gesture == .click
        }
        return true
    }

    // MARK: - 展示

    /// 本地化标签 key (用于菜单 / 录制预览 / 行展示的手势徽章)
    var localizedLabelKey: String {
        switch self {
        case .click:        return "gesture-click"
        case .longPress:    return "gesture-long-press"
        case .doubleClick:  return "gesture-double-click"
        case .tripleClick:  return "gesture-triple-click"
        case .dragUp:       return "gesture-drag-up"
        case .dragDown:     return "gesture-drag-down"
        case .dragLeft:     return "gesture-drag-left"
        case .dragRight:    return "gesture-drag-right"
        case .scrollUp:     return "gesture-scroll-up"
        case .scrollDown:   return "gesture-scroll-down"
        case .scrollLeft:   return "gesture-scroll-left"
        case .scrollRight:  return "gesture-scroll-right"
        }
    }

    /// 本地化展示名称
    var displayName: String {
        return NSLocalizedString(localizedLabelKey, comment: "Mouse gesture label")
    }

    /// 展示徽章组件 (供 RecordedEvent.displayComponents 追加).
    /// 单击不追加徽章 (与旧行为视觉一致), 其余手势追加一个 *紧凑* 的语言无关徽章,
    /// 避免长名称的 Logi 按钮 + 完整手势名把触发区撑爆遮住右侧动作下拉.
    /// 完整本地化名称仍由 `displayName` 提供 (行内 tooltip / 辅助功能用).
    var displayBadgeComponent: String? {
        switch self {
        case .click:        return nil
        case .longPress:    return "◷"   // 计时器状字形, 表示按住
        case .doubleClick:  return "×2"
        case .tripleClick:  return "×3"
        case .dragUp:       return "↑"
        case .dragDown:     return "↓"
        case .dragLeft:     return "←"
        case .dragRight:    return "→"
        // 滚轮用双线虚线箭头, 与实线拖拽箭头区分 (同一按钮可同时绑拖拽与滚轮)
        case .scrollUp:     return "⇡"
        case .scrollDown:   return "⇣"
        case .scrollLeft:   return "⇠"
        case .scrollRight:  return "⇢"
        }
    }
}

// MARK: - 方向归类
extension MouseGesture {
    /// 从一次拖拽位移判定方向手势.
    /// 约定: 传入的 dx/dy 使用 "屏幕自然坐标" (向上为 +y, 向右为 +x),
    /// 即 NSEvent.mouseLocation 的坐标系. CGEvent (向下为 +y) 的调用方需先翻转 y.
    /// 主轴取绝对值更大的方向; 水平与垂直相等时优先水平.
    static func dragGesture(dx: CGFloat, dy: CGFloat) -> MouseGesture {
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .dragRight : .dragLeft
        }
        return dy >= 0 ? .dragUp : .dragDown
    }

    /// 从一次滚轮位移判定方向手势.
    /// 约定: dy 取 CGEvent scrollWheel 轴1 (垂直, 向上为正), dx 取轴2 (水平, 向右为正);
    /// 录制捕获与运行时消费使用同一份原始 delta, 因此符号约定一致即可正确匹配.
    /// 主轴取绝对值更大的方向; 垂直与水平相等时优先垂直.
    static func scrollGesture(dx: CGFloat, dy: CGFloat) -> MouseGesture {
        if abs(dy) >= abs(dx) {
            return dy >= 0 ? .scrollUp : .scrollDown
        }
        return dx >= 0 ? .scrollRight : .scrollLeft
    }
}
