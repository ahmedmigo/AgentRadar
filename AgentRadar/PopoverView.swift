import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: AgentMonitor

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(agentCount: monitor.agents.count, lastScan: monitor.lastScan)

            Divider()

            if monitor.agents.isEmpty {
                EmptyStateView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.agents) { agent in
                            AgentRowView(agent: agent, monitor: monitor)
                            if agent.id != monitor.agents.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }

            Divider()
            FooterBar()
        }
        .background(VisualEffectBlur())
        .frame(width: 340)
    }
}

// MARK: - Header

struct HeaderBar: View {
    let agentCount: Int
    let lastScan: Date

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Agent Radar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            HStack(spacing: 6) {
                if agentCount > 0 {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 3)
                                .scaleEffect(1.5)
                                .animation(.easeOut(duration: 1).repeatForever(autoreverses: true), value: agentCount)
                        )
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                }

                Text(agentCount == 0 ? "No agents" : "\(agentCount) active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    @ObservedObject var agent: DetectedAgent
    var monitor: AgentMonitor

    var statusColor: Color {
        switch agent.status {
        case .thinking:  return .green
        case .running:   return .blue
        case .needsAttention: return .orange
        case .idle:      return .gray
        case .completed: return .secondary
        }
    }

    var statusLabel: String {
        switch agent.status {
        case .thinking:  return "Thinking"
        case .running:   return "Running"
        case .needsAttention: return "Needs Input"
        case .idle:      return "Idle"
        case .completed: return "Done"
        }
    }

    var agentColor: Color {
        Color(hex: agent.kind.color) ?? .orange
    }

    var body: some View {
        Button(action: { monitor.activateAgent(agent) }) {
            HStack(spacing: 14) {
                    // Main Icon (App Icon) with small badge (Agent Icon)
                    ZStack(alignment: .bottomTrailing) {
                        if let appIcon = agent.appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "terminal.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        // Small badge for agent type
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .frame(width: 18, height: 18)
                                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                            
                            if let customIcon = agent.kind.customIcon {
                                Image(customIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else {
                                Circle()
                                    .fill(agentColor)
                                    .frame(width: 14, height: 14)
                                Image(systemName: agent.kind.icon)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .offset(x: 4, y: 4)
                    }
                    .padding(.trailing, 4)

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(agent.appName ?? agent.kind.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(URL(fileURLWithPath: agent.workingDirectory).lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        // Activity line
                        HStack(spacing: 5) {
                            if agent.status == .thinking {
                                AnimatedGradientText(text: agent.currentActivity.isEmpty ? "Thinking..." : agent.currentActivity)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else if agent.status == .needsAttention {
                                if let tool = agent.pendingToolCall {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.orange)
                                            Text(tool.toolName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.orange)
                                        }
                                        Text(tool.summary)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                } else {
                                    Text("Waiting for your input")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                            } else if agent.status == .idle {
                                Text(agent.currentActivity.isEmpty ? "Idle" : agent.currentActivity)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(agent.currentActivity.isEmpty ? statusLabel : agent.currentActivity)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    // Uptime + open hint
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(agent.uptimeString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)

                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(agent.status == .needsAttention ? Color.orange.opacity(0.15) : Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        )
    }
}

// MARK: - Animated Text

struct AnimatedGradientText: View {
    let text: String
    @State private var isAnimating = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .primary, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: isAnimating ? geo.size.width : -geo.size.width * 2)
                }
            )
            .mask(Text(text).font(.system(size: 12, weight: .medium)))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            VStack(spacing: 6) {
                Text("No agents detected")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Start Claude Code, Codex, Gemini CLI,\nor any AI coding agent to see it here.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(height: 280)
    }
}

struct FooterBar: View {
    var body: some View {
        HStack {
            Text("Agent Radar")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 4) {
                    Text("Quit")
                    Image(systemName: "power")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .menu
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
