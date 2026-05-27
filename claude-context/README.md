# Claude Cowork Project Context

This folder is a portable snapshot of everything that makes the Dart Game Claude Cowork project *itself* — separate from the code, which already lives in the repo. The point is to be able to clone this repo on another machine (PC, second Mac, whatever) and rehydrate Claude's project state without losing the design history, conventions, or feedback patterns that have accumulated over the conversations so far.

## What's in here

```
claude-context/
├── README.md                 (this file)
├── custom-instructions.md    (project-level custom instructions — paste into the Claude desktop app on the new machine)
└── memory/                   (Claude's persistent auto-memory — 17 markdown files)
    ├── MEMORY.md             (the index; lists and summarizes every other memory file)
    ├── user_role.md
    ├── feedback_*.md         (3 feedback memories — GDScript conventions, session-end refresh, onboarding UX patterns)
    ├── project_*.md          (10 project memories — dart game concept, design philosophies, shipped systems, open questions)
    └── reference_*.md        (1 reference memory — pointer to DesignNotes.md)
```

Memory files are written in the format Claude uses internally: each has YAML frontmatter (`name`, `description`, `type`) and a markdown body. The `MEMORY.md` index is what Claude reads first to decide which deeper memory files are worth pulling into context.

## What's NOT in here (and why)

- **`CLAUDE.md`** — already in the repo root, travels with git automatically. It holds the *active* feature spec.
- **`specs/`** — already in the repo root, holds archived shipped specs. Travels with git.
- **`DesignNotes.md`**, **`DartComponentGuide.md`**, **`UnlockConditionRecipes.md`**, **`ThrowModifierGuide.txt`** — same: already in the repo, version-controlled, no extra step needed.
- **Connected MCPs / plugins** — these are configured per-machine in the Claude desktop app. There's no portable export. Re-connect them manually on the new machine.

## How to restore on a new machine (PC or otherwise)

1. **Clone the repo** as you normally would.
2. **Open the Claude desktop app** on the new machine and create a Cowork project pointing at the cloned repo folder.
3. **Paste custom instructions.** Open `claude-context/custom-instructions.md` here, copy the content below the `---`, and paste it into the project's custom instructions field in the Claude desktop app settings.
4. **Restore the memory files.** The Claude desktop app stores per-project memory at a path like:
    - **macOS:** `~/Library/Application Support/Claude/local-agent-mode-sessions/<session-uuid>/<project-uuid>/spaces/<space-uuid>/memory/`
    - **Windows:** `%APPDATA%\Claude\local-agent-mode-sessions\<session-uuid>\<project-uuid>\spaces\<space-uuid>\memory\` (path structure assumed to mirror macOS; verify on first run)
    
    The exact UUIDs will be different on the new machine. The easiest way to find the right folder: start a Cowork session in the project on the new machine, ask Claude to read its own memory directory path, then copy the contents of `claude-context/memory/` into that folder, overwriting anything that's there.
5. **Reconnect MCPs / plugins** as needed (Slack, Linear, whatever was wired up on the original machine).

## Keeping this folder in sync

The live memory at the Claude desktop app's app-data path is the source of truth; `claude-context/memory/` is a periodically-refreshed snapshot of it. The sync is *not* automatic — it has to happen at a specific moment, and the chosen moment is **session end**.

The `feedback-session-end-refresh` memory tells Claude that at the end of any session that feels complete (feature shipped, design pass settled, or you say "we're done"), it should — among other refresh tasks — sync the live memory folder into `claude-context/memory/`. Concretely Claude will:

1. List the live memory files.
2. Write each one into `claude-context/memory/` (overwriting).
3. Delete any snapshot files that no longer exist in live memory.
4. Tell you what changed so you can decide whether to `git commit`.

This means the snapshot only stays current if you actually accept the session-end-refresh offer at the end of design sessions. If you skip it, the snapshot drifts. You can also ask Claude explicitly at any point: "snapshot the memory into `claude-context/`."

**Advanced option (not recommended unless you really need live sync):** instead of snapshotting, you can replace the live memory folder at the app-data path with a symlink pointing into `claude-context/memory/`. Every memory write then goes straight to the repo. The downsides — desktop app updates may break the symlink, and the failure mode is silent — are why this isn't the default. If you want to set it up anyway, the commands are at the bottom of this file.

## Recovery notes

If the desktop app ever wipes its local state (reinstall, app data loss, OS migration), this folder is the canonical fallback. Treat it as the *backup of record* for the Cowork project itself. The repo's code can always be rebuilt; the design context here is harder to reconstruct.

## Appendix: symlink setup (advanced, optional)

If you decide you want live sync rather than snapshot-at-session-end — for example because you're switching between Mac and PC mid-design-cycle and don't want to remember to refresh — here's the setup. Treat this as advanced because the failure mode (silent desync after a Claude desktop app update) is genuinely annoying.

**macOS:**

```bash
# Quit the Claude desktop app first (Cmd+Q).

# Back up the existing live memory folder.
cp -R "/Users/<you>/Library/Application Support/Claude/local-agent-mode-sessions/<session-uuid>/<project-uuid>/spaces/<space-uuid>/memory" ~/Desktop/claude-memory-backup

# Remove the existing folder and replace it with a symlink into the repo.
rm -rf "/Users/<you>/Library/Application Support/Claude/local-agent-mode-sessions/<session-uuid>/<project-uuid>/spaces/<space-uuid>/memory"
ln -s "/path/to/darts-game/claude-context/memory" "/Users/<you>/Library/Application Support/Claude/local-agent-mode-sessions/<session-uuid>/<project-uuid>/spaces/<space-uuid>/memory"

# Reopen Claude desktop app. Verify the symlink exists.
```

To find the actual UUIDs, start a Cowork session in the project and ask Claude to list its own memory directory path.

**Windows:**

Use a directory junction (no admin required, behaves identically for this case):

```cmd
mklink /J "C:\Users\<you>\AppData\Roaming\Claude\local-agent-mode-sessions\<session-uuid>\<project-uuid>\spaces\<space-uuid>\memory" "C:\path\to\darts-game\claude-context\memory"
```

Same flow: quit Claude → back up → delete the existing folder → run `mklink` → reopen Claude.

**If the symlink breaks** (after an app update or reinstall), Claude will silently start writing to a new real folder at the app-data path and the repo will stop receiving updates. Check `ls -la` (Mac) or `dir` (Windows) on the parent directory periodically to confirm the `memory` entry is still a link/junction.
