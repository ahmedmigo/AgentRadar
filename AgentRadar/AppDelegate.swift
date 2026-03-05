import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var monitor: AgentMonitor?
    var animationTimer: Timer?
    var animFrame = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Check Accessibility silently — only prompt when user clicks an agent
        // (the prompt is handled in AgentMonitor.activateAgent)

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBar(attention: 0, working: 0, completed: 0, idle: 0)

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 480)
        popover?.behavior = .transient
        popover?.animates = true

        // Start monitor
        monitor = AgentMonitor()
        monitor?.onUpdate = { [weak self] agents in
            DispatchQueue.main.async {
                self?.handleAgentUpdate(agents)
            }
        }
        monitor?.start()

        // Update popover content
        let contentView = PopoverView(monitor: monitor!)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    func handleAgentUpdate(_ agents: [DetectedAgent]) {
        let needsAttention = agents.filter { $0.status == .needsAttention }
        let working = agents.filter { $0.status == .running || $0.status == .thinking }
        let completed = agents.filter { $0.status == .completed }
        let idle = agents.filter { $0.status == .idle }

        updateStatusBar(attention: needsAttention.count, working: working.count, completed: completed.count, idle: idle.count)

        if !needsAttention.isEmpty {
            sendNotification(for: needsAttention)
        }
    }

    func updateStatusBar(attention: Int, working: Int, completed: Int, idle: Int) {
        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        // Clear any text titles
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        var img: NSImage?

        if attention > 0 {
            // SF Symbols has numbered circles up to 50
            let symbolName = attention <= 50 ? "\(attention).circle.fill" : "exclamationmark.circle.fill"
            img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Needs Attention")?.withSymbolConfiguration(config)
            button.alphaValue = 1.0
        } else if working > 0 {
            img = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Working")?.withSymbolConfiguration(config)
            button.alphaValue = 1.0
        } else if completed > 0 {
            img = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Completed")?.withSymbolConfiguration(config)
            button.alphaValue = 0.8
        } else if idle > 0 {
            img = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Idle")?.withSymbolConfiguration(config)
            button.alphaValue = 0.7
        } else {
            img = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "No Agents")?.withSymbolConfiguration(config)
            button.alphaValue = 0.6
        }
        
        // Remove forced colors so macOS automatically handles Dark Mode (White) and Light Mode (Black)
        button.contentTintColor = nil
        img?.isTemplate = true
        button.image = img
    }

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

