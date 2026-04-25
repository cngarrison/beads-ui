// IssueListView.swift
// IssueListView, IssueRow, IssueDetailSheet, IssueEditSheet.

import SwiftUI
import AppKit

// MARK: - Issue List View

struct IssueListView: View {
    let workingDirectory: String
    var refreshTrigger: Int = 0

    @State private var issues:       [BeadsIssue] = []
    @State private var isLoading     = false
    @State private var loadingCount  = 0
    @State private var errorMessage: String? = nil
    @State private var copiedID:     String? = nil
    @State private var detailIssue:  BeadsIssue? = nil
    @State private var editIssue:    BeadsIssue? = nil

    var body: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider()
            listContent
        }
        .task { await loadIssues() }
        .onChange(of: workingDirectory) { newDir in Task { await loadIssues(dir: newDir) } }
        .onChange(of: refreshTrigger) { _ in Task { await loadIssues() } }
        .sheet(item: $detailIssue) { issue in
            IssueDetailSheet(issue: issue, workingDirectory: workingDirectory)
        }
        .sheet(item: $editIssue) { issue in
            let w = NSApp.mainWindow?.frame.size.width ?? NSApp.keyWindow?.frame.size.width ?? 920
            IssueEditSheet(
                issue: issue,
                workingDirectory: workingDirectory,
                preferredWidth: w,
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
                Text(loadingCount > 0 ? "Loading issues\u{2026} (\(loadingCount) found)" : "Loading issues\u{2026}")
                    .foregroundStyle(.secondary).font(.subheadline)
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
                         onClaim: { Task { await claimIssue(issue) } },
                         onClose: { Task { await closeIssue(issue) } })
            }
            .listStyle(.plain)
            .background(

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

    private func claimIssue(_ issue: BeadsIssue) async {
        let dir = workingDirectory
        do {
            try await Task.detached(priority: .userInitiated) {
                try BeadsRunner.claim(id: issue.id, workingDirectory: dir)
            }.value
            await loadIssues()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        isLoading = true; loadingCount = 0; errorMessage = nil
        let (progressStream, bgTask) = BeadsRunner.listWithProgress(workingDirectory: dir)
        for await count in progressStream { loadingCount = count }
        do {
            issues = try await bgTask.value
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
    var onClaim: () -> Void = {}
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
            Button("Edit\u{2026}") { onEdit() }
            Button("View Detail") { onShowDetail() }
            Divider()
            Button("Copy ID") { copyID() }
            Button("Copy Title") { copyTitle() }
            Divider()
            Menu("Status") {
                Button("Claim") { onClaim() }
                Divider()
                Button("Close") { onClose() }
            }
        }
        .help("Click to copy ID \u{00B7} Double-click to edit")
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

    private func copyTitle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.title, forType: .string)
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
    @State private var fields         = IssueFormFields()
    @State private var originalFields = IssueFormFields()   // snapshot at load time
    @State private var isLoading = true
    @State private var isSaving  = false
    @State private var error: String? = nil
    @State private var comments: [BeadsComment] = []
    @State private var dependencies: [BeadsDependency] = []
    @State private var dependents:   [BeadsDependency] = []
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
                            // Children subsection (parent-child dependents, read-only)
                            let children = dependents.filter { $0.dependencyType == "parent-child" }
                            if !children.isEmpty {
                                Text("Children").font(.subheadline).fontWeight(.medium)
                                ForEach(children) { child in
                                    HStack(spacing: 6) {
                                        Text(child.status == "closed" ? "\u{2713}" : child.status == "in_progress" ? "\u{25D0}" : "\u{25CB}")
                                            .font(.caption)
                                            .foregroundStyle(child.status == "closed" ? Color.green : child.status == "in_progress" ? Color.blue : Color.primary)
                                        Text(child.id)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(child.title).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        Text("P\(child.priority)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Divider().padding(.vertical, 4)
                            }

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
                            formTextArea($fields.notes, placeholder: "Add notes\u{2026}", height: 80)
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
                                formTextArea($newCommentText, placeholder: "Add a comment\u{2026}", height: 60)
                                Button(isAddingComment ? "Adding\u{2026}" : "Add") {
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
        .frame(minHeight: 540, maxHeight: .infinity)
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
            originalFields = fields
            comments = detail.comments ?? []
            dependencies = detail.dependencies ?? []
            dependents   = detail.dependents   ?? []
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
            dependents   = detail.dependents   ?? []
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
            dependents   = detail.dependents   ?? []
        } catch {
            depError = error.localizedDescription
        }
    }

    private func saveIssue() {
        guard canSave else { return }
        isSaving = true
        let snap     = fields
        let origSnap = originalFields
        let dir      = workingDirectory
        let id       = issue.id
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try BeadsRunner.update(id: id, fields: snap, original: origSnap, workingDirectory: dir)
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
