import Foundation
import Combine
import AppKit

// MARK: - Agent Status

enum AgentStatus: Equatable {
    case running
    case thinking
    case needsAttention
    case idle
    case completed
}

// MARK: - Pending Tool Call

struct PendingToolCall {
    let toolName: String    // "Bash", "Write", "Edit", etc.
    let summary: String     // "npx tsc --noEmit", "/foo/bar.swift", etc.
}

// MARK: - Known Agent Binary

struct KnownAgent {
    let binaryName: String       // exact name for pgrep -x
    let displayName: String
    let icon: String             // SF Symbol
    let customIcon: String?      // Custom asset name
    let color: String            // hex

    static let all: [KnownAgent] = [
        KnownAgent(binaryName: "claude", displayName: "Claude Code", icon: "sparkles", customIcon: "claude-icon", color: "#D97706"),
        KnownAgent(binaryName: "codex", displayName: "Codex CLI", icon: "terminal.fill", customIcon: nil, color: "#10B981"),
        KnownAgent(binaryName: "gemini", displayName: "Gemini CLI", icon: "g.circle.fill", customIcon: "gemini-icon", color: "#3B82F6"),
        KnownAgent(binaryName: "aider", displayName: "Aider", icon: "hammer.fill", customIcon: nil, color: "#EC4899"),
        KnownAgent(binaryName: "continue", displayName: "Continue", icon: "arrow.triangle.2.circlepath", customIcon: nil, color: "#F59E0B"),
        KnownAgent(binaryName: "opencode", displayName: "OpenCode", icon: "chevron.left.forwardslash.chevron.right", customIcon: nil, color: "#0EA5E9"),
    ]
}

// MARK: - Detected Agent

class DetectedAgent: ObservableObject, Identifiable {
    let id: String
    let pid: Int32
    let kind: KnownAgent
    let startTime: Date
    var workingDirectory: String
    var commandLine: String
    var tty: String
    var ownerAppPID: pid_t?      // PID of the .app that owns this agent's terminal

    @Published var status: AgentStatus
    @Published var lastActivity: Date
    @Published var cpuPercent: Double = 0
    @Published var memoryMB: Double = 0
    @Published var currentActivity: String = ""
    @Published var childCommand: String = ""
    @Published var appIcon: NSImage?
    @Published var appName: String?
    @Published var pendingToolCall: PendingToolCall?

    var displayName: String {
        let dir = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return dir.isEmpty ? kind.displayName : "\(kind.displayName) — \(dir)"
    }

    var uptimeString: String {
        let seconds = Int(Date().timeIntervalSince(startTime))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    init(pid: Int32, kind: KnownAgent, workingDirectory: String, commandLine: String, tty: String) {
        self.id = "\(pid)"
        self.pid = pid
        self.kind = kind
        self.startTime = Date()
        self.workingDirectory = workingDirectory
        self.commandLine = commandLine
        self.tty = tty
        self.status = .running
        self.lastActivity = Date()
    }
}

// MARK: - Agent Monitor

class AgentMonitor: ObservableObject {
    @Published var agents: [DetectedAgent] = []
    @Published var lastScan: Date = Date()

    var onUpdate: (([DetectedAgent]) -> Void)?
    private var timer: Timer?
    private var knownPIDs: Set<Int32> = []

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let found = self.detectAgents()

