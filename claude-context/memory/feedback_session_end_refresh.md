---
name: feedback-session-end-refresh
description: "At the end of any session that feels complete, do a project-knowledge refresh pass — check diffs against memory + DesignNotes.md, propose updates where warranted."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

When a session feels like it's wrapping up (feature shipped, design pass settled, or Max explicitly says "we're done here"), offer to do a project-knowledge refresh before signing off. Don't wait to be asked — surface the offer.

**The refresh checklist:**
1. **Code diffs vs. memory/DesignNotes:** Run `git status` and `git log` since the last refresh. Anything in memory or `DesignNotes.md` that the new code contradicts? Update it. Anything in the code that the docs don't yet describe? Add it.
2. **Conversation diffs:** What design decisions solidified or shifted in this session? What open questions did we surface or close? Update the relevant memories ([[project-dart-game-concept]], [[project-balance-philosophy]], [[project-component-philosophy]], [[project-architecture-rules]], [[project-open-questions]]).
3. **Active spec (`CLAUDE.md`):** If the spec it holds is shipped, propose archiving it to `specs/YYYY-MM-DD-feature-slug.md` with an accurate status header. If it's still in flight, leave alone.
4. **`DesignNotes.md`:** Only update sections that meaningfully changed. Don't rewrite the whole doc every time — light edits keep the git history readable.
5. **`claude-context/memory/` snapshot:** Sync the live memory folder into the in-repo snapshot at `claude-context/memory/` so cross-machine transfer stays current. Process: glob the live memory folder, for each file write its current content into `claude-context/memory/<filename>` (overwriting), and use bash to delete any files in `claude-context/memory/` that no longer exist in the source. Report a short summary of what changed so Max can decide whether to commit. Skip this step if no memory changed during the session — only run it after step 2 actually wrote something, or if the snapshot has obviously drifted (e.g., a memory file exists in live but not in the snapshot).

**Why:** Max doesn't want to manually re-orient Claude at the start of each session by explaining what's new. The whole point of memory + DesignNotes is to absorb that load. If the refresh doesn't happen at session end, those docs drift and future-Claude gets a stale read. Step 5 specifically exists so the project context survives a machine swap — `claude-context/` is the portable backup that gets carried between Max's Mac and PC via git.

**How to apply:** Be proactive about offering this — at the end of a clearly-complete chunk of work, write a one-line offer ("want me to do an end-of-session refresh?"). If Max says yes, walk through the checklist and propose specific updates before writing them. Don't blanket-rewrite memories from scratch; surgical edits only.

**Guardrails:**
- Don't save session logs or activity summaries to memory — that violates the memory rules. Save durable design intent, decisions with reasons, and new feedback.
- Don't update memory just because something was discussed — only when something was *decided* or *learned*.
- If a memory entry turns out to be wrong, fix it. Don't leave contradictory entries.

See also: [[user-role]], [[reference-design-notes]]
