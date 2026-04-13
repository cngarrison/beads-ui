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
    let title: String
    let status: String       // "open", "in_progress", "closed", "deferred", "blocked"
    let priority: Int        // 0–4
    let issueType: String?   // "task", "bug", "feature", etc.
    let parentID: String?
    let dependencyCount: Int      // issues this one depends on
    let dependentCount:  Int      // issues depending on this one
    var children: [BeadsIssue]?   // nil = leaf node

    var statusSymbol: String {
        switch status {
        case "open":        return "\u{25CB}"  // ○
        case "in_progress": return "\u{25D0}"  // ◐
        case "closed":      return "\u{2713}"  // ✓
        case "deferred":    return "\u{2744}"  // ❄
        default:            return "\u{25CF}"  // ● blocked/unknown
        }
    }

    var statusColor: Color {
        switch status {
        case "open":        return .primary
        case "in_progress": return .blue
        case "closed":      return .green
        case "deferred":    return .purple
        default:            return .orange
        }
    }

    var priorityLabel: String { "P\(priority)" }
}

// Structured detail returned by `bd show --json <id>`
struct BeadsIssueDetail: Decodable {
    let id: String
    let title: String
    let description: String?
    let design: String?
    let acceptanceCriteria: String?   // JSON key "acceptance_criteria"
    let status: String
    let priority: Int
    let issueType: String?
    let assignee: String?             // JSON key "assignee" (display name)
    let owner: String?                // email address
    let labels: [String]?             // JSON key "labels"
    let notes: String?
    let comments: [BeadsComment]?
    let dependencies: [BeadsDependency]?
    enum CodingKeys: String, CodingKey {
        case id, title, description, design, status, owner, assignee, labels, notes, comments, dependencies
        case priority, issueType = "issue_type"
        case acceptanceCriteria = "acceptance_criteria"
    }
}

struct BeadsDependency: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let dependencyType: String?   // "blocks", "blocked-by", "discovered-from", etc.
    enum CodingKeys: String, CodingKey {
        case id, title, status, priority
        case dependencyType = "dependency_type"
    }
}

struct BeadsComment: Decodable, Identifiable {
    let id: String
    let author: String
    let text: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, author, text
        case createdAt = "created_at"
    }
}

// Shared form field state — used by both CreateIssueView and IssueEditSheet
struct IssueFormFields {
    var title              = ""
    var description        = ""
    var issueType: IssueType = .task
    var priority: Priority   = .p2
    var assignee           = ""
    var labels             = ""
    var externalRef        = ""
    var designNotes        = ""
    var acceptanceCriteria = ""
    var dependencies       = ""
    var notes              = ""

    static func from(_ detail: BeadsIssueDetail) -> IssueFormFields {
        var f = IssueFormFields()
        f.title              = detail.title
        f.description        = detail.description ?? ""
        f.designNotes        = detail.design ?? ""
        f.acceptanceCriteria = detail.acceptanceCriteria ?? ""
        f.assignee           = detail.assignee ?? detail.owner ?? ""  // prefer display name
        f.labels             = detail.labels?.joined(separator: ", ") ?? ""
        f.notes              = detail.notes ?? ""
        if let t = detail.issueType, let it = IssueType(rawValue: t) { f.issueType = it }
        if let p = Priority(rawValue: String(detail.priority))        { f.priority  = p }
        return f
    }
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
        let (stdout, stderr, status) = try run(["bd", "list", "--json", "--limit", "0"], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
        return try buildTree(from: stdout)
    }

    // MARK: Show (plain text — used by IssueDetailSheet)

