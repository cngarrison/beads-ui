// ContentView.swift
// App entry point (@main), ContentView, top bar, project picker logic.

import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct BeadsUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Explicitly set regular activation policy so the app appears
        // in the Dock and ⌘-Tab switcher when built outside of Xcode.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Beads Issues") {
            ContentView()
        }
        .defaultSize(width: 920, height: 780)
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
