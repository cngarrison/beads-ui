# Contributing to Beads Tracker

Thank you for your interest in contributing! This project started as a 30-minute experiment in AI-assisted development — and contributions made the same way are absolutely welcome. You don’t need to know Swift.

---

## The spirit of this project

Beads Tracker is intentionally a **single-file SwiftUI app**. The entire application lives in `BeadsTracker.swift`. This constraint is a feature: it keeps the codebase approachable for people who aren’t professional Swift developers, and it keeps the build system trivially simple (`make`).

Please maintain this constraint when contributing. If a feature genuinely can’t fit cleanly in one file, open an issue to discuss before splitting.

---

## Ways to contribute

### Without writing any code
- **File a bug** — run `bd create` in this repo and describe what’s wrong
- **Suggest a feature** — check [ROADMAP.md](ROADMAP.md) first, then `bd create` if it’s new
- **Improve the docs** — README, ROADMAP, and this file are all fair game
- **Test on your hardware** — especially Intel Macs and different macOS versions

### With code
- Pick an item from [ROADMAP.md](ROADMAP.md)
- Claim it with `bd update <id> --claim` if you’re working from this repo
- Write the Swift, rebuild with `make`, test manually, send a PR

---

## You don’t need to know Swift

This project was built by someone with no Swift experience, using [Beyond Better](https://BeyondBetter.app) and Claude Sonnet. If you want to add a feature:

1. Open Beyond Better (or any Claude interface) with this repo as context
2. Describe the feature you want to add, referencing the relevant `bd` CLI commands from `bd --help`
3. Iterate on any compile errors (there are usually very few)
4. Test with `make run`
5. Send a PR

The [ROADMAP.md](ROADMAP.md) items are written to give enough context for an AI assistant to implement them with minimal additional explanation.

---

## Issue Tracker Sync

Beads Tracker uses [beads](https://github.com/cngarrison/beads) (`bd`) for issue tracking. Issues are stored in the Git repo under `refs/dolt/data` alongside the source code — no separate account or service needed.

**First-time setup** (after cloning):
```bash
bd bootstrap   # pulls the issue database from the remote
bd list        # verify issues are visible
```

**Day-to-day:**
```bash
bd dolt pull   # pull latest issues before starting work
bd dolt push   # push your changes after creating/closing issues
```

---

## Development setup

```bash
# Clone the repo
git clone https://github.com/cngarrison/beads-tracker.git
cd beads-tracker

# One-time setup: git hooks + issue tracker bootstrap
make setup

# Build
make

# Run
make run

# Build the app icon (requires: brew install librsvg)
make icon && make
```

`make setup` configures the `.githooks` directory (which includes hooks that auto-sync `bd dolt push/pull`) and runs `bd bootstrap` to pull the issue database from the repo.

No Xcode required. No Swift Package Manager. No dependencies beyond the Xcode Command Line Tools.

```bash
xcode-select --install   # if you don’t have them already
```

---

## Project layout

```
BeadsTracker.swift  ── Entire application (keep it one file)
Info.plist          ── App bundle metadata (rarely needs changing)
Makefile            ── Build system + icon pipeline
BeadsTracker.svg    ── App icon source (edit to change the icon)
README.md           ── User-facing docs
ROADMAP.md          ── Feature ideas and backlog
CONTRIBUTING.md     ── This file
```

---

## Code conventions

There aren’t many rules, but please follow these:

**Structure** — keep the existing section order in `BeadsTracker.swift`:
1. App entry point (`@main`)
2. Domain enums & models
3. `BeadsRunner` (all `bd` CLI interaction)
4. `ContentView` (tab container)
5. `CreateIssueView`
6. `IssueListView`
7. Supporting views (`IssueRow`, etc.)

**`BeadsRunner`** — all subprocess calls to `bd` must go through the `run(_:in:)` helper. Don’t spawn `Process` directly in views.

**Main thread** — `@State` mutations must happen on the main actor. Use `Task.detached` for background work and `DispatchQueue.main.async` (or `await` on the main actor) to update state.

**No third-party dependencies** — only Swift standard library, SwiftUI, and AppKit.

**macOS 13.0 minimum** — check API availability before using newer APIs. Known pitfall: `.monospaced()` on `Text` requires 13.3+; use `.font(.system(.body, design: .monospaced))` instead.

**Activation policy** — because the app is built with `swiftc -parse-as-library` rather than through Xcode, `NSApplication` can default to a non-regular activation policy (no Dock icon, no ⌘-Tab entry). The `App.init()` explicitly calls `NSApplication.shared.setActivationPolicy(.regular)` to fix this. Don’t remove it.

**Raw string Unicode escapes** — Swift raw string literals (`#"..."#`) do **not** process `\u{XXXX}` escape sequences. Use regular string literals when you need Unicode characters in regex patterns or string comparisons.

---

## Submitting a PR

1. Fork the repo and create a branch: `git checkout -b my-feature`
2. Make your changes to `BeadsTracker.swift` (and other files if needed)
3. Confirm `make` succeeds with no errors
4. Test the feature manually with a real beads repository
5. Update `ROADMAP.md` to mark the item as done (or remove it)
6. Open a pull request with a brief description of what you changed and why

---

## Reporting bugs

Please include:
- macOS version (`sw_vers`)
- CPU architecture (`uname -m`)
- Output of `bd --version`
- Steps to reproduce
- What you expected vs. what happened
- Any error output from the terminal (run `make run` from the terminal to capture stderr)

---

## Questions?

Open an issue or start a discussion. This is a small, friendly project.