    static func show(id: String, workingDirectory: String) throws -> String {
        let (stdout, stderr, status) = try run(["bd", "show", id], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
        return stdout
    }

    // MARK: Show Detail (JSON — used by IssueEditSheet for pre-populating the form)

    static func showDetail(id: String, workingDirectory: String) throws -> BeadsIssueDetail {
        let (stdout, stderr, status) = try run(["bd", "show", "--json", id], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
        let results = try JSONDecoder().decode([BeadsIssueDetail].self, from: Data(stdout.utf8))
        guard let first = results.first else {
            throw BeadsError.commandFailed("No detail returned for issue \(id)")
        }
        return first
    }

    // MARK: Update

    static func update(id: String, fields: IssueFormFields, workingDirectory: String) throws {
        var args = ["bd", "update", id]
        // Title is always passed (required field)
        args += ["--title", fields.title]
        // Type and priority are always sent (pickers always have a value)
        args += ["--type", fields.issueType.rawValue]
        args += ["--priority", fields.priority.rawValue]
        // Optional fields: only pass when non-empty to avoid unintentionally blanking data
        if !fields.description.isEmpty { args += ["--description", fields.description] }
        if !fields.assignee.isEmpty    { args += ["--assignee",    fields.assignee] }
        if !fields.labels.isEmpty      { args += ["--set-labels",  fields.labels] }
        if !fields.designNotes.isEmpty { args += ["--design",      fields.designNotes] }
        // Acceptance criteria — only pass when non-empty (same safety policy as other optional fields)
        if !fields.acceptanceCriteria.isEmpty { args += ["--acceptance", fields.acceptanceCriteria] }
        // Notes — only pass when non-empty
        if !fields.notes.isEmpty { args += ["--notes", fields.notes] }
        // Labels — split on comma, trim whitespace, pass each with --set-labels
        // Only pass when non-empty to avoid accidentally clearing labels
        if !fields.labels.isEmpty {
            let labelList = fields.labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for label in labelList {
                args += ["--set-labels", label]
            }
        }
        // Note: --external-ref and --deps are intentionally omitted since
        // we cannot pre-populate them from the JSON response and would wipe existing data.

        let (stdout, stderr, status) = try run(args, in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : msg)
        }
    }

    // MARK: Add Comment

    static func addComment(id: String, text: String, workingDirectory: String) throws {
        let (stdout, stderr, status) = try run(["bd", "comments", "add", id, text], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
    }

    // MARK: Add Dependency

    static func addDependency(issueID: String, depID: String, type depType: String, workingDirectory: String) throws {
        var args = ["bd", "link", issueID, depID]
        if !depType.isEmpty && depType != "blocks" { args += ["--type", depType] }
        let (stdout, stderr, status) = try run(args, in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
    }

    // MARK: Remove Dependency

    static func removeDependency(issueID: String, depID: String, workingDirectory: String) throws {
        let (stdout, stderr, status) = try run(["bd", "dep", "remove", issueID, depID], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
    }

    // MARK: Close

    static func close(id: String, workingDirectory: String) throws {
        let (stdout, stderr, status) = try run(["bd", "close", id], in: workingDirectory)
        if status != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsError.commandFailed(msg.isEmpty ? stdout : msg)
        }
    }

    // MARK: Parse (JSON → tree)

    private static func buildTree(from json: String) throws -> [BeadsIssue] {
        struct RawIssue: Decodable {
            let id: String
            let title: String
            let status: String
            let priority: Int
            let issueType: String?
            let parent: String?
            let dependencyCount: Int?
            let dependentCount:  Int?
            enum CodingKeys: String, CodingKey {
                case id, title, status, priority, parent
                case issueType = "issue_type"
                case dependencyCount = "dependency_count"
                case dependentCount  = "dependent_count"
            }
        }

        let raw = try JSONDecoder().decode([RawIssue].self, from: Data(json.utf8))

        // Build flat map and child index
        var nodeMap: [String: BeadsIssue] = [:]
        var childIndex: [String: [String]] = [:]   // parentID → [childID]
        for r in raw {
            nodeMap[r.id] = BeadsIssue(id: r.id, title: r.title, status: r.status,
                                       priority: r.priority, issueType: r.issueType,
                                       parentID: r.parent,
                                       dependencyCount: r.dependencyCount ?? 0,
                                       dependentCount:  r.dependentCount  ?? 0,
                                       children: nil)
            if let p = r.parent { childIndex[p, default: []].append(r.id) }
        }

        // Recursively attach children
        func build(_ id: String) -> BeadsIssue? {
            guard var node = nodeMap[id] else { return nil }
            let kids = childIndex[id] ?? []
            if !kids.isEmpty { node.children = kids.compactMap { build($0) } }
            return node
        }

        // Roots: no parent, or parent not present in this result set
        let rootIDs = raw.filter { r in
            guard let p = r.parent else { return true }
            return nodeMap[p] == nil   // orphan → promote to root
        }.map { $0.id }

        return rootIDs.compactMap { build($0) }
    }

    // MARK: Process helper

    private static func run(_ args: [String], in directory: String) throws -> (String, String, Int32) {
        let p = Process()
        // Use a login shell so GUI-launched apps (Dock, Finder) inherit the
        // user's full PATH (e.g. /usr/local/bin where `bd` typically lives).
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''" ) + "'" }.joined(separator: " ")
        p.arguments = ["-l", "-c", cmd]
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
    @AppStorage("recentProjects") private var recentProjectsJSON: String = "[]"
    @State private var currentTab: AppTab = .issues

    private var recentProjects: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentProjectsJSON.utf8))) ?? []
    }

