// 엑셀 줄 자 — 화면 위에 반투명 띠를 띄워 지금 보는 행/열을 표시하는 메뉴바 앱
import Cocoa
import Carbon

// MARK: - 띠 그리기

final class BandView: NSView {
    var vertical = false
    var color: NSColor = .systemYellow { didSet { needsDisplay = true } }
    var fillAlpha: CGFloat = 0.28 { didSet { needsDisplay = true } }

    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    private var lastMouse: NSPoint = .zero

    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(fillAlpha).setFill()
        bounds.fill()
        // 테두리 선을 진하게 그려서 경계가 잘 보이게
        color.withAlphaComponent(min(1, fillAlpha + 0.55)).setFill()
        let w: CGFloat = 1.5
        if vertical {
            NSRect(x: 0, y: 0, width: w, height: bounds.height).fill()
            NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height).fill()
        } else {
            NSRect(x: 0, y: 0, width: bounds.width, height: w).fill()
            NSRect(x: 0, y: bounds.height - w, width: bounds.width, height: w).fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        lastMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        onDrag?(p.x - lastMouse.x, p.y - lastMouse.y)
        lastMouse = p
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }
}

final class BandPanel: NSPanel {
    let band: BandView
    var onKey: ((NSEvent) -> Bool)?

    init(vertical: Bool) {
        band = BandView()
        band.vertical = vertical
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = band
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

// MARK: - 앱

enum Mode: Int { case horizontal = 0, vertical, cross }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let colors: [(String, NSColor)] = [
        ("노랑", .systemYellow), ("하늘", .systemTeal), ("초록", .systemGreen),
        ("분홍", .systemPink), ("주황", .systemOrange), ("보라", .systemPurple),
    ]
    let alphas: [(String, CGFloat)] = [("연하게", 0.16), ("보통", 0.28), ("진하게", 0.42)]
    let hSizes: [CGFloat] = [16, 18, 20, 24, 30, 40]
    let vSizes: [CGFloat] = [40, 60, 80, 100, 140]

    let d = UserDefaults.standard
    var mode: Mode = .horizontal
    var follow = true
    var visible = true
    var colorIdx = 0
    var alphaIdx = 1
    var hThick: CGFloat = 20
    var vThick: CGFloat = 80
    var center = NSPoint(x: 400, y: 400)

    let hBand = BandPanel(vertical: false)
    let vBand = BandPanel(vertical: true)
    var statusItem: NSStatusItem!
    var timer: Timer?
    var lastMouse = NSPoint(x: -1, y: -1)
    var hotKeys: [EventHotKeyRef?] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        load()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📏"

        for panel in [hBand, vBand] {
            panel.band.onDrag = { [weak self] dx, dy in self?.dragged(panel, dx, dy) }
            panel.band.onScroll = { [weak self] dy in self?.scrolled(panel, dy) }
            panel.onKey = { [weak self] e in self?.key(panel, e) ?? false }
        }
        if !follow { center = NSEvent.mouseLocation }
        registerHotKeys()
        apply()
    }

    // MARK: 설정 저장/불러오기

    func load() {
        if d.object(forKey: "mode") != nil {
            mode = Mode(rawValue: d.integer(forKey: "mode")) ?? .horizontal
            follow = d.bool(forKey: "follow")
            colorIdx = min(d.integer(forKey: "color"), colors.count - 1)
            alphaIdx = min(d.integer(forKey: "alpha"), alphas.count - 1)
            hThick = CGFloat(d.double(forKey: "hThick"))
            vThick = CGFloat(d.double(forKey: "vThick"))
        }
    }

    func save() {
        d.set(mode.rawValue, forKey: "mode")
        d.set(follow, forKey: "follow")
        d.set(colorIdx, forKey: "color")
        d.set(alphaIdx, forKey: "alpha")
        d.set(Double(hThick), forKey: "hThick")
        d.set(Double(vThick), forKey: "vThick")
    }

    // MARK: 화면 반영

    var showH: Bool { visible && mode != .vertical }
    var showV: Bool { visible && mode != .horizontal }

    func apply() {
        for p in [hBand, vBand] {
            p.band.color = colors[colorIdx].1
            p.band.fillAlpha = alphas[alphaIdx].1
            // 따라가기 모드에서는 클릭이 엑셀로 그대로 통과해야 함
            p.ignoresMouseEvents = follow
        }
        if follow { center = NSEvent.mouseLocation }
        place()
        showH ? hBand.orderFrontRegardless() : hBand.orderOut(nil)
        showV ? vBand.orderFrontRegardless() : vBand.orderOut(nil)

        timer?.invalidate()
        timer = nil
        if follow && visible {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        statusItem.button?.title = visible ? (follow ? "📏" : "📌") : "📏̸"
        buildMenu()
        save()
    }

    func screen(for p: NSPoint) -> NSRect {
        (NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]).frame
    }

    func place() {
        let s = screen(for: center)
        if showH {
            hBand.setFrame(NSRect(x: s.minX, y: round(center.y - hThick / 2), width: s.width, height: hThick), display: true)
        }
        if showV {
            vBand.setFrame(NSRect(x: round(center.x - vThick / 2), y: s.minY, width: vThick, height: s.height), display: true)
        }
    }

