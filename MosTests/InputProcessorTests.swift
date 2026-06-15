import XCTest
@testable import Mos_Debug

final class InputProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
    }

    override func tearDown() {
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    func testProcess_downEvent_consumedWhenBindingMatches() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                               phase: .down, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_consumedViaActiveBindings() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_logiStandardButtonEventDoesNotMatchNativeMouseBinding() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(
            type: .mouse,
            code: 1006,
            modifiers: CGEventFlags(rawValue: 0),
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertEqual(InputProcessor.shared.process(event), .passthrough)
    }

    func testProcess_nativeMouseButtonMatchesNativeMouseBinding() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: upEvent)), .consumed)
        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_upEvent_passthroughWithoutPriorDown() {
        let event = InputEvent(type: .mouse, code: 99, modifiers: CGEventFlags(rawValue: 0),
                               phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .passthrough)
    }

    func testProcess_upEvent_matchesDespiteModifierChange() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
                                    displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskCommand,
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        // Up with ⌘ already released (modifiers = 0)
        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testSystemShortcutExecutionModes_mouseActionsStateful_nonMouseTrigger() {
        XCTAssertEqual(SystemShortcut.mouseLeftClick.executionMode, .stateful)
        XCTAssertEqual(SystemShortcut.logiSmartShiftToggle.executionMode, .trigger)
    }

    func testProcess_upEvent_passthroughForTriggerShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "logiSmartShiftToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .passthrough)
    }

    func testProcess_upEvent_consumedForStatefulMouseShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
    }

    func testProcess_statefulMouseShortcut_doesNotSetVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_statefulMouseShortcut_startsAndStopsMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierShortcut_startsAndStopsMotionTapForMouseInteractionPropagation() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::58:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_predefinedModifierShortcut_usesStatefulModifierFlow() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "modifierOption", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testResolveAction_predefinedModifierShortcut_mapsToCustomModifierKey() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "modifierShift") else {
            return XCTFail("Expected predefined modifier shortcut to resolve")
        }

        switch action {
        case .customKey(let code, let modifiers):
            XCTAssertEqual(code, KeyCode.shiftL)
            XCTAssertEqual(modifiers, 0)
        default:
            XCTFail("Expected predefined modifier shortcut to reuse custom modifier execution")
        }
    }

    func testResolveAction_escapeShortcut_mapsToSystemShortcut() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "escapeKey") else {
            return XCTFail("Expected escape shortcut to resolve")
        }

        switch action {
        case .systemShortcut(let identifier):
            XCTAssertEqual(identifier, "escapeKey")
        default:
            XCTFail("Expected escape shortcut to use the system shortcut execution path")
        }
    }

    func testResolveAction_mosScrollActionsAreStateful() {
        for identifier in ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"] {
            guard let action = ShortcutExecutor.shared.resolveAction(named: identifier) else {
                return XCTFail("Expected \(identifier) action to resolve")
            }

            XCTAssertEqual(action.executionMode, .stateful)
        }
    }

    func testProcess_mosScrollDash_downAndUpControlsDashState() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollMiddleTapWithoutScroll_replaysOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64, userData: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((
                event.type,
                event.getIntegerValueField(.mouseEventButtonNumber),
                event.getIntegerValueField(.eventSourceUserData)
            ))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [2, 2])
        XCTAssertEqual(observedEvents.map(\.userData), [MosEventMarker.syntheticCustom, MosEventMarker.syntheticCustom])
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollMiddleTapWithScrollUse_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        InputProcessor.shared.markMosScrollActionSessionsUsedForScroll()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelWhileMosScrollHeldSuppressesTapReplay() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelReleasesCGMosScrollSessionWhenPhysicalButtonIsNoLongerDown() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollCGMouseTapWithPointerMove_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: 70, y: 40),
            mouseButton: .center
        )!
        upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: upEvent)), .consumed)

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_logiButtonCanTriggerMosScrollToggle() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward Button"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.toggleScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    func testProcess_logiMosScrollForwardTapWithoutScroll_replaysForwardButton() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward Button"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.getIntegerValueField(.mouseEventButtonNumber)))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [4, 4])
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    func testProcess_mosScrollBlock_downAndUpControlsBlockState() {
        let trigger = RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollBlock", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.blockSmooth)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }

    func testProcess_multipleMosScrollDashTriggers_releaseOneKeepsDashActive() {
        let firstTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let secondTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        let firstBinding = ButtonBinding(triggerEvent: firstTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        let secondBinding = ButtonBinding(triggerEvent: secondTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [firstBinding, secondBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollBindingDoesNotLatchWhenLegacyScrollHotkeySeesOnlyDown() {
        struct Case {
            let shortcutName: String
            let configureLegacyHotkey: (ScrollHotkey) -> Void
            let isRoleActive: () -> Bool
        }

        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        let originalBlock = Options.shared.scroll.block
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
            Options.shared.scroll.block = originalBlock
        }

        let cases: [Case] = [
            Case(
                shortcutName: "mosScrollDash",
                configureLegacyHotkey: { Options.shared.scroll.dash = $0 },
                isRoleActive: { ScrollCore.shared.dashScroll }
            ),
            Case(
                shortcutName: "mosScrollToggle",
                configureLegacyHotkey: { Options.shared.scroll.toggle = $0 },
                isRoleActive: { ScrollCore.shared.toggleScroll }
            ),
            Case(
                shortcutName: "mosScrollBlock",
                configureLegacyHotkey: { Options.shared.scroll.block = $0 },
                isRoleActive: { ScrollCore.shared.blockSmooth }
            ),
        ]

        for testCase in cases {
            InputProcessor.shared.clearActiveBindings()
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
            ScrollCore.shared.toggleScroll = false
            ScrollCore.shared.blockSmooth = false
            ScrollCore.shared.dashKeyHeld = false
            ScrollCore.shared.toggleKeyHeld = false
            ScrollCore.shared.blockKeyHeld = false
            Options.shared.scroll.dash = nil
            Options.shared.scroll.toggle = nil
            Options.shared.scroll.block = nil

            let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
            let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: testCase.shortcutName, isEnabled: true)
            Options.shared.buttons.binding = [binding]
            ButtonUtils.shared.invalidateCache()
            testCase.configureLegacyHotkey(ScrollHotkey(type: .mouse, code: 2))

            let legacyDownEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: CGPoint(x: 40, y: 40),
                mouseButton: .center
            )!
            legacyDownEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .otherMouseDown, legacyDownEvent, nil)

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertTrue(testCase.isRoleActive(), "\(testCase.shortcutName) should be active while held")

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertFalse(testCase.isRoleActive(), "\(testCase.shortcutName) should release even if the legacy hotkey tap missed up")
        }
    }

    func testProcess_mouseSessionRemainsActiveAfterVirtualModifierReleasesUntilMouseUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierKeepsMotionTapRunningAfterMouseSessionEndsUntilModifierUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_multipleVirtualModifiers_applyToMappedMouseEvents() {
        let shiftTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let optionTrigger = RecordedEvent(type: .mouse, code: 7, modifiers: 0, displayComponents: ["🖱8"], deviceFilter: nil)
        let leftTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)

        let shiftBinding = ButtonBinding(triggerEvent: shiftTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        let optionBinding = ButtonBinding(triggerEvent: optionTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let leftBinding = ButtonBinding(triggerEvent: leftTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [shiftBinding, optionBinding, leftBinding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 7, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue | CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { event in
            event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        })
    }

    func testProcess_statefulMouseShortcut_preservesPhysicalModifierFlagsOnSyntheticMouseEvents() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { $0.flags.contains(.maskShift) })
    }

    func testProcess_mouseTriggerWithoutModifiers_matchesWhenAdditionalModifiersHeld() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_mouseTriggerPrefersExactModifierBindingOverBaseBinding() {
        let baseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let exactTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let baseBinding = ButtonBinding(triggerEvent: baseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let exactBinding = ButtonBinding(triggerEvent: exactTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        Options.shared.buttons.binding = [baseBinding, exactBinding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.rightMouseDown, .rightMouseUp])
    }

    func testProcess_repeatedDownForSameTrigger_replacesPreviousMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)
    }

    func testClearActiveBindings_clearsVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, KeyCode.getKeyMask(56).rawValue)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testClearActiveBindings_clearsActiveMouseInteractionSessions() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testButtonCore_passthroughKeyboardEvent_appliesVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.buttonEventCallBack(proxy, .keyDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testButtonCore_passthroughRealLeftMouseEvent_doesNotApplyVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 16, y: 24),
            mouseButton: .left
        )!
        event.flags = CGEventFlags(rawValue: 0)

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.primaryMouseObservationCallBack(proxy, .leftMouseDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertFalse(event.flags.contains(.maskShift))
    }

    func testCGEventExtensions_otherMouseDraggedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertTrue(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.mouseCode, 3)
        XCTAssertEqual(event.eventTypeName, "otherMouseDragged")
    }

    func testCGEventExtensions_mouseMovedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 12, y: 34),
            mouseButton: .left
        )!

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertFalse(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseMoveEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.eventTypeName, "mouseMoved")
    }

    func testInputEventFromCGEvent_otherMouseDraggedPreservesMouseCode() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 90, y: 45),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let inputEvent = InputEvent(fromCGEvent: event)
        XCTAssertEqual(inputEvent.type, .mouse)
        XCTAssertEqual(inputEvent.code, 3)
    }

    func testMonitorLogStore_previewShowsNewestLinesWithoutDroppingExportHistory() {
        let store = MonitorLogStore(previewLineLimit: 2)

        store.append("first", to: .buttonEvent)
        store.append("second", to: .buttonEvent)
        store.append("third", to: .buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "third\nsecond")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "first\nsecond\nthird")
    }

    func testMonitorLogStore_clearChannelRemovesPreviewAndHistory() {
        let store = MonitorLogStore(previewLineLimit: 3)

        store.append("one", to: .buttonEvent)
        store.append("two", to: .buttonEvent)
        store.clear(.buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "")
    }

    func testMonitorButtonEventLogLine_includesMouseModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 32, y: 48),
            mouseButton: .left
        )!
        event.flags = [.maskShift, .maskCommand]
        event.setIntegerValueField(.mouseEventDeltaX, value: 4)
        event.setIntegerValueField(.mouseEventDeltaY, value: -2)
        event.setIntegerValueField(.eventSourceUserData, value: 42)

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
        XCTAssertTrue(rendered.contains("userData: 42"))
    }

    func testMonitorButtonEventLogLine_includesFlagsChangedPhaseAndModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(source: nil)!
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(KeyCode.optionL))
        event.flags = [.maskAlternate, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("flagsChanged"))
        XCTAssertTrue(rendered.contains("phase: down"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌥]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testMonitorButtonEventLogLine_includesKeyDownModifiersAndKeyName() {
        let controller = MonitorViewController()

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        event.flags = [.maskCommand, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("keyDown"))
        XCTAssertTrue(rendered.contains("key:"))
        XCTAssertTrue(rendered.contains("keyCode: 0"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testButtonUtilsIndex_returnsOnlyMatchingTypeAndCodeCandidates() {
        let matchingTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let matchingWithDifferentModifiers = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue), displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let wrongTypeTrigger = RecordedEvent(type: .keyboard, code: 3, modifiers: 0, displayComponents: ["F"], deviceFilter: nil)
        let wrongCodeTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)

        let matchingBinding = ButtonBinding(triggerEvent: matchingTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let matchingWithDifferentModifiersBinding = ButtonBinding(triggerEvent: matchingWithDifferentModifiers, systemShortcutName: "custom::56:0", isEnabled: true)
        let wrongTypeBinding = ButtonBinding(triggerEvent: wrongTypeTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        let wrongCodeBinding = ButtonBinding(triggerEvent: wrongCodeTrigger, systemShortcutName: "mouseMiddleClick", isEnabled: true)

        Options.shared.buttons.binding = [
            matchingBinding,
            matchingWithDifferentModifiersBinding,
            wrongTypeBinding,
            wrongCodeBinding,
        ]
        ButtonUtils.shared.invalidateCache()

        let candidates = ButtonUtils.shared.getButtonBindings(for: .mouse, code: 3)

        XCTAssertEqual(
            Set(candidates.map(\.id)),
            Set([matchingBinding.id, matchingWithDifferentModifiersBinding.id])
        )
    }

    func testButtonCore_dispatchEventMask_excludesPrimaryMouseButtons() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType, in mask: CGEventMask) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return mask & typeMask != 0
        }

        XCTAssertFalse(contains(.leftMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.leftMouseUp, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyUp, in: core.dispatchEventMask))
    }

    func testButtonCore_primaryObservationMask_includesPrimaryMouseButtons() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType, in mask: CGEventMask) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return mask & typeMask != 0
        }

        XCTAssertTrue(contains(.leftMouseDown, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.leftMouseUp, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.rightMouseDown, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.rightMouseUp, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.otherMouseDown, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.otherMouseUp, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.keyDown, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.keyUp, in: core.primaryObservationEventMask))
    }

}

