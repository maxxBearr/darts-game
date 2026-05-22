# Active Spec: Shop System

**Spec date:** 2026-05-21
**Status:** Designed, ready for implementation
**Scope:** New post-leg system. Every three legs, the player enters a "shop" that uses the dart board itself as the shop interface — they throw their accumulated spare darts at lit-up spots on the board to earn upgrades. Builds on the [HUD / Assembly Polish Pass](specs/2026-05-21-hud-assembly-polish.md): the parity slot system and the shared checkout-detection function are assumed to be in place.

## Summary

Replace the leg-end pick screen on every third leg with a "shop round." The player throws a number of darts equal to the spare darts they saved across the preceding three legs. Spots on the board light up with rarity indicators (common, uncommon, rare). Hitting a lit spot reveals two random upgrades of that rarity, of which the player picks one. Hit nothing, get nothing.

Five parts to the spec:

1. Cadence — when shops happen, how they interact with the existing per-leg upgrade pick.
2. Spare-dart math — how many darts the player gets at the shop.
3. Board setup — how many spots light up, what rarities, where they sit.
4. Throw resolution — what happens on hit, miss, and total whiff.
5. Visuals — the "swirly shader" treatment for lit spots and the zero-dart fallback.

---

## 1. Cadence and Flow

Shops fire after every third leg. The run flow becomes:

Leg 1 → 2 upgrade picks → Leg 2 → 2 upgrade picks → Leg 3 → **Shop** → Leg 4 → 2 upgrade picks → Leg 5 → 2 upgrade picks → Leg 6 → **Shop** → ...

The shop replaces the post-leg pick screen on shop legs (3, 6, 9, ...) entirely. On non-shop legs, the existing 2-upgrade pick continues unchanged.

The shop is not itself a leg. It does not consume a leg slot, advance run scaling, or accrue any leg-side state. It is a screen that runs between the end of one leg and the start of the next.

**Why per-leg picks continue:** the game is currently hard. The shop is additive — a richer reward on milestone legs — not a replacement for the steady drip of upgrades that keeps non-shop legs feeling worthwhile. Not the moment to scale player power down.

---

## 2. Spare-Dart Math

Each leg has a finite dart budget. Saving darts means finishing the leg before exhausting that budget.

**Formula:**
- At leg start: `total_darts_in_leg = max_turns * darts_per_turn` (currently 5 × 3 = 15).
- Each throw during the leg: `used_darts += 1`.
- On a bust: the remaining darts in the busted turn count toward `used_darts` (busting on dart 1 of a turn burns the full 3-dart turn).
- On a leg win: `saved_darts_this_leg = total_darts_in_leg - used_darts`.

**Across the shop window:** `shop_darts = saved_darts from leg N-2 + saved_darts from leg N-1 + saved_darts from leg N`, where leg N is the leg that just ended.

The formula is intentionally written in terms of `max_turns` and `darts_per_turn` because future modifiers may alter either value. The math stays correct regardless.

The accumulator resets to 0 once the shop concludes — the next window begins from the next leg.

---

## 3. Board Setup

When the shop opens, a number of board spots light up with rarity indicators. The player will throw `shop_darts` darts at this board.

### 3a. Lit-spot count

`lit_spots = shop_darts + 3`

The flat +3 slack gives the player consistent breathing room — always a few more targets than darts, so the player gets meaningful choice in *which* targets to prioritize. This holds across the range: 3 darts → 6 spots, 9 darts → 12 spots, 15 darts → 18 spots.

### 3b. Rarity distribution

Within the lit spots:

- `rares = max(1, floor(lit_spots / 6))` — at least one rare guaranteed.
- `uncommons = floor(lit_spots / 3)`.
- `commons = lit_spots - rares - uncommons`.

The "at least one rare" floor means a shop is never just commons. There is always a high-stakes target on the board.

### 3c. Placement rules

Rarity governs which board regions a spot can land on:

- **Commons** fill the larger single regions of wedges.
- **Uncommons and rares** fill the smaller double and triple rings.

Within those constraints, placement is random. Which specific wedge a common occupies, and which specific double/triple a rare occupies, is rolled per shop.

**Emergent strategy:** because doubles and triples are physically adjacent to their corresponding singles, missing a hard rare often clips into the related single. If that single happens to be lit as a common, the player has an organic near-miss reward — the geometry creates the safety net, not a separate consolation mechanic. The player who reads the lit-spot clusters before throwing will outperform the one who yolos at rares. This is one of the three interacting systems the game wants the player calculating every throw (board RNG read + skill/confidence + stat-driven hit probability).

---

## 4. Throw Resolution

### 4a. Hitting a lit spot

When a dart lands on a lit spot:

1. The spot's rarity tier determines which pool the items roll from (common / uncommon / rare).
2. Two items of that rarity are rolled and shown to the player.
3. The player picks one. The picked item is added to the loadout. The other is discarded.
4. Any existing slot-conflict rules apply (see 4d).
5. The spot deactivates — no longer lit — for the rest of the shop.