            DispatchQueue.main.async {
                self.reconcile(found)
                self.lastScan = Date()
                self.onUpdate?(self.agents)
            }
        }
    }

    // MARK: - Layer 1: Detect agents via pgrep

    private func detectAgents() -> [(pid: Int32, kind: KnownAgent, cwd: String, cmd: String, tty: String)] {
        var results: [(pid: Int32, kind: KnownAgent, cwd: String, cmd: String, tty: String)] = []
        let myPID = ProcessInfo.processInfo.processIdentifier
        var seenPIDs = Set<Int32>()

        for agent in KnownAgent.all {
            // Try exact binary match first (compiled CLIs like claude),
            // then fall back to command-line match (Node/Python CLIs like gemini, codex)
            var pgrepOutput = shell("pgrep -x \(agent.binaryName) 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pgrepOutput.isEmpty {
                pgrepOutput = shell("pgrep -f 'bin/\(agent.binaryName)($| )' 2>/dev/null")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !pgrepOutput.isEmpty else { continue }

            let pids = pgrepOutput.components(separatedBy: "\n")
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                .sorted()  // Lowest PID first (parent process)

            // Track TTYs to avoid adding child workers on the same terminal
            var seenTTYs = Set<String>()

            for pid in pids {
                if pid == myPID || seenPIDs.contains(pid) { continue }

                // Get details: tty, stat, args
                let details = shell("ps -p \(pid) -o tty=,stat=,args= 2>/dev/null")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !details.isEmpty else { continue }

                let parts = details.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 2 else { continue }

                let tty = String(parts[0])
                // Skip processes not on a real TTY (GUI apps show "??")
                guard tty != "??" else { continue }
                // Skip duplicate agents on the same TTY (child node workers)
                guard !seenTTYs.contains(tty) else { continue }
                seenTTYs.insert(tty)

                let cmd = parts.count >= 3 ? String(parts[2]) : agent.binaryName
                let cwd = getWorkingDirectory(for: pid)
                results.append((pid: pid, kind: agent, cwd: cwd, cmd: cmd, tty: tty))
                seenPIDs.insert(pid)
            }
        }
        return results
    }

    // MARK: - Reconcile

    private func reconcile(_ found: [(pid: Int32, kind: KnownAgent, cwd: String, cmd: String, tty: String)]) {
        let foundPIDs = Set(found.map { $0.pid })

        // Remove dead agents
        agents.removeAll { !foundPIDs.contains($0.pid) }

        // Add new agents
        for item in found {
            if !knownPIDs.contains(item.pid) {
                let agent = DetectedAgent(
                    pid: item.pid,
                    kind: item.kind,
                    workingDirectory: item.cwd,
                    commandLine: item.cmd,
                    tty: item.tty
                )
                // Layer 2: find the owning app for this agent
                agent.ownerAppPID = findOwnerAppPID(pid: item.pid)
                if let ownerPID = agent.ownerAppPID, let app = NSRunningApplication(processIdentifier: ownerPID) {
                    agent.appIcon = app.icon
                    agent.appName = app.localizedName
                } else if let appName = findOwnerAppName(pid: item.pid) {
                    agent.appName = appName
                    let workspace = NSWorkspace.shared
                    if let path = workspace.fullPath(forApplication: appName) {
                        agent.appIcon = workspace.icon(forFile: path)
                    }
                }
                agents.append(agent)
                knownPIDs.insert(item.pid)
            }
        }

        // Update stats for all agents
        for agent in agents {
            updateStats(agent)
        }

        // Clean up dead PIDs
        knownPIDs = knownPIDs.intersection(foundPIDs)
    }

    // MARK: - Status Detection

    private func updateStats(_ agent: DetectedAgent) {
        // Get CPU and memory
        let statsOutput = shell("ps -p \(agent.pid) -o %cpu=,rss=,stat= 2>/dev/null")
        let statsParts = statsOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)

        var procState = ""
        if statsParts.count >= 2 {
            agent.cpuPercent = Double(statsParts[0]) ?? 0
            agent.memoryMB = (Double(statsParts[1]) ?? 0) / 1024.0
        }
        if statsParts.count >= 3 {
            procState = String(statsParts[2])
        }

        // Check if process is backgrounded or stopped first
        let isForeground = procState.contains("+")
        let isStopped = procState.contains("T")

        if isStopped {
            agent.status = .idle
            agent.currentActivity = "Stopped"
            return
        }
        if !isForeground && !procState.isEmpty {
            agent.status = .idle
            agent.currentActivity = "Backgrounded"
            return
        }

        // For Claude Code: use JSONL transcript for reliable status
        if agent.kind.binaryName == "claude" {
            if let status = claudeStatusFromTranscript(agent) {
                agent.status = status.status
                agent.currentActivity = status.activity
                if status.status == .thinking {
                    agent.lastActivity = Date()
                }
                return
            }
        }

        // Fallback for other agents: check child processes
        let childPids = shell("pgrep -P \(agent.pid) 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var hasActiveChildren = false
        var bestChild = ""

        if !childPids.isEmpty {
            let pidList = childPids.components(separatedBy: "\n").joined(separator: ",")
            let childOutput = shell("ps -o stat=,args= -p \(pidList) 2>/dev/null")

            for childLine in childOutput.components(separatedBy: "\n") {
                let trimmed = childLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let cParts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard cParts.count >= 2 else { continue }
                let stat = String(cParts[0])
                let childCmd = String(cParts[1])

                if childCmd.contains("pgrep") || childCmd.contains("ps -o") || childCmd.contains("ps -p") { continue }
                // Skip child processes that are the agent's own worker (e.g. node re-spawning gemini)
                if childCmd.contains("bin/\(agent.kind.binaryName)") { continue }
                let cmdLower = childCmd.lowercased()
                if cmdLower.hasPrefix("caffeinate") || cmdLower.hasPrefix("sleep") { continue }

                if stat.contains("R") || (stat.contains("S") && stat.contains("+") && !stat.contains("T")) {
                    hasActiveChildren = true
                    if bestChild.isEmpty {
                        bestChild = Self.readableCommand(childCmd)
                    }
                }
            }
        }

        agent.childCommand = bestChild

        if hasActiveChildren {
            agent.status = .thinking
            agent.currentActivity = bestChild
            agent.lastActivity = Date()
        } else {
            // Generic fallback: foreground + no active children = idle at prompt
            agent.status = .idle
            agent.currentActivity = "Ready"
        }
    }

    // MARK: - Claude Code Transcript-Based Status

    /// Read the Claude Code JSONL transcript to determine actual agent status.
    /// The transcript is the source of truth — if it says the agent finished its turn,
    /// the agent IS waiting for user input, regardless of how long ago that was.
    private func claudeStatusFromTranscript(_ agent: DetectedAgent) -> (status: AgentStatus, activity: String)? {
        // Convert working directory to Claude's project dir format:
        // /Users/foo/bar → -Users-foo-bar
        let projectDirName = agent.workingDirectory.replacingOccurrences(of: "/", with: "-")
        let projectDir = NSHomeDirectory() + "/.claude/projects/" + projectDirName

        // Find the most recently modified .jsonl file
        guard let jsonlPath = mostRecentFile(in: projectDir, extension: "jsonl") else { return nil }

        // Check file modification time
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: jsonlPath),
              let mtime = attrs[.modificationDate] as? Date else { return nil }

        let staleness = Date().timeIntervalSince(mtime)

        // Read recent lines and find the last assistant/user entry
        // (skip system/progress metadata lines that Claude appends after turns)
        guard let entry = readLastRelevantEntry(of: jsonlPath) else {
            return nil
        }

        let msgType = entry["type"] as? String ?? ""
        let message = entry["message"] as? [String: Any]
        let stopReason = message?["stop_reason"] as? String

        switch msgType {
        case "assistant":
            if stopReason == "end_turn" {
                // Agent finished its turn — task complete, no action needed
                // (this includes optional feedback prompts like "How is Claude doing?")
                agent.pendingToolCall = nil
                return (.completed, "Task completed")
            } else if stopReason == "tool_use" {
                // Agent wants to use a tool
                if staleness < 3 {
                    // File was just updated — tool is actively executing
                    agent.pendingToolCall = nil
                    return (.thinking, "Running tool...")
                } else {
                    // Tool call sitting there — waiting for user approval
                    if let contentArray = message?["content"] as? [[String: Any]] {
                        for block in contentArray {
                            if block["type"] as? String == "tool_use" {
                                let name = block["name"] as? String ?? "Tool"
                                let input = block["input"] as? [String: Any] ?? [:]
                                let summary = Self.toolSummary(name: name, input: input)
                                agent.pendingToolCall = PendingToolCall(toolName: name, summary: summary)
                                break
                            }
                        }
                    }
                    return (.needsAttention, "Waiting for tool approval")
                }
            } else {
                // stop_reason is null — still streaming response
                agent.pendingToolCall = nil
                if staleness < 15 {
                    return (.thinking, "Thinking...")
                } else {
                    // Streaming stopped without end_turn — likely waiting
                    return (.completed, "Task completed")
                }
            }

        case "user":
            // User sent a message or tool result — agent is working
            agent.pendingToolCall = nil
            if staleness < 15 {
                return (.thinking, "Thinking...")
            } else {
                // Agent should have responded by now
                return (.running, "Active")
            }

        default:
            return nil
        }
    }

    /// Find the most recently modified file with the given extension in a directory
    private func mostRecentFile(in directory: String, extension ext: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return nil }

        var bestPath: String?
        var bestDate: Date?

        for file in files where file.hasSuffix(".\(ext)") {
            let path = directory + "/" + file
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date {
                if bestDate == nil || mtime > bestDate! {
                    bestDate = mtime
                    bestPath = path
                }
            }
        }
        return bestPath
    }

    /// Read the last assistant or user entry from a JSONL file.
    /// Skips system/progress metadata lines that Claude appends after turns.
    private func readLastRelevantEntry(of path: String) -> [String: Any]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        // Read up to 32KB from the end — enough for several JSONL entries
        let readSize: UInt64 = min(fileSize, 32768)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()

        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .reversed()

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            if type == "assistant" || type == "user" {
                return json
            }
        }
        return nil
    }

    /// Extract a human-readable command from a full command path
    private static func readableCommand(_ cmd: String) -> String {
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return cmd }
        let binary = URL(fileURLWithPath: String(first)).lastPathComponent
        if parts.count > 1 {
            let args = String(parts[1]).prefix(60)
            return "\(binary) \(args)"
        }
        return binary
    }

    /// Generate a human-readable summary for a pending tool call
    private static func toolSummary(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            if let cmd = input["command"] as? String {
                return String(cmd.prefix(60))
            }
        case "Write", "Read", "Edit":
            if let path = input["file_path"] as? String {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        case "Glob":
            if let pattern = input["pattern"] as? String {
                return pattern
            }
        case "Grep":
            if let query = input["query"] as? String {
                return query
            }
        default:
            break
        }
        return name
    }

    // MARK: - Layer 2: Walk parent chain to find owning .app

    /// Walk the parent process chain to find the PID of the .app bundle that owns this terminal
    private func findOwnerAppPID(pid: Int32) -> pid_t? {
        var current = pid
        for _ in 0..<15 {
            let info = shell("ps -p \(current) -o ppid=,args= 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !info.isEmpty else { return nil }
            let parts = info.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            guard let ppid = Int32(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let cmd = String(parts[1])

            // Found a .app bundle — return THIS process's PID (current), not its parent
            if cmd.contains(".app/") || cmd.contains(".app ") {
                return current
            }
            if ppid <= 1 { return nil }
            current = ppid
        }
        return nil
    }

    // MARK: - Window Activation

    func activateAgent(_ agent: DetectedAgent) {
        let ownerPID = agent.ownerAppPID ?? findOwnerAppPID(pid: agent.pid)
        let folderName = URL(fileURLWithPath: agent.workingDirectory).lastPathComponent

        guard let appPID = ownerPID,
              let app = NSRunningApplication(processIdentifier: appPID) else {
            if let name = findOwnerAppName(pid: agent.pid) {
                shell("open -a \"\(name)\"")
            }
            return
        }

        guard !folderName.isEmpty else {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        // Check Accessibility permission — prompt user if not granted
        if !AXIsProcessTrusted() {
            // Activate the app anyway (best we can do without AX)
            app.activate(options: [.activateIgnoringOtherApps])
            // Prompt user to grant Accessibility — opens System Settings
            promptForAccessibility()
            return
        }

        // Use AX to raise the exact window
        raiseWindowViaAX(appPID: appPID, folderName: folderName, app: app)
    }

    /// Prompt the user to grant Accessibility permission using Apple's native dialog.
    /// Only shows the system prompt if not already trusted.
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Raise a specific window using the Accessibility API
    private func raiseWindowViaAX(appPID: pid_t, folderName: String, app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(appPID)

        // Set app as frontmost via AX + NSRunningApplication
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate(options: [.activateIgnoringOtherApps])

        // Find the matching window and raise it
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else { continue }

            if title.localizedCaseInsensitiveContains(folderName) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                return
            }
        }

        // No matching window found — just activate the app
    }

    /// Walk parent chain and return the human-readable app name (e.g. "Cursor", "Terminal")
    private func findOwnerAppName(pid: Int32) -> String? {
        var current = pid
        for _ in 0..<15 {
            let info = shell("ps -p \(current) -o ppid=,args= 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !info.isEmpty else { return nil }
            let parts = info.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            guard let ppid = Int32(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let cmd = String(parts[1])

            if cmd.contains(".app/") || cmd.contains(".app ") {
                // Extract "AppName" from "/Applications/AppName.app/..."
                if let range = cmd.range(of: #"[^/]+\.app"#, options: .regularExpression) {
                    return String(cmd[range]).replacingOccurrences(of: ".app", with: "")
                }
                return nil
            }
            if ppid <= 1 { return nil }
            current = ppid
        }
        return nil
    }

    // MARK: - Helpers

    private func getWorkingDirectory(for pid: Int32) -> String {
        let output = shell("lsof -p \(pid) -a -d cwd -Fn 2>/dev/null")
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        }
        return "~"
    }

    @discardableResult
    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