// MARK: - MouseGesture model
final class MouseGestureModelTests: XCTestCase {

    func testClassification() {
        XCTAssertTrue(MouseGesture.click.isClick)
        XCTAssertFalse(MouseGesture.click.requiresDeferredRecognition)
        XCTAssertTrue(MouseGesture.doubleClick.requiresDeferredRecognition)
        XCTAssertTrue(MouseGesture.longPress.requiresHold)
        XCTAssertFalse(MouseGesture.doubleClick.requiresHold)
        XCTAssertTrue(MouseGesture.dragLeft.isDrag)
        XCTAssertFalse(MouseGesture.longPress.isDrag)
        XCTAssertEqual(MouseGesture.click.clickCount, 1)
        XCTAssertEqual(MouseGesture.doubleClick.clickCount, 2)
        XCTAssertEqual(MouseGesture.tripleClick.clickCount, 3)
        XCTAssertNil(MouseGesture.dragUp.clickCount)
    }

    func testPrimaryButtonsOnlyAllowClick() {
        // 左键 (0) / 右键 (1) 只允许单击
        for code: UInt16 in [0, 1] {
            XCTAssertTrue(MouseGesture.isAllowed(.click, forMouseCode: code))
            XCTAssertFalse(MouseGesture.isAllowed(.doubleClick, forMouseCode: code))
            XCTAssertFalse(MouseGesture.isAllowed(.longPress, forMouseCode: code))
            XCTAssertFalse(MouseGesture.isAllowed(.dragRight, forMouseCode: code))
        }
        // 非主键允许全部手势
        XCTAssertTrue(MouseGesture.isAllowed(.doubleClick, forMouseCode: 3))
        XCTAssertTrue(MouseGesture.isAllowed(.dragLeft, forMouseCode: 1000))
    }

