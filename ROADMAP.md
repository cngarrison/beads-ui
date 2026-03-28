# BeadsUI Roadmap

This file tracks ideas for future development. Issues are also tracked in this repo's own beads database — run `bd list` to see them.

Pull requests are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started (Swift experience not required).

---

## 🔥 High priority

### Issue detail view
Double-click a row in the Issues tab to open a sheet showing the full output of `bd show <id>`. Should display all fields: description, design notes, acceptance criteria, dependencies, history, etc.

**Relevant `bd` command:** `bd show <id>`

---

### Close / complete an issue
A **Close** button in the issue detail view (or as a swipe action on the row) that runs `bd close <id>` and removes the issue from the list.

**Relevant `bd` command:** `bd close <id>`

---

### Auto-refresh Issues tab after creating
After a successful creation, switch to the Issues tab and trigger a refresh, so the new issue appears immediately without manual intervention.

---

## 🟡 Medium priority

### Claim / start an issue
A **Claim** button in the detail view or row context menu that runs `bd update <id> --claim`, marking the issue as in-progress and assigning it to the current user.

**Relevant `bd` command:** `bd update <id> --claim`

---

### Add notes to an issue
A text field in the detail view to append notes to an existing issue without opening the terminal.

**Relevant `bd` command:** `bd update <id> --append-notes "..."`

---

### Filter & search the Issues list
A search bar above the list plus filter chips/toggles for:
- Status (open, in progress, blocked, deferred, closed)
- Priority (P0–P4)
- Type (task, bug, feature, …)
- Label

**Relevant `bd` flags:** `--status`, `--priority`, `--type`, `--label`, `--title`

---

### Custom issue types from config
Read `.beads/config.yaml` in the selected repository to discover any custom issue types configured for that project and add them dynamically to the Type picker.

**Relevant config key:** `types.custom`

---

### Multi-repo support
Replace the single working-directory picker with a list of pinned repositories. The user can add/remove repos and switch between them from a sidebar or dropdown. The last-selected repo is remembered per-launch.

---

### Open working directory in Terminal
A button in the top bar that opens the selected repository in Terminal.app (or the user’s default terminal).

---

## 🟢 Lower priority / nice to have

### Keyboard shortcuts
- `⌘ 1` / `⌘ 2` — switch between Create and Issues tabs
- `⌘ R` — refresh the Issues list
- `⎋` — dismiss banners / close sheets

---

### Configurable `bd` binary path
A Preferences panel (`⌘ ,`) where the user can set:
- Path to the `bd` binary (for non-standard installations)
- Default issue type
- Default priority
- Default assignee

---

### Menu bar extra
A lightweight menu bar icon that lets the user file a quick issue (title only, with defaults for everything else) without opening the main window.

---

### System notification on successful create
Use `UserNotifications` to post a macOS notification when an issue is created, including the issue ID and a button to copy it.

---

### Auto-refresh / polling
An option to poll `bd list` every N seconds and update the Issues tab in the background, similar to `bd list --watch`.

---

### Sort & group issues
Allow the Issues list to be sorted by priority, status, created date, or updated date, and optionally grouped by type or label.

---

### Right-click context menu on issue rows
Inline actions without opening a detail view:
- Copy ID
- Copy title
- Mark in progress
- Mark closed
- Open detail…

---

### `bd create` dry-run preview
A **Preview** button that runs `bd create --dry-run` and shows what would be created before the user commits.

**Relevant `bd` flag:** `--dry-run`

---

## 💡 Longer-term ideas

- **Create child issues** — expose `--parent <id>` when creating from the detail view of an existing issue
- **Dependency visualisation** — a simple graph view of blocking/blocked-by relationships
- **Spotlight integration** — index open issues so they appear in macOS Spotlight
- **Shortcuts app integration** — expose Create Issue as a Shortcuts action
- **GitHub sync** — display `--external-ref` links as clickable URLs in the detail view
