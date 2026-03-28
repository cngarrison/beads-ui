// BeadsUI.swift
// Single-file SwiftUI macOS app for creating beads issues via `bd create`.
// Build: make    Run: make run

import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct BeadsUIApp: App {
    init() {
        // Explicitly set regular activation policy so the app appears
        // in the Dock and ⌘-Tab switcher when built outside of Xcode.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Beads Issue Creator") {
            ContentView()
        }
        .defaultSize(width: 640, height: 780)
    }
}

// MARK: - Domain Enums & Models

enum AppTab: Hashable { case create, issues }

enum IssueType: String, CaseIterable, Identifiable {
    case task, bug, feature, epic, chore
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Priority: String, CaseIterable, Identifiable {
    case p0 = "0", p1 = "1", p2 = "2", p3 = "3", p4 = "4"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .p0: return "P0 \u{2013} Critical"
        case .p1: return "P1 \u{2013} High"
        case .p2: return "P2 \u{2013} Medium (default)"
        case .p3: return "P3 \u{2013} Low"
        case .p4: return "P4 \u{2013} Backlog"
        }
    }
}

enum BeadsError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg):
            return msg.isEmpty ? "`bd` command failed with no output" : msg
        }
    }
}

struct BeadsIssue: Identifiable {
    let id: String
    let statusSymbol: String
    let statusColor: Color
    let priority: String
    let title: String
}

// MARK: - Beads Runner

enum BeadsRunner {

    // MARK: Create

    static func create(
        title: String, description: String, type: IssueType, priority: Priority,
        assignee: String, labels: String, externalRef: String,
        designNotes: String, acceptanceCriteria: String, dependencies: String,
        workingDirectory: String
    ) throws -> String {
        var args = ["bd", "create"]
        args += ["--title", title]
        args += ["--type", type.rawValue]
        args += ["--priority", priority.rawValue]
        if !description.isEmpty        { args += ["--description", description] }
        if !assignee.isEmpty           { args += ["--assignee", assignee] }
        if !labels.isEmpty             { args += ["--labels", labels] }
        if !externalRef.isEmpty        { args += ["--external-ref", externalRef] }
        if !designNotes.isEmpty        { args += ["--design", designNotes] }
        if !acceptanceCriteria.isEmpty { args += ["--acceptance", acceptanceCriteria] }
        if !dependencies.isEmpty       { args += ["--deps", dependencies] }

        let (stdout, stderr, status) = try run(args, in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : msg)
        }
        let combined = stdout + stderr
        let pat = #"Created issue:\s+(\S+)"#
        if let re = try? NSRegularExpression(pattern: pat),
           let m  = re.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           let r  = Range(m.range(at: 1), in: combined) {
            return String(combined[r])
        }
        return "(created)"
    }

    // MARK: List

    static func list(workingDirectory: String) throws -> [BeadsIssue] {
        let (stdout, stderr, status) = try run(["bd", "list", "--flat"], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
        return parseIssues(from: stdout)
    }

    // MARK: Parse

    private static func parseIssues(from output: String) -> [BeadsIssue] {
        // Line format: <status> <id> [<sym> <priority>] [<type>] - <title>
        // e.g.:        ○ beads-ui-beb [● P2] [task] - Add icon for the app
        let pattern = "^(\\S)\\s+(\\S+)\\s+\\[\\S+\\s+(P\\d)\\]\\s+\\[\\S+\\]\\s+-\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            let ns = NSRange(t.startIndex..., in: t)
            guard let m = regex.firstMatch(in: t, range: ns),
                  let r1 = Range(m.range(at: 1), in: t),
                  let r2 = Range(m.range(at: 2), in: t),
                  let r3 = Range(m.range(at: 3), in: t),
                  let r4 = Range(m.range(at: 4), in: t) else { return nil }
            let sym = String(t[r1])
            let color: Color = {
                switch sym {
                case "\u{25CB}": return .primary   // ○ open
                case "\u{25D0}": return .blue       // ◐ in_progress
                case "\u{2713}": return .green      // ✓ closed
                case "\u{2744}": return .purple     // ❄ deferred
                default:         return .orange     // ● blocked + unknown
                }
            }()
            return BeadsIssue(
                id: String(t[r2]), statusSymbol: sym, statusColor: color,
                priority: String(t[r3]), title: String(t[r4])
            )
        }
    }

    // MARK: Process helper

    private static func run(_ args: [String], in directory: String) throws -> (String, String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        if !directory.isEmpty { p.currentDirectoryURL = URL(fileURLWithPath: directory) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError  = err
        try p.run()
        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, p.terminationStatus)
    }
}