    func testDragDirectionClassification() {
        // 自然坐标: +x 右, +y 上
        XCTAssertEqual(MouseGesture.dragGesture(dx: 20, dy: 1), .dragRight)
        XCTAssertEqual(MouseGesture.dragGesture(dx: -20, dy: 1), .dragLeft)
        XCTAssertEqual(MouseGesture.dragGesture(dx: 1, dy: 20), .dragUp)
        XCTAssertEqual(MouseGesture.dragGesture(dx: 1, dy: -20), .dragDown)
        // 水平/垂直相等优先水平
        XCTAssertEqual(MouseGesture.dragGesture(dx: 10, dy: 10), .dragRight)
    }

    func testBadgeOmittedForClick() {
        XCTAssertNil(MouseGesture.click.displayBadgeComponent)
        XCTAssertNotNil(MouseGesture.longPress.displayBadgeComponent)
    }
}

// MARK: - MouseGestureRecognizer (纯状态机)
final class MouseGestureRecognizerTests: XCTestCase {

    private func makeRecognizer(_ armed: Set<MouseGesture>) -> (MouseGestureRecognizer, () -> [MouseGesture]) {
        var recognized: [MouseGesture] = []
        let config = MouseGestureRecognizer.Config(
            armedGestures: armed,
            longPressDelay: 0.35,
            multiClickInterval: 0.30,
            dragDistance: 10
        )
        let recognizer = MouseGestureRecognizer(config: config)
        recognizer.onRecognize = { recognized.append($0) }
        return (recognizer, { recognized })
    }

