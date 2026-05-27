---
name: project-audio-system
description: "Audio system shipped 2026-05-26 — autoloaded AudioManager with BaseButton auto-connect for UI clicks, music transitions via volume + pitch fade, progressive turn-end pitch tension, leg-win/lost pitch response. Filename typo 'auido' flagged for rename."
metadata: 
  node_type: memory
  type: project
  originSessionId: 08056db4-575e-4779-b21c-72c057113b67
---

**Shipped 2026-05-26.** Autoloaded singleton `AudioManager` — but note: source files are `auido_manager.gd` and `AuidoManager.tscn` (typo). **Filename rename is a follow-up** — preserve the typo when referencing the file path until renamed.

**Key design choices** (the *why*, not the implementation specifics — the script is small enough to read directly):

- **Music transitions fade volume AND pitch together.** Menu-to-game tweens pitch from 0.85 to 1.0 alongside the volume fade; the reverse drops the game music's pitch by 0.15 as it fades out. Pitch-shift on a fade creates an atmospheric sense of mood change that pure volume crossfading doesn't.
- **Progressive turn-end pitch tension.** `on_turn_ended(turn_number)` lowers `game_music.pitch_scale` by a turn-dependent delta: −0.035 for turns 1-2, −0.048 turn 3, −0.11 turn 4+. The *accelerating* drop maps to the actual stakes — turn 5 is the leg-decider, and the music should feel that way. Cheaper than music-swap (a single continuous pitch variable across the leg) and creates flow continuity.
- **Leg outcome resets pitch.** `on_leg_won()` snaps back to 1.0 (relief). `on_leg_lost()` drops by another −0.5 (dread). The pitch state being one continuous variable across the leg is what makes the win/lose moment land — without the gradual tension build, the resolution wouldn't feel earned.
- **BaseButton auto-connect.** `_on_node_added` listens for any `BaseButton` entering the tree and wires `.pressed → play_ui_click`. UI click sounds are universal without per-screen wiring. Trade-off: every button gets the click whether it should or not — currently fine, but if a screen ever needs a different click sound it'd need explicit handling on that specific button.
- **Bonus pitch ladder.** `play_bonus_hit(trigger_index)` plays the bonus chime at `0.9 + 0.15 * trigger_index` pitch — sequential bonus triggers in one throw ladder up audibly. Communicates compounding scoring events.
- **Dart-thunk variation.** Two thunk variants at randomized start positions (0.34s / 2.3s into the file) with pitch jitter in [0.88, 1.2]. Variation is what makes repeated throws not annoying.

**Hooks expected by other code:**
- `play_dart_thunk()` — dart-landing event.
- `play_void_hit()` — dart hits a Void boss wedge (zero-scoring).
- `play_leg_win()` / `play_ui_click()` / `play_bonus_hit(trigger_index)` — event sounds.
- `on_turn_ended(turn_number)`, `on_leg_won()`, `on_leg_lost()` — game-state pitch transitions.
- `transition_to_game_music()` / `transition_to_menu_music()` — scene-flow music swaps.

**How to apply.**

- When adding a new audio event, extend `AudioManager` rather than wiring sounds inline. Keep music + sfx orchestration centralized.
- When adding sound that should ride a game-state transition, follow the `on_turn_ended` / `on_leg_won` / `on_leg_lost` handler pattern — game logic calls the handler, the handler tweens pitch / volume. Don't have game code touch pitch directly.
- If a new music context is needed (e.g., boss-leg music), the music transition pattern (volume + pitch fade together via `set_parallel(true)` tween) is the model.
- Filename typo: **rename `auido_manager.gd` → `audio_manager.gd` and `AuidoManager.tscn` → `AudioManager.tscn`** when convenient. Touches: project.godot autoload entry, the file paths themselves, any preload() or @onready references in main.gd. Not urgent — the typo is contained.

See also: [[project-boss-level-system]]