// MARK: - Content View (tab container)

struct ContentView: View {
    @AppStorage("workingDirectory") private var workingDirectory: String = ""
    @State private var currentTab: AppTab = .create

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            switch currentTab {
            case .create:
                CreateIssueView(workingDirectory: $workingDirectory)
            case .issues:
                IssueListView(workingDirectory: workingDirectory)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $currentTab) {
                Label("Create", systemImage: "plus.circle").tag(AppTab.create)
                Label("Issues", systemImage: "list.bullet").tag(AppTab.issues)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            Image(systemName: "folder").foregroundStyle(.secondary)
            if workingDirectory.isEmpty {
                Text("No repository selected")
                    .foregroundStyle(.secondary).italic().font(.subheadline)
            } else {
                Text(URL(fileURLWithPath: workingDirectory).lastPathComponent)
                    .font(.subheadline).lineLimit(1)
                    .help(workingDirectory)
            }
            Button("Choose\u{2026}") { pickWorkingDirectory() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Beads Repository"; panel.prompt = "Select"
        if !workingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}

// MARK: - Create Issue View

struct CreateIssueView: View {
    @Binding var workingDirectory: String

    @State private var title              = ""
    @State private var description        = ""
    @State private var issueType: IssueType = .task
    @State private var priority: Priority   = .p2
    @State private var assignee           = ""
    @State private var labels             = ""
    @State private var externalRef        = ""
    @State private var designNotes        = ""
    @State private var acceptanceCriteria = ""
    @State private var dependencies       = ""

    @State private var isSubmitting   = false
    @State private var createdIssueID: String? = nil
    @State private var errorMessage:  String? = nil
    @State private var showCopied     = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !workingDirectory.isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            if let id  = createdIssueID { successBanner(issueID: id) }
            if let err = errorMessage   { errorBanner(message: err) }
            ScrollView { formContent.padding() }
            Divider()
            bottomBar
        }
    }