    func testSingleClickWhenOnlyDoubleArmed_resolvesToClickAfterTimeout() {
        let (r, recognized) = makeRecognizer([.doubleClick])
        r.handleDown(at: .zero, time: 0)
        r.handleUp(at: .zero, time: 0.05)
        XCTAssertEqual(r.pendingDeadline ?? -1, 0.35, accuracy: 1e-9)
        r.handleTimeout(time: 0.35)
        XCTAssertEqual(recognized(), [.click])
    }

    func testDoubleClick() {
        let (r, recognized) = makeRecognizer([.doubleClick])
        r.handleDown(at: .zero, time: 0)
        r.handleUp(at: .zero, time: 0.05)
        r.handleDown(at: .zero, time: 0.10)
        r.handleUp(at: .zero, time: 0.12)
        XCTAssertEqual(recognized(), [.doubleClick])
    }

    func testTripleClick() {
        let (r, recognized) = makeRecognizer([.tripleClick])
        r.handleDown(at: .zero, time: 0);   r.handleUp(at: .zero, time: 0.03)
        r.handleDown(at: .zero, time: 0.06); r.handleUp(at: .zero, time: 0.09)
        r.handleDown(at: .zero, time: 0.12); r.handleUp(at: .zero, time: 0.15)
        XCTAssertEqual(recognized(), [.tripleClick])
    }