    private func addToRecents(_ path: String) {
        var list = recentProjects
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentProjectsJSON = (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]"
    }

    private func clearRecents() { recentProjectsJSON = "[]" }

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
        .onAppear {
            if !workingDirectory.isEmpty { addToRecents(workingDirectory) }
        }
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
            projectSelector
            Button("Choose\u{2026}") { pickWorkingDirectory() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var projectSelector: some View {
        let recents = recentProjects
        if recents.isEmpty {
            if workingDirectory.isEmpty {
                Text("No repository selected")
                    .foregroundStyle(.secondary).italic().font(.subheadline)
            } else {
                Text(URL(fileURLWithPath: workingDirectory).lastPathComponent)
                    .font(.subheadline).lineLimit(1)
                    .help(workingDirectory)
            }
        } else {
            Menu {
                ForEach(recents, id: \.self) { path in
                    Button {
                        workingDirectory = path
                    } label: {
                        if path == workingDirectory {
                            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "checkmark")
                        } else {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                        }
                    }
                    .help(path)
                }
                Divider()
                Button("Clear Recents") { clearRecents() }
            } label: {
                HStack(spacing: 4) {
                    Text(workingDirectory.isEmpty ? "No repository" :
                         URL(fileURLWithPath: workingDirectory).lastPathComponent)
                        .font(.subheadline)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(workingDirectory)
        }
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
            addToRecents(url.path)
        }
    }
}

// MARK: - Form Helpers (file-scope, shared by CreateIssueView and IssueEditSheet)

@ViewBuilder
func formField<C: View>(
    _ label: String,
    required: Bool = false,
    @ViewBuilder content: () -> C
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 2) {
            Text(label).font(.subheadline).fontWeight(.medium)
            if required { Text("*").foregroundStyle(.red).font(.subheadline) }
        }
        content()
    }
}

