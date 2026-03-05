import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var monitor: AgentMonitor?
    var animationTimer: Timer?
    var animFrame = 0
    var isAnimating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBar(attention: 0, working: 0, completed: 0, idle: 0)

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 480)
        popover?.behavior = .transient
        popover?.animates = true

        monitor = AgentMonitor()
        monitor?.onUpdate = { [weak self] agents in
            DispatchQueue.main.async {
                self?.handleAgentUpdate(agents)
            }
        }
        monitor?.start()

        let contentView = PopoverView(monitor: monitor!)
        popover?.contentViewController = NSHostingController(rootView: contentView)

        // Check for updates
        UpdateChecker.shared.checkOnLaunch()
    }

    func handleAgentUpdate(_ agents: [DetectedAgent]) {
        let needsAttention = agents.filter { $0.status == .needsAttention }
        let working = agents.filter { $0.status == .running || $0.status == .thinking }
        let completed = agents.filter { $0.status == .completed }
        let idle = agents.filter { $0.status == .idle }

        updateStatusBar(attention: needsAttention.count, working: working.count, completed: completed.count, idle: idle.count)
    }

    func updateStatusBar(attention: Int, working: Int, completed: Int, idle: Int) {
        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        // Stop animation by default; re-start below if needed
        let shouldAnimate = working > 0

        if attention > 0 {
            stopAnimation()
            let symbolName = attention <= 50 ? "\(attention).circle.fill" : "exclamationmark.circle.fill"
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Needs Attention")?.withSymbolConfiguration(config) {
                let size = symbol.size
                let img = NSImage(size: size, flipped: false) { rect in
                    NSColor.systemOrange.set()
                    symbol.draw(in: rect)
                    NSGraphicsContext.current?.cgContext.setBlendMode(.sourceIn)
                    NSGraphicsContext.current?.cgContext.fill(rect)
                    return true
                }
                img.isTemplate = false
                button.image = constrainToMenuBar(img)
            }
            button.contentTintColor = nil
            button.alphaValue = 1.0
        } else if working > 0 {
            button.contentTintColor = nil
            button.alphaValue = 1.0
            // Render initial frame; animation timer handles the rest
            renderAnimatedIcon(for: button)
            if !isAnimating { startAnimation() }
        } else if completed > 0 {
            stopAnimation()
            let img = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Completed")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = constrainToMenuBar(img)
            button.contentTintColor = nil
            button.alphaValue = 0.8
        } else if idle > 0 {
            stopAnimation()
            let img = compositeIcon(innerAlpha: 1.0, outerAlpha: 1.0)
            img?.isTemplate = true
            button.image = constrainToMenuBar(img)
            button.contentTintColor = nil
            button.alphaValue = 0.7
        } else {
            stopAnimation()
            let img = compositeIcon(innerAlpha: 1.0, outerAlpha: 1.0)
            img?.isTemplate = true
            button.image = constrainToMenuBar(img)
            button.contentTintColor = nil
            button.alphaValue = 0.4
        }

        if !shouldAnimate && isAnimating {
            stopAnimation()
        }
    }

    // MARK: - Icon Compositing

    /// Composite sparkle + inner ring + outer ring at given opacities
    func compositeIcon(innerAlpha: CGFloat, outerAlpha: CGFloat) -> NSImage? {
        guard let sparkle = NSImage(named: "statusbar-sparkle"),
              let inner = NSImage(named: "statusbar-inner"),
              let outer = NSImage(named: "statusbar-outer") else { return nil }

        let size = sparkle.size
        let img = NSImage(size: size, flipped: false) { rect in
            outer.draw(in: rect, from: .zero, operation: .sourceOver, fraction: outerAlpha)
            inner.draw(in: rect, from: .zero, operation: .sourceOver, fraction: innerAlpha)
            sparkle.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        return img
    }

    func constrainToMenuBar(_ img: NSImage?) -> NSImage? {
        guard let original = img else { return nil }
        let maxHeight: CGFloat = 18
        let ratio = maxHeight / original.size.height
        original.size = NSSize(width: original.size.width * ratio, height: maxHeight)
        return original
    }

    // MARK: - Animation

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        animFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem?.button else { return }
            self.animFrame += 1
            self.renderAnimatedIcon(for: button)
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
        animFrame = 0
    }

    func renderAnimatedIcon(for button: NSStatusBarButton) {
        // Wave effect: inner ring pulses first, outer ring follows with a delay
        // Full cycle = ~1.8 seconds
        let t = Double(animFrame) * 0.05
        let cycleDuration = 1.8

        // Inner ring leads, outer ring follows with 0.4s offset
        let innerPhase = t.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        let outerPhase = (t - 0.4).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

        // Smooth pulse: 0.15 → 1.0 → 0.15
        let innerAlpha = CGFloat(0.15 + 0.85 * max(0, sin(innerPhase * .pi)))
        let outerAlpha = CGFloat(0.15 + 0.85 * max(0, sin(outerPhase * .pi)))

        let img = compositeIcon(innerAlpha: innerAlpha, outerAlpha: outerAlpha)
        img?.isTemplate = true
        button.image = constrainToMenuBar(img)
    }

    // MARK: - Notifications

    func sendNotification(for agents: [DetectedAgent]) {
        for agent in agents {
            let content = UNMutableNotificationContent()
            content.title = "⚠️ Agent Needs Attention"
            content.body = "\(agent.displayName) is waiting for input"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "agent-\(agent.pid)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