    func testLongPress() {
        let (r, recognized) = makeRecognizer([.longPress])
        r.handleDown(at: .zero, time: 0)
        XCTAssertEqual(r.pendingDeadline ?? -1, 0.35, accuracy: 1e-9)
        r.handleTimeout(time: 0.35)
        r.handleUp(at: .zero, time: 0.5)
        XCTAssertEqual(recognized(), [.longPress])
    }

    func testLongPressArmedButQuickReleaseIsClick() {
        let (r, recognized) = makeRecognizer([.longPress])
        r.handleDown(at: .zero, time: 0)
        r.handleUp(at: .zero, time: 0.1)
        XCTAssertEqual(recognized(), [.click])
    }

    func testDragInArmedDirection() {
        let (r, recognized) = makeRecognizer([.dragRight])
        r.handleDown(at: CGPoint(x: 0, y: 0), time: 0)
        r.handleMove(to: CGPoint(x: 20, y: 1), time: 0.05)
        r.handleUp(at: CGPoint(x: 20, y: 1), time: 0.1)
        XCTAssertEqual(recognized(), [.dragRight])
    }

    func testDragInUnarmedDirectionEmitsNothing() {
        let (r, recognized) = makeRecognizer([.dragRight])
        r.handleDown(at: CGPoint(x: 0, y: 0), time: 0)
        r.handleMove(to: CGPoint(x: -20, y: 0), time: 0.05)
        r.handleUp(at: CGPoint(x: -20, y: 0), time: 0.1)
        XCTAssertTrue(recognized().isEmpty)
    }

    func testSmallMovementIsNotDrag() {
        let (r, recognized) = makeRecognizer([.dragRight])
        r.handleDown(at: CGPoint(x: 0, y: 0), time: 0)
        r.handleMove(to: CGPoint(x: 5, y: 0), time: 0.05)
        r.handleUp(at: CGPoint(x: 5, y: 0), time: 0.1)
        // 拖拽未达阈值, 且无多击布防 → 当作单击
        XCTAssertEqual(recognized(), [.click])
    }

    func testLongPressAndDoubleArmed_holdYieldsLongPress() {
        let (r, recognized) = makeRecognizer([.longPress, .doubleClick])
        r.handleDown(at: .zero, time: 0)
        r.handleTimeout(time: 0.35)
        XCTAssertEqual(recognized(), [.longPress])
    }

    func testCancelEmitsNothing() {
        let (r, recognized) = makeRecognizer([.longPress])
        r.handleDown(at: .zero, time: 0)
        r.cancel()
        r.handleTimeout(time: 0.35)
        XCTAssertTrue(recognized().isEmpty)
    }
}

