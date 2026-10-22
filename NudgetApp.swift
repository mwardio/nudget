import AppKit
import CoreGraphics
import ServiceManagement

private enum PreferenceKey {
    static let interval = "io.mward.nudget.interval"
    static let wantsToRun = "io.mward.nudget.wantsToRun"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let intervals = [
        (seconds: 15, label: "15 seconds"),
        (seconds: 30, label: "30 seconds"),
        (seconds: 60, label: "1 minute"),
        (seconds: 120, label: "2 minutes"),
        (seconds: 300, label: "5 minutes"),
    ]

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Status: Starting…", action: nil, keyEquivalent: "")
    private let lastNudgeMenuItem = NSMenuItem(title: "Last nudge: Not yet", action: nil, keyEquivalent: "")
    private let runMenuItem = NSMenuItem(title: "Start Nudging", action: #selector(toggleRunning), keyEquivalent: "")
    private let nudgeNowMenuItem = NSMenuItem(title: "Nudge Now", action: #selector(nudgeNow), keyEquivalent: "n")
    private let launchAtLoginMenuItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private var intervalMenuItems: [Int: NSMenuItem] = [:]

    private var timer: Timer?
    private var interval = 30
    private var wantsToRun = true
    private var lastNudge: Date?
    private lazy var nuggetMenuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "NudgetIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        defaults.register(defaults: [
            PreferenceKey.interval: 30,
            PreferenceKey.wantsToRun: true,
        ])
        interval = validatedInterval(defaults.integer(forKey: PreferenceKey.interval))
        wantsToRun = defaults.bool(forKey: PreferenceKey.wantsToRun)