The 2-of-2 pick is narrower than the regular leg-end 2-of-3 pick. Intentional: the throw itself is already a meaningful choice (which spot to target), so the post-hit menu stays small.

The shop draws from the same item pool the per-leg picks use, weighted by the rarity tier of the hit spot. Stat upgrades and modifiers can both appear in the shop — they are not segregated by source.

### 4b. Hitting an unlit area

The dart lands normally on the board (or misses the board entirely), no reward triggers, the dart is spent. The next dart is thrown.

### 4c. Whiffing the entire shop

If the player throws every dart without landing on a single lit spot: hit nothing, get nothing. No consolation upgrade, no reroll. The shop ends with no rewards.

Intentional. The spare-dart system already rewards play quality; softening misses dilutes that signal.

### 4d. Streak slot interactions

The shop does not score throws — no scoring modifiers apply, no streak counters update. Streak items still respect their slot conflict rules at the pick step: if a player picks a streak item from the 2-of-2 menu and they already have an item in that streak slot equipped (color, wedge, or parity), the existing replace warning fires. Same logic and UI as the leg-end pick. No duplicates.

---

## 5. Visuals

### 5a. Lit-spot treatment

Lit spots are rendered with a swirly, animated shader-style fill. Visual reference: the Balatro main menu background, or the moving curved pattern of a stylized zebra. The shader animates continuously so the lit spots read as alive.

Rarity is encoded by color:

- **Common:** white / light grey.
- **Uncommon:** blue.
- **Rare:** purple.

The shader pattern is the same across rarities; only the color palette differs. This keeps the shop visually coherent and lets the player parse rarity at a glance from across the board.

### 5b. Zero-dart shop ("oh dear")

If the player saved zero darts across the three preceding legs (`shop_darts == 0`), the shop screen still appears. The board has no lit spots. A brief humorous acknowledgment plays — something tonal along the lines of *"oh dear, you didn't save ANY darts... oh well"* — then the shop closes and the next leg begins.

The point is to make the consequence of poor play visible rather than silently skipping the shop. Brief, in-character, no extra dialogue.

---

## Deferred / Out of Scope

- **Reroll mechanics** for either lit-spot generation or the post-hit 2-of-2 options. Could land later as a stat upgrade or a shop-specific modifier.
- **Shop variants** (themed shops, boss shops, alternate layouts). One shop type for now.
- **Item-specific shop interactions** (e.g., a modifier that biases shop rolls or alters lit-spot placement). Future hook.
- **Run-end interaction.** If a shop would fire after the final leg of a run, behavior is undefined for now. Resolve in implementation, or wait until run structure firms up (this depends on the unresolved meta-progression / run-length question).
- **Static on-board modifier visuals.** Still deferred from the HUD pass — art-direction-dependent.

---

## Implementation Notes

- All tunable values — the `lit_spots` slack constant (currently +3), the rarity floor formulas, shader animation speed, the zero-dart acknowledgment duration — exposed as exported variables with hover descriptions per project conventions.
- Static typing throughout per project conventions.
- Reuse the streak conflict logic established by the HUD pass for the parity slot. The shop pick step calls the same conflict-check function the leg-end pick uses. Do not duplicate.
- The shop's item pool must be the same data source the per-leg picks use. Rarity weighting is determined by the spot's rarity tier, not a separate shop-specific pool.
- `shop_darts` accounting must persist across legs within the run. Counter resets to 0 immediately after a shop concludes (success, whiff, or zero-dart all reset).
- A shop is its own screen / state, not a modal on top of a leg. Clean transition between leg-end and leg-start.

---

## Workflow Notes

`CLAUDE.md` holds the **single active spec** — the feature currently being designed or implemented. It auto-loads into every Claude conversation in this repo, so it should stay lean and focused on one thing at a time.

When a feature ships (or work moves on to a new spec), the previous one gets archived:

1. Move everything above this "Workflow Notes" section into `specs/YYYY-MM-DD-feature-slug.md`.
2. Add a status header at the top of the archived file:
   ```
   ---
   Spec date: YYYY-MM-DD
   Status: Shipped YYYY-MM-DD | Partially shipped | Superseded by specs/X
   Implementation: Where the implementation pass ran (Claude Code, manual, etc.)
   Notes: What shipped vs deferred, links to follow-up specs that revisit anything here.
   ---
   ```
3. Reset the spec section in `CLAUDE.md` to this placeholder (or replace it with the next spec).

The archive is for design context, not implementation reference. Code lives in code; the archived spec exists to remind future-Max (and future-Claude) *why* a system was built a certain way, what alternatives were considered, and what the design assumptions were. When making changes that touch an existing system, scan `specs/` for any prior decision that constrains the new work.