// MARK: - Manual scheduler for deterministic controller tests
private final class ManualGestureScheduler: GestureDeadlineScheduling {
    private(set) var pending: (() -> Void)?
    private(set) var fireAt: TimeInterval?
    var isScheduled: Bool { pending != nil }
    func schedule(fireAt: TimeInterval, now: TimeInterval, action: @escaping () -> Void) {
        self.fireAt = fireAt
        self.pending = action
    }
    func cancel() {
        fireAt = nil
        pending = nil
    }
    func fire() {
        let action = pending
        cancel()
        action?()
    }
}

// MARK: - MouseGestureController (注入计时/执行 seam, 确定性测试)
final class MouseGestureControllerTests: XCTestCase {
    private var time: TimeInterval = 0
    private var scheduler = ManualGestureScheduler()
    private var controller = MouseGestureController()
    private var executed: [ButtonBinding] = []
    private var replays = 0

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        time = 0
        executed = []
        replays = 0
        scheduler = ManualGestureScheduler()
        controller = MouseGestureController()
        controller.nowProvider = { [weak self] in self?.time ?? 0 }
        controller.schedulerFactory = { [weak self] in self?.scheduler ?? ManualGestureScheduler() }
        controller.actionExecutor = { [weak self] binding, _ in self?.executed.append(binding) }
        controller.clickReplayer = { [weak self] _ in self?.replays += 1 }
        controller.motionTracking = { _ in }
    }

    override func tearDown() {
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    private func mouse(_ phase: InputPhase, code: UInt16 = 3, modifiers: CGEventFlags = []) -> InputEvent {
        InputEvent(type: .mouse, code: code, modifiers: modifiers, phase: phase, source: .hidPP, device: nil)
    }

    private func bind(_ gesture: MouseGesture, code: UInt16 = 3, name: String = "custom::56:0") -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil, gesture: gesture)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: name, isEnabled: true)
    }

    func testHandleDownReturnsFalseWhenNoNonClickGestureArmed() {
        Options.shared.buttons.binding = [bind(.click)]
        ButtonUtils.shared.invalidateCache()
        XCTAssertFalse(controller.handleDown(mouse(.down)))
    }

    func testDoubleClickExecutesBinding() {
        let b = bind(.doubleClick)
        Options.shared.buttons.binding = [b]
        ButtonUtils.shared.invalidateCache()

        XCTAssertTrue(controller.handleDown(mouse(.down)))
        time = 0.05; XCTAssertTrue(controller.handleUp(mouse(.up)))
        XCTAssertTrue(scheduler.isScheduled)
        time = 0.10; XCTAssertTrue(controller.handleDown(mouse(.down)))
        time = 0.12; XCTAssertTrue(controller.handleUp(mouse(.up)))

        XCTAssertEqual(executed.map(\.id), [b.id])
        XCTAssertEqual(replays, 0)
    }

    func testSingleClickOnDoubleOnlyButtonReplaysPhysicalClick() {
        let b = bind(.doubleClick)
        Options.shared.buttons.binding = [b]
        ButtonUtils.shared.invalidateCache()

        XCTAssertTrue(controller.handleDown(mouse(.down)))
        time = 0.05; XCTAssertTrue(controller.handleUp(mouse(.up)))
        time = 0.35; scheduler.fire()

        XCTAssertTrue(executed.isEmpty)
        XCTAssertEqual(replays, 1)
    }

    func testClickAndDoubleArmed_singleClickExecutesClickBinding() {
        let clickB = bind(.click, name: "custom::58:0")
        let doubleB = bind(.doubleClick, name: "custom::56:0")
        Options.shared.buttons.binding = [clickB, doubleB]
        ButtonUtils.shared.invalidateCache()

        XCTAssertTrue(controller.handleDown(mouse(.down)))
        time = 0.05; XCTAssertTrue(controller.handleUp(mouse(.up)))
        time = 0.35; scheduler.fire()

        XCTAssertEqual(executed.map(\.id), [clickB.id])
        XCTAssertEqual(replays, 0)
    }

    func testLongPressExecutesOnTimeout() {
        let b = bind(.longPress)
        Options.shared.buttons.binding = [b]
        ButtonUtils.shared.invalidateCache()

        XCTAssertTrue(controller.handleDown(mouse(.down)))
        XCTAssertTrue(scheduler.isScheduled)
        time = 0.35; scheduler.fire()
        XCTAssertEqual(executed.map(\.id), [b.id])

        time = 0.5; XCTAssertTrue(controller.handleUp(mouse(.up)))
        XCTAssertFalse(controller.hasActiveSessions)
    }

    func testDragExecutesViaMotion() {
        let b = bind(.dragRight)
        Options.shared.buttons.binding = [b]
        ButtonUtils.shared.invalidateCache()

        let downCG = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 100, y: 100),
            mouseButton: .center
        )!
        downCG.setIntegerValueField(.mouseEventButtonNumber, value: 3)
        XCTAssertTrue(controller.handleDown(InputEvent(fromCGEvent: downCG)))

        // 向右移动 100pt (y 翻转抵消, dx 与屏高无关) → dragRight
        controller.handleMove(toCGLocation: CGPoint(x: 200, y: 100))

        XCTAssertEqual(executed.map(\.id), [b.id])
        XCTAssertEqual(replays, 0)
    }

    func testCancelAllClearsSessions() {
        Options.shared.buttons.binding = [bind(.longPress)]
        ButtonUtils.shared.invalidateCache()
        XCTAssertTrue(controller.handleDown(mouse(.down)))
        XCTAssertTrue(controller.hasActiveSessions)
        controller.cancelAll()
        XCTAssertFalse(controller.hasActiveSessions)
    }
}