func formTextArea(
    _ text: Binding<String>,
    placeholder: String,
    height: CGFloat
) -> some View {
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

// MARK: - Issue Form Content

/// Reusable form body shared by CreateIssueView and IssueEditSheet.
/// Contains all input fields; does NOT include banners, ScrollView, or bottom bar.
struct IssueFormContent: View {
    @Binding var fields: IssueFormFields
    var showDependencies: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            formField("Title", required: true) {
                TextField("Brief summary of the issue", text: $fields.title)
                    .textFieldStyle(.roundedBorder)
            }
            formField("Description") {
                formTextArea($fields.description,
                             placeholder: "Explain why this issue exists and what needs to be done\u{2026}",
                             height: 80)
            }
            HStack(alignment: .top, spacing: 20) {
                formField("Type") {
                    Picker("", selection: $fields.issueType) {
                        ForEach(IssueType.allCases) { t in Text(t.label).tag(t) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                formField("Priority") {
                    Picker("", selection: $fields.priority) {
                        ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                formField("Assignee") {
                    TextField("username or email", text: $fields.assignee).textFieldStyle(.roundedBorder)
                }
                formField("Labels") {
                    TextField("urgent, backend, needs-review", text: $fields.labels).textFieldStyle(.roundedBorder)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                formField("External Reference") {
                    TextField("gh-123, jira-ABC-456", text: $fields.externalRef).textFieldStyle(.roundedBorder)
                }
                if showDependencies {
                    formField("Dependencies") {
                        TextField("discovered-from:bd-20, blocks:bd-15", text: $fields.dependencies).textFieldStyle(.roundedBorder)
                    }
                }
            }
            formField("Design Notes") {
                formTextArea($fields.designNotes,
                             placeholder: "Describe the technical approach or design details\u{2026}",
                             height: 70)
            }
            formField("Acceptance Criteria") {
                formTextArea($fields.acceptanceCriteria,
                             placeholder: "List the criteria for completion\u{2026}",
                             height: 70)
            }
        }
    }
}

// MARK: - Create Issue View

struct CreateIssueView: View {
    @Binding var workingDirectory: String

    @State private var fields = IssueFormFields()

    @State private var isSubmitting   = false
    @State private var createdIssueID: String? = nil
    @State private var errorMessage:  String? = nil
    @State private var showCopied     = false

    private var canSubmit: Bool {
        !fields.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !workingDirectory.isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            if let id  = createdIssueID { successBanner(issueID: id) }
            if let err = errorMessage   { errorBanner(message: err) }
            ScrollView { IssueFormContent(fields: $fields).padding() }
            Divider()
            bottomBar
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

    // MARK: Actions

    private func clearFormFields() {
        fields = IssueFormFields()
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
        let snap = fields
        let dir  = workingDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let id = try BeadsRunner.create(
                    title: snap.title, description: snap.description,
                    type: snap.issueType, priority: snap.priority,
                    assignee: snap.assignee, labels: snap.labels,
                    externalRef: snap.externalRef, designNotes: snap.designNotes,
                    acceptanceCriteria: snap.acceptanceCriteria,
                    dependencies: snap.dependencies,
                    workingDirectory: dir)
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
    @State private var detailIssue:  BeadsIssue? = nil
    @State private var editIssue:    BeadsIssue? = nil
    @State private var listWidth:    CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider()
            listContent
        }
        .task { await loadIssues() }
        .onChange(of: workingDirectory) { newDir in Task { await loadIssues(dir: newDir) } }
        .sheet(item: $detailIssue) { issue in
            IssueDetailSheet(issue: issue, workingDirectory: workingDirectory)
        }
        .sheet(item: $editIssue) { issue in
            IssueEditSheet(
                issue: issue,
                workingDirectory: workingDirectory,
                preferredWidth: listWidth,
                onSaved: { Task { await loadIssues() } }
            )
        }
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
            List(issues, children: \.children) { issue in
                IssueRow(issue: issue, copiedID: $copiedID,
                         onEdit: { editIssue = issue },
                         onShowDetail: { detailIssue = issue },
                         onClose: { Task { await closeIssue(issue) } })
            }
            .listStyle(.plain)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { listWidth = geo.size.width }
                        .onChange(of: geo.size.width) { listWidth = $0 }
                }
            )
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

    private func closeIssue(_ issue: BeadsIssue) async {
        let dir = workingDirectory
        do {
            try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.close(id: issue.id, workingDirectory: dir)
            }.value
            await loadIssues()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadIssues(dir explicitDir: String? = nil) async {
        let dir = explicitDir ?? workingDirectory
        guard !dir.isEmpty else { return }
        isLoading = true; errorMessage = nil
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
    var onEdit: () -> Void = {}
    var onShowDetail: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text(issue.statusSymbol)
                .foregroundStyle(issue.statusColor)
                .frame(width: 16)

            Text(issue.id)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            priorityBadge(issue.priorityLabel)

            if issue.dependencyCount + issue.dependentCount > 0 {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("\(issue.dependencyCount) dependenc\(issue.dependencyCount == 1 ? "y" : "ies"), \(issue.dependentCount) dependent\(issue.dependentCount == 1 ? "" : "s")")
            }

            Text(issue.title).lineLimit(1)

            Spacer()

            if copiedID == issue.id {
                Text("Copied!").font(.caption).foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture { copyID() }
        .contextMenu {
            Button("Edit Issue") { onEdit() }
            Button("View Detail") { onShowDetail() }
            Divider()
            Button("Close Issue") { onClose() }
        }
        .help("Click to copy ID \u{00B7} Double-click to edit issue")
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

// MARK: - Issue Detail Sheet

struct IssueDetailSheet: View {
    let issue: BeadsIssue
    let workingDirectory: String

    @Environment(\.dismiss) private var dismiss
    @State private var output    = ""
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(issue.id)
                    .font(.system(.headline, design: .monospaced))
                Text("\u{2013}")
                Text(issue.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)
            Divider()
            if isLoading {
                ProgressView("Loading\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32)).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        let dir = workingDirectory
        let id  = issue.id
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.show(id: id, workingDirectory: dir)
            }.value
            output = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Issue Edit Sheet

struct IssueEditSheet: View {
    let issue: BeadsIssue
    let workingDirectory: String
    let preferredWidth: CGFloat
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fields    = IssueFormFields()
    @State private var isLoading = true
    @State private var isSaving  = false
    @State private var error: String? = nil
    @State private var comments: [BeadsComment] = []
    @State private var dependencies: [BeadsDependency] = []
    @State private var newCommentText: String = ""
    @State private var isAddingComment = false
    @State private var commentError: String? = nil
    @State private var newDepID: String = ""
    @State private var newDepType: String = "blocks"
    @State private var isAddingDep = false
    @State private var depError: String? = nil

    private var canSave: Bool {
        !fields.title.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(issue.id)
                    .font(.system(.headline, design: .monospaced))
                Text("\u{2013}")
                Text(issue.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
            }
            .padding()
            .background(.bar)
            Divider()

            if isLoading {
                ProgressView("Loading\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32)).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Dismiss") { dismiss() }.buttonStyle(.bordered)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        IssueFormContent(fields: $fields, showDependencies: false).padding()

                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dependencies").font(.subheadline).fontWeight(.medium)

                            if dependencies.isEmpty {
                                Text("No dependencies.").foregroundStyle(.secondary).font(.subheadline)
                            } else {
                                ForEach(dependencies) { dep in
                                    HStack(spacing: 6) {
                                        Text(dep.dependencyType ?? "depends-on")
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.teal, in: Capsule())
                                        Text(dep.id)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(dep.title).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        Text("P\(dep.priority)").font(.caption2).foregroundStyle(.secondary)
                                        Button { Task { await removeDep(dep) } } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove this dependency")
                                    }
                                }
                            }

                            if let err = depError {
                                Text(err).foregroundStyle(.red).font(.caption)
                            }

                            HStack(spacing: 6) {
                                TextField("Issue ID", text: $newDepID)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                Picker("", selection: $newDepType) {
                                    Text("blocks").tag("blocks")
                                    Text("tracks").tag("tracks")
                                    Text("related").tag("related")
                                    Text("parent-child").tag("parent-child")
                                    Text("discovered-from").tag("discovered-from")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 160)
                                Button(isAddingDep ? "Adding\u{2026}" : "Add") {
                                    Task { await addDep() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(newDepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingDep)
                            }
                        }
                        .padding(.horizontal).padding(.top, 8)

                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.subheadline).fontWeight(.medium)
                            formTextArea($fields.notes, placeholder: "Add notes…", height: 80)
                            Text("Notes are saved along with other fields when you click Save.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.top, 8)

                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comments").font(.subheadline).fontWeight(.medium)

                            if comments.isEmpty {
                                Text("No comments yet.").foregroundStyle(.secondary).font(.subheadline)
                            } else {
                                ForEach(comments) { comment in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(comment.author).fontWeight(.medium).font(.subheadline)
                                            Spacer()
                                            Text(comment.createdAt).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(comment.text).font(.body).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(8)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }

                            if let err = commentError {
                                Text(err).foregroundStyle(.red).font(.caption)
                            }
                            HStack(alignment: .bottom, spacing: 8) {
                                formTextArea($newCommentText, placeholder: "Add a comment…", height: 60)
                                Button(isAddingComment ? "Adding…" : "Add") {
                                    Task { await addComment() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingComment)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                    }
                }
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isSaving { ProgressView().scaleEffect(0.75).padding(.trailing, 4) }
                Button("Save") { saveIssue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(.bar)
        }
        .frame(width: max(520, preferredWidth - 80))
        .frame(minHeight: 540)
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        let dir = workingDirectory
        let id  = issue.id
        do {
            let detail = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.showDetail(id: id, workingDirectory: dir)
            }.value
            fields = IssueFormFields.from(detail)
            comments = detail.comments ?? []
            dependencies = detail.dependencies ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isAddingComment = true
        commentError = nil
        let dir = workingDirectory
        let id = issue.id
        do {
            try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.addComment(id: id, text: text, workingDirectory: dir)
            }.value
            // Reload to get updated comments list
            let detail = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.showDetail(id: id, workingDirectory: dir)
            }.value
            comments = detail.comments ?? []
            newCommentText = ""
        } catch {
            commentError = error.localizedDescription
        }
        isAddingComment = false
    }

    private func addDep() async {
        let depID = newDepID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !depID.isEmpty else { return }
        isAddingDep = true
        depError = nil
        let dir = workingDirectory
        let id = issue.id
        let dtype = newDepType
        do {
            try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.addDependency(issueID: id, depID: depID, type: dtype, workingDirectory: dir)
            }.value
            let detail = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.showDetail(id: id, workingDirectory: dir)
            }.value
            dependencies = detail.dependencies ?? []
            newDepID = ""
        } catch {
            depError = error.localizedDescription
        }
        isAddingDep = false
    }

    private func removeDep(_ dep: BeadsDependency) async {
        depError = nil
        let dir = workingDirectory
        let id = issue.id
        let depID = dep.id
        do {
            try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.removeDependency(issueID: id, depID: depID, workingDirectory: dir)
            }.value
            let detail = try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.showDetail(id: id, workingDirectory: dir)
            }.value
            dependencies = detail.dependencies ?? []
        } catch {
            depError = error.localizedDescription
        }
    }

    private func saveIssue() {
        guard canSave else { return }
        isSaving = true
        let snap = fields
        let dir  = workingDirectory
        let id   = issue.id
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try BeadsRunner.update(id: id, fields: snap, workingDirectory: dir)
                DispatchQueue.main.async {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