    func tick() {
        let p = NSEvent.mouseLocation
        if p != lastMouse {
            lastMouse = p
            center = p
            place()
        }
    }

    // MARK: 고정 모드 조작 (드래그 / 스크롤 / 키보드)

    func dragged(_ panel: BandPanel, _ dx: CGFloat, _ dy: CGFloat) {
        if panel === hBand { center.y += dy } else { center.x += dx }
        place()
    }

    func scrolled(_ panel: BandPanel, _ dy: CGFloat) {
        guard dy != 0 else { return }
        let step: CGFloat = dy > 0 ? 1 : -1
        if panel === hBand { hThick = max(4, min(300, hThick + step)) } else { vThick = max(4, min(600, vThick + step)) }
        place()
        save()
    }

    func key(_ panel: BandPanel, _ e: NSEvent) -> Bool {
        let shift = e.modifierFlags.contains(.shift)
        switch Int(e.keyCode) {
        case kVK_UpArrow:    center.y += shift ? hThick : 1
        case kVK_DownArrow:  center.y -= shift ? hThick : 1
        case kVK_LeftArrow:  center.x -= shift ? vThick : 1
        case kVK_RightArrow: center.x += shift ? vThick : 1
        case kVK_Escape:     follow = true; apply(); return true
        default: return false
        }
        place()
        return true
    }

    // MARK: 전역 단축키 (권한 필요 없음)

    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ud in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<AppDelegate>.fromOpaque(ud!).takeUnretainedValue()
            DispatchQueue.main.async { me.hotKey(Int(id.id)) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let mods = UInt32(controlKey | optionKey)
        let keys: [(Int, Int)] = [(kVK_ANSI_R, 1), (kVK_ANSI_F, 2), (kVK_ANSI_M, 3)]
        for (code, id) in keys {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(code), mods, EventHotKeyID(signature: OSType(0x52554C52), id: UInt32(id)),
                                GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }

    func hotKey(_ id: Int) {
        switch id {
        case 1: visible.toggle()
        case 2: toggleFollowState()
        case 3: mode = Mode(rawValue: (mode.rawValue + 1) % 3)!
        default: return
        }
        apply()
    }

    func toggleFollowState() {
        follow.toggle()
        if !follow {
            center = NSEvent.mouseLocation
            // 고정하자마자 방향키로 움직일 수 있게 포커스
            (mode == .vertical ? vBand : hBand).makeKey()
        }
    }

    // MARK: 메뉴

    func buildMenu() {
        let m = NSMenu()
        func item(_ title: String, _ on: Bool = false, key: String = "", _ action: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
            i.state = on ? .on : .off
            m.addItem(i)
        }
        func header(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }

        item(visible ? "숨기기  (⌃⌥R)" : "보이기  (⌃⌥R)") { [unowned self] in visible.toggle(); apply() }
        item("마우스 따라가기  (⌃⌥F)", follow) { [unowned self] in toggleFollowState(); apply() }
        m.addItem(.separator())

        header("모양  (⌃⌥M 으로 전환)")
        item("  가로 줄 (행)", mode == .horizontal) { [unowned self] in mode = .horizontal; apply() }
        item("  세로 줄 (열)", mode == .vertical) { [unowned self] in mode = .vertical; apply() }
        item("  십자 (행 + 열)", mode == .cross) { [unowned self] in mode = .cross; apply() }
        m.addItem(.separator())

        header("색")
        for (i, c) in colors.enumerated() {
            item("  " + c.0, i == colorIdx) { [unowned self] in colorIdx = i; apply() }
        }
        m.addItem(.separator())

        header("진하기")
        for (i, a) in alphas.enumerated() {
            item("  " + a.0, i == alphaIdx) { [unowned self] in alphaIdx = i; apply() }
        }
        m.addItem(.separator())

        let hSub = NSMenu()
        for s in hSizes {
            let i = ClosureMenuItem(title: "\(Int(s)) px", keyEquivalent: "") { [unowned self] in hThick = s; apply() }
            i.state = s == hThick ? .on : .off
            hSub.addItem(i)
        }
        let hItem = NSMenuItem(title: "가로 줄 두께  (지금 \(Int(hThick))px)", action: nil, keyEquivalent: "")
        hItem.submenu = hSub
        m.addItem(hItem)

        let vSub = NSMenu()
        for s in vSizes {
            let i = ClosureMenuItem(title: "\(Int(s)) px", keyEquivalent: "") { [unowned self] in vThick = s; apply() }
            i.state = s == vThick ? .on : .off
            vSub.addItem(i)
        }
        let vItem = NSMenuItem(title: "세로 줄 두께  (지금 \(Int(vThick))px)", action: nil, keyEquivalent: "")
        vItem.submenu = vSub
        m.addItem(vItem)

        m.addItem(.separator())
        header("고정 모드: 끌어서 이동 · 휠로 두께 조절")
        header("↑↓←→ 1px 이동 · ⇧+방향키 한 칸 · esc 따라가기")
        m.addItem(.separator())
        item("종료", key: "q") { NSApp.terminate(nil) }
        statusItem.menu = m
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