    // MARK: Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            field("Title", required: true) {
                TextField("Brief summary of the issue", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            field("Description") {
                textArea($description,
                         placeholder: "Explain why this issue exists and what needs to be done\u{2026}",
                         height: 80)
            }
            HStack(alignment: .top, spacing: 20) {
                field("Type") {
                    Picker("", selection: $issueType) {
                        ForEach(IssueType.allCases) { t in Text(t.label).tag(t) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                field("Priority") {
                    Picker("", selection: $priority) {
                        ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                field("Assignee") {
                    TextField("username or email", text: $assignee).textFieldStyle(.roundedBorder)
                }
                field("Labels") {
                    TextField("urgent, backend, needs-review", text: $labels).textFieldStyle(.roundedBorder)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                field("External Reference") {
                    TextField("gh-123, jira-ABC-456", text: $externalRef).textFieldStyle(.roundedBorder)
                }
                field("Dependencies") {
                    TextField("discovered-from:bd-20, blocks:bd-15", text: $dependencies).textFieldStyle(.roundedBorder)
                }
            }
            field("Design Notes") {
                textArea($designNotes,
                         placeholder: "Describe the technical approach or design details\u{2026}",
                         height: 70)
            }
            field("Acceptance Criteria") {
                textArea($acceptanceCriteria,
                         placeholder: "List the criteria for completion\u{2026}",
                         height: 70)
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Clear") { clearForm() }.buttonStyle(.bordered).disabled(isSubmitting)
            Spacer()
            if isSubmitting { ProgressView().scaleEffect(0.75).padding(.trailing, 4) }
            Button("Create Issue") { submitIssue() }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding().background(.bar)
    }

    // MARK: Banners

    @ViewBuilder
    private func successBanner(issueID: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            (Text("Created: ").bold()
             + Text(issueID).font(.system(.body, design: .monospaced)))
            Spacer()
            Button(showCopied ? "Copied!" : "Copy ID") { copyToClipboard(issueID) }
                .buttonStyle(.bordered).controlSize(.small)
            Button("Dismiss") { createdIssueID = nil }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.green.opacity(0.12))
    }

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }

    // MARK: Helpers

    @ViewBuilder
    private func field<C: View>(_ label: String, required: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(label).font(.subheadline).fontWeight(.medium)
                if required { Text("*").foregroundStyle(.red).font(.subheadline) }
            }
            content()
        }
    }

    private func textArea(_ text: Binding<String>, placeholder: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .frame(height: height)
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func clearFormFields() {
        title = ""; description = ""; issueType = .task; priority = .p2
        assignee = ""; labels = ""; externalRef = ""
        designNotes = ""; acceptanceCriteria = ""; dependencies = ""
        errorMessage = nil
    }

    private func clearForm() { clearFormFields(); createdIssueID = nil }

    private func copyToClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
    }

    private func submitIssue() {
        guard !workingDirectory.isEmpty else { errorMessage = "No repository selected."; return }
        isSubmitting = true; errorMessage = nil; createdIssueID = nil
        let s = (title: title, desc: description, type: issueType, pri: priority,
                 assignee: assignee, labels: labels, ref: externalRef,
                 design: designNotes, ac: acceptanceCriteria, deps: dependencies,
                 dir: workingDirectory)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let id = try BeadsRunner.create(
                    title: s.title, description: s.desc, type: s.type, priority: s.pri,
                    assignee: s.assignee, labels: s.labels, externalRef: s.ref,
                    designNotes: s.design, acceptanceCriteria: s.ac, dependencies: s.deps,
                    workingDirectory: s.dir)
                DispatchQueue.main.async { isSubmitting = false; createdIssueID = id; clearFormFields() }
            } catch {
                DispatchQueue.main.async { isSubmitting = false; errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Issue List View

struct IssueListView: View {
    let workingDirectory: String

    @State private var issues:       [BeadsIssue] = []
    @State private var isLoading     = false
    @State private var errorMessage: String? = nil
    @State private var copiedID:     String? = nil

    var body: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider()
            listContent
        }
        .task { await loadIssues() }
        .onChange(of: workingDirectory) { _ in Task { await loadIssues() } }
    }

    private var listToolbar: some View {
        HStack {
            if !issues.isEmpty {
                Text("\(issues.count) issue\(issues.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary).font(.subheadline)
            }
            Spacer()
            Button { Task { await loadIssues() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(isLoading || workingDirectory.isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var listContent: some View {
        if workingDirectory.isEmpty {
            emptyState(icon: "folder.badge.questionmark",
                       title: "No Repository Selected",
                       message: "Use the Choose\u{2026} button to select a beads repository.")
        } else if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading issues\u{2026}").foregroundStyle(.secondary).font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36)).foregroundStyle(.orange)
                Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadIssues() } }.buttonStyle(.bordered)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if issues.isEmpty {
            emptyState(icon: "tray",
                       title: "No Issues",
                       message: "This repository has no open issues.")
        } else {
            List(issues) { issue in
                IssueRow(issue: issue, copiedID: $copiedID)
            }
            .listStyle(.plain)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadIssues() async {
        guard !workingDirectory.isEmpty else { return }
        isLoading = true; errorMessage = nil
        let dir = workingDirectory
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.list(workingDirectory: dir)
            }.value
            issues = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Issue Row

struct IssueRow: View {
    let issue: BeadsIssue
    @Binding var copiedID: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(issue.statusSymbol)
                .foregroundStyle(issue.statusColor)
                .frame(width: 16)

            Text(issue.id)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            priorityBadge(issue.priority)

            Text(issue.title).lineLimit(1)

            Spacer()

            if copiedID == issue.id {
                Text("Copied!").font(.caption).foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { copyID() }
        .help("Click to copy \(issue.id) to clipboard")
        .padding(.vertical, 2)
    }

    private func priorityBadge(_ p: String) -> some View {
        let color: Color = {
            switch p {
            case "P0": return .red
            case "P1": return .orange
            case "P2": return .blue
            case "P3": return .teal
            default:   return .secondary
            }
        }()
        return Text(p)
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private func copyID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.id, forType: .string)
        withAnimation { copiedID = issue.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedID == issue.id { withAnimation { copiedID = nil } }
        }
    }
}