// MARK: - RecordedEvent gesture 持久化 / 展示 / 匹配
final class RecordedEventGestureTests: XCTestCase {

    func testClickGestureOmittedFromJSON() throws {
        let event = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .click)
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["gesture"], "Click gesture must not be written (向后兼容旧 JSON)")
    }

    func testNonClickGestureRoundTrips() throws {
        let event = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .doubleClick)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)
        XCTAssertEqual(decoded.resolvedGesture, .doubleClick)
    }

    func testLegacyJSONWithoutGestureDecodesToClick() throws {
        let json = #"{"type":"mouse","code":3,"modifiers":0,"deviceFilter":null}"#
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: json.data(using: .utf8)!)
        XCTAssertNil(decoded.gesture)
        XCTAssertEqual(decoded.resolvedGesture, .click)
    }

    func testEqualityDistinguishesGesture() {
        let click = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .click)
        let double1 = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .doubleClick)
        let double2 = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .doubleClick)
        XCTAssertNotEqual(click, double1)
        XCTAssertEqual(double1, double2)
    }

    func testDisplayComponentsAppendGestureBadgeForNonClick() {
        // 行内徽章用紧凑字形 (避免撑爆触发区), 完整名称走 accessibilityLabel.
        let double = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .doubleClick)
        XCTAssertEqual(double.displayComponents.last, MouseGesture.doubleClick.displayBadgeComponent)
        XCTAssertNotEqual(double.displayComponents.last, MouseGesture.doubleClick.displayName)
        XCTAssertTrue(double.accessibilityLabel.contains(MouseGesture.doubleClick.displayName))
        let click = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .click)
        XCTAssertFalse(click.displayComponents.contains(where: { $0 == MouseGesture.doubleClick.displayBadgeComponent }))
    }

    func testButtonBindingRoundTripPreservesGesture() throws {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, gesture: .longPress)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.triggerEvent.resolvedGesture, .longPress)
    }

    func testInputEventCarriesGestureToRecordedEvent() {
        let event = InputEvent(type: .mouse, code: 3, modifiers: [], phase: .down,
                               source: .hidPP, device: nil, gesture: .tripleClick)
        let recorded = RecordedEvent(from: event)
        XCTAssertEqual(recorded.resolvedGesture, .tripleClick)
    }

    func testInputProcessorIgnoresNonClickBindingOnRawDown() {
        // 非单击绑定不应被原始 down 立即匹配 (应走手势协调器).
        let trigger = RecordedEvent(type: .mouse, code: 9, modifiers: 0, deviceFilter: nil, gesture: .doubleClick)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()
        defer { Options.shared.buttons.binding = []; ButtonUtils.shared.invalidateCache() }

        // 仅绑定双击 → 协调器接管 down (consumed), 但不会立即执行单击动作.
        let down = InputEvent(type: .mouse, code: 9, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        InputProcessor.shared.clearActiveBindings()
    }
}
