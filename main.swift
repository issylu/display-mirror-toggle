import Cocoa

// MARK: - Display enumeration

// CGGetActiveDisplayList excludes mirror slaves, so we must use CGGetOnlineDisplayList
// to reliably detect secondary displays even while already mirrored.
func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &displays, &count)
    return displays
}

func builtInDisplay() -> CGDirectDisplayID? {
    onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
}

func externalDisplays() -> [CGDirectDisplayID] {
    onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 }
}

// MARK: - Mirroring

enum MasterRole: String {
    case builtIn = "builtin"
    case external = "external"
}

var preferredMasterRole: MasterRole {
    get { MasterRole(rawValue: UserDefaults.standard.string(forKey: "mirrorMasterRole") ?? "builtin") ?? .builtIn }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "mirrorMasterRole") }
}

func resolvedMaster(for role: MasterRole) -> CGDirectDisplayID? {
    switch role {
    case .builtIn: return builtInDisplay()
    case .external: return externalDisplays().first
    }
}

func isCurrentlyMirrored() -> Bool {
    onlineDisplays().contains { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
}

func disableMirroring() {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
    for d in onlineDisplays() {
        CGConfigureDisplayMirrorOfDisplay(cfg, d, kCGNullDirectDisplay)
    }
    CGCompleteDisplayConfiguration(cfg, .permanently)
}

func enableMirroring(master: CGDirectDisplayID) {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
    for d in onlineDisplays() where d != master {
        CGConfigureDisplayMirrorOfDisplay(cfg, d, master)
    }
    CGCompleteDisplayConfiguration(cfg, .permanently)
}

func toggleMirror() {
    if isCurrentlyMirrored() {
        disableMirroring()
    } else if let master = resolvedMaster(for: preferredMasterRole) {
        enableMirroring(master: master)
    }
}

// MARK: - Resolutions

func dedupedResolutions(for display: CGDirectDisplayID) -> [CGDisplayMode] {
    // Without this option, only raw unscaled native-pixel modes are returned — the
    // HiDPI "logical" resolutions shown in System Settings (e.g. 1792x1120) are omitted.
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else { return [] }
    var usable = modes.filter { $0.isUsableForDesktopGUI() }

    // Prefer true Retina-scaled "friendly" logical resolutions (pixel size = 2x logical size).
    // Non-Retina displays (e.g. an external monitor) have no such modes, so fall back to
    // the full list in that case rather than showing nothing.
    let retinaOnly = usable.filter { $0.pixelWidth == $0.width * 2 && $0.pixelHeight == $0.height * 2 }
    if !retinaOnly.isEmpty { usable = retinaOnly }

    var bestByRes: [String: CGDisplayMode] = [:]
    for mode in usable {
        let key = "\(mode.width)x\(mode.height)"
        if let existing = bestByRes[key] {
            if mode.refreshRate > existing.refreshRate { bestByRes[key] = mode }
        } else {
            bestByRes[key] = mode
        }
    }
    return bestByRes.values.sorted { $0.width * $0.height > $1.width * $1.height }
}

func applyResolution(display: CGDirectDisplayID, mode: CGDisplayMode) {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
    CGConfigureDisplayWithDisplayMode(cfg, display, mode, nil)
    CGCompleteDisplayConfiguration(cfg, .permanently)
}

func isCurrentMode(_ mode: CGDisplayMode, on display: CGDirectDisplayID) -> Bool {
    guard let current = CGDisplayCopyDisplayMode(display) else { return false }
    return current.width == mode.width
        && current.height == mode.height
        && abs(current.refreshRate - mode.refreshRate) < 0.5
}

func resolutionTitle(_ mode: CGDisplayMode) -> String {
    "\(mode.width) x \(mode.height) @ \(Int(mode.refreshRate.rounded()))Hz"
}

// Carries the (display, mode) pair through a menu item's representedObject.
final class ResolutionChoice: NSObject {
    let display: CGDirectDisplayID
    let mode: CGDisplayMode
    init(display: CGDirectDisplayID, mode: CGDisplayMode) {
        self.display = display
        self.mode = mode
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        if let button = statusItem.button {
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        let mirrored = isCurrentlyMirrored()
        let symbolName = mirrored ? "rectangle.on.rectangle" : "rectangle.split.2x1"
        let description = mirrored ? "Mirror" : "Extend"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = mirrored ? "🪞" : "⧉"
        }
    }

    @objc func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        guard !externalDisplays().isEmpty else { return }
        toggleMirror()
        updateIcon()
    }

    func showMenu() {
        let menu = NSMenu()

        let stateTitle = isCurrentlyMirrored() ? "目前：鏡像顯示 (Mirror)" : "目前：延伸桌面 (Extend)"
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())

        // Mirror source (which display's image wins when mirroring is on).
        let sourceMenu = NSMenu()
        let builtInItem = NSMenuItem(title: "以本機為主", action: #selector(setMasterRole(_:)), keyEquivalent: "")
        builtInItem.target = self
        builtInItem.representedObject = MasterRole.builtIn.rawValue
        builtInItem.state = preferredMasterRole == .builtIn ? .on : .off
        sourceMenu.addItem(builtInItem)

        let externalItem = NSMenuItem(title: "以外接為主", action: #selector(setMasterRole(_:)), keyEquivalent: "")
        externalItem.target = self
        externalItem.representedObject = MasterRole.external.rawValue
        externalItem.state = preferredMasterRole == .external ? .on : .off
        sourceMenu.addItem(externalItem)

        let sourceParent = NSMenuItem(title: "鏡像來源", action: nil, keyEquivalent: "")
        sourceParent.submenu = sourceMenu
        sourceParent.isEnabled = !externalDisplays().isEmpty
        menu.addItem(sourceParent)
        menu.addItem(NSMenuItem.separator())

        // Per-display resolution submenus.
        if let builtIn = builtInDisplay() {
            addResolutionSubmenu(to: menu, display: builtIn, label: "本機顯示器解析度")
        }
        for (index, external) in externalDisplays().enumerated() {
            let label = externalDisplays().count > 1 ? "外接顯示器 \(index + 1) 解析度" : "外接顯示器解析度"
            addResolutionSubmenu(to: menu, display: external, label: label)
        }
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func addResolutionSubmenu(to menu: NSMenu, display: CGDirectDisplayID, label: String) {
        let resolutions = dedupedResolutions(for: display)
        guard !resolutions.isEmpty else { return }

        let submenu = NSMenu()
        for mode in resolutions {
            let item = NSMenuItem(title: resolutionTitle(mode), action: #selector(selectResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ResolutionChoice(display: display, mode: mode)
            item.state = isCurrentMode(mode, on: display) ? .on : .off
            submenu.addItem(item)
        }

        let parent = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc func setMasterRole(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let role = MasterRole(rawValue: raw) else { return }
        preferredMasterRole = role
        // If already mirroring, re-apply immediately so the switch takes effect without a manual re-toggle.
        if isCurrentlyMirrored(), let master = resolvedMaster(for: role) {
            enableMirroring(master: master)
        }
        updateIcon()
    }

    @objc func selectResolution(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ResolutionChoice else { return }
        applyResolution(display: choice.display, mode: choice.mode)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
