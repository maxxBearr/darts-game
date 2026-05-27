---
name: feedback-godot-conventions
description: "Max's GDScript coding conventions — static typing everywhere, frequent comments, exported vars with descriptive hover text."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c03aae22-d38d-4870-9334-45c4eabb7151
---

When writing or editing GDScript for Max's projects, follow these conventions:

1. **Statically type ALL variables.** No untyped `var foo = ...` — always `var foo: Type = ...`. This is for legibility, not just safety.
2. **Comment frequently.** Code should read well even to someone unfamiliar with it. Don't be sparing.
3. **Exported variables get descriptions.** When using `@export`, add the `## description` doc-comment above it so it shows up on hover in the Godot inspector. Describe where the var comes into effect and what different values would mean.
4. **Prefer exported vars whenever applicable.** After a code pass, the developer should have inspector-level control over tunable parameters wherever it makes sense — magic numbers should usually become `@export` vars.

**Why:** Max cares strongly about code legibility for himself and future-him, and likes to tune via the inspector rather than re-editing scripts.

**How to apply:** Apply to every GDScript file I touch in this project, including new code and edits to existing code. If I'm tempted to use a magic number or skip a type annotation, don't.

See also: [[user-role]]