        configureStatusItem()
        configureMenu()
        reconcileRunningState(fireImmediately: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Accessibility can be granted while Nudget is already open. Rechecking
        // here makes the app start as soon as the user returns to its menu.
        reconcileRunningState(fireImmediately: true)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.setAccessibilityLabel("Nudget")
        statusItem.button?.toolTip = "Nudget"
        updateStatusIcon()
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusMenuItem.isEnabled = false
        lastNudgeMenuItem.isEnabled = false
        runMenuItem.target = self
        nudgeNowMenuItem.target = self
        launchAtLoginMenuItem.target = self

        menu.addItem(statusMenuItem)
        menu.addItem(lastNudgeMenuItem)
        menu.addItem(.separator())
        menu.addItem(runMenuItem)
        menu.addItem(nudgeNowMenuItem)

        let intervalParent = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu(title: "Interval")
        for option in intervals {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(changeInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.seconds
            intervalMenu.addItem(item)
            intervalMenuItems[option.seconds] = item
        }
        intervalParent.submenu = intervalMenu
        menu.addItem(intervalParent)

        menu.addItem(.separator())
        menu.addItem(launchAtLoginMenuItem)

        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let aboutItem = NSMenuItem(title: "About Nudget", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Nudget", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenu()
    }

    private var hasAccessibilityPermission: Bool {
        CGPreflightPostEventAccess()
    }

    private var isRunning: Bool {
        timer?.isValid == true
    }

    private func validatedInterval(_ candidate: Int) -> Int {
        intervals.contains(where: { $0.seconds == candidate }) ? candidate : 30
    }

    private func reconcileRunningState(fireImmediately: Bool) {
        if wantsToRun && hasAccessibilityPermission {
            startTimer(fireImmediately: fireImmediately)
        } else {
            stopTimer()
        }
        refreshMenu()
    }

    private func startTimer(fireImmediately: Bool) {
        guard !isRunning else {
            refreshMenu()
            return
        }

        let repeatingTimer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            self?.performNudge()
        }
        timer = repeatingTimer
        RunLoop.main.add(repeatingTimer, forMode: .common)

        if fireImmediately {
            performNudge()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    private func performNudge() -> Bool {
        guard hasAccessibilityPermission, let point = CGEvent(source: nil)?.location else {
            reconcileRunningState(fireImmediately: false)
            return false
        }

        let positions = [
            CGPoint(x: point.x + 1, y: point.y),
            CGPoint(x: point.x - 1, y: point.y),
            point,
        ]

        for position in positions {
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: position,
                mouseButton: .left
            ) else {
                return false
            }
            event.post(tap: .cghidEventTap)
        }

        lastNudge = Date()
        refreshMenu()
        return true
    }

    private func refreshMenu() {
        if !hasAccessibilityPermission {
            statusMenuItem.title = "Status: Accessibility Required"
            runMenuItem.title = "Grant Accessibility…"
            runMenuItem.isEnabled = true
            nudgeNowMenuItem.isEnabled = false
        } else if isRunning {
            statusMenuItem.title = "Status: Running every \(intervalLabel)"
            runMenuItem.title = "Stop Nudging"
            runMenuItem.isEnabled = true
            nudgeNowMenuItem.isEnabled = true
        } else {
            statusMenuItem.title = "Status: Paused"
            runMenuItem.title = "Start Nudging"
            runMenuItem.isEnabled = true
            nudgeNowMenuItem.isEnabled = true
        }

        if let lastNudge {
            lastNudgeMenuItem.title = "Last nudge: \(lastNudge.formatted(date: .omitted, time: .standard))"
        } else {
            lastNudgeMenuItem.title = "Last nudge: Not yet"
        }

        for (seconds, item) in intervalMenuItems {
            item.state = seconds == interval ? .on : .off
        }

        refreshLaunchAtLoginItem()
        updateStatusIcon()
    }

    private var intervalLabel: String {
        intervals.first(where: { $0.seconds == interval })?.label ?? "\(interval) seconds"
    }

    private func updateStatusIcon() {
        let toolTip: String
        let alpha: CGFloat

        if !hasAccessibilityPermission {
            toolTip = "Nudget needs Accessibility permission"
            alpha = 0.55
        } else if isRunning {
            toolTip = "Nudget is running every \(intervalLabel)"
            alpha = 1
        } else {
            toolTip = "Nudget is paused"
            alpha = 0.55
        }

        let fallbackImage = NSImage(
            systemSymbolName: "cursorarrow",
            accessibilityDescription: toolTip
        )
        fallbackImage?.isTemplate = true

        statusItem?.button?.image = nuggetMenuBarImage ?? fallbackImage
        statusItem?.button?.title = statusItem?.button?.image == nil ? "N" : ""
        statusItem?.button?.alphaValue = alpha
        statusItem?.button?.toolTip = toolTip
        statusItem?.button?.setAccessibilityHelp(toolTip)
    }

    private func refreshLaunchAtLoginItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginMenuItem.title = "Launch at Login"
            launchAtLoginMenuItem.state = .on
        case .requiresApproval:
            launchAtLoginMenuItem.title = "Launch at Login (Approval Required…)"
            launchAtLoginMenuItem.state = .mixed
        case .notRegistered, .notFound:
            launchAtLoginMenuItem.title = "Launch at Login"
            launchAtLoginMenuItem.state = .off
        @unknown default:
            launchAtLoginMenuItem.title = "Launch at Login"
            launchAtLoginMenuItem.state = .off
        }
    }

    @objc private func toggleRunning() {
        if !hasAccessibilityPermission {
            requestAccessibilityPermission()
            return
        }

        wantsToRun = !isRunning
        defaults.set(wantsToRun, forKey: PreferenceKey.wantsToRun)
        reconcileRunningState(fireImmediately: wantsToRun)
    }

    @objc private func nudgeNow() {
        _ = performNudge()
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        interval = validatedInterval(sender.tag)
        defaults.set(interval, forKey: PreferenceKey.interval)

        if isRunning {
            stopTimer()
            startTimer(fireImmediately: false)
        }
        refreshMenu()
    }

    @objc private func requestAccessibilityPermission() {
        wantsToRun = true
        defaults.set(true, forKey: PreferenceKey.wantsToRun)
        _ = CGRequestPostEventAccess()

        if hasAccessibilityPermission {
            reconcileRunningState(fireImmediately: true)
        } else {
            showAccessibilityHelp()
        }
    }

    private func showAccessibilityHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Nudget needs Accessibility permission"
        alert.informativeText = """
        Enable Nudget in System Settings → Privacy & Security → Accessibility, \
        then reopen the Nudget menu. No sudo is required.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp

        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } catch {
            presentError(title: "Could not update Launch at Login", error: error)
        }

        refreshLaunchAtLoginItem()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Nudget"
        alert.informativeText = """
        A tiny menu-bar utility that nudges the pointer by one pixel and returns \
        it, using only Apple frameworks.

        No clicks. No third-party tools. No sudo.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentError(title: String, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
