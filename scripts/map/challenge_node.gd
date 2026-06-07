class_name ChallengeNode
extends Resource
## One challenge encounter's tunable surface (Phase 02). The map generator rolls the
## stable knobs (darts_per_turn / reward_family / handicap) at placement and writes
## them here; the *target* and *deposit band* are computed at ARRIVAL from the live
## highest_cleared and the node's depth (they depend on runtime progress) — see
## MapGraph.compute_challenge_params() and specs/map/02-challenge-nodes-impl.md §3–§7.
## These @exports let the designer clamp the rolls or hand-tune a specific node; lives
## on an off-branch (is_off_branch) map node, always post-boss-1.

## Score the player must reach. Computed at arrival in [highest_cleared - target_undercut,
## highest_cleared] (a number they have ALREADY cleared), snapped to the leg lattice
## (101/201/…) so the HUD checkout stays safe (the finer "251" lattice is deferred, §15).
## 0 until compute_challenge_params() fills it.
@export var target_score: int = 0

## How far below the player's highest cleared score the target may roll. Larger = the
## challenge anchors to a lower number, so re-clearing it on the (depth-scaled) budget
## feels leaner / more compressed. Session default 300 (§3 tuning note).
@export var target_undercut: int = 300

## Darts thrown per turn for THIS node, rolled in [dpt_min, dpt_max] at generation and
## shown BEFORE the deposit (it is difficulty-relevant: it sets the bust unit and streak
## room, §5). Low (2) = little within-turn rescue, weak streaks; high (5) = malleable but
## a bust torches a whole row. Does NOT change the total-dart budget — only regroups it.
@export var darts_per_turn: int = 3
@export var dpt_min: int = 2          ## floor of the per-node darts-per-turn roll
@export var dpt_max: int = 5          ## ceiling of the per-node darts-per-turn roll

## Wager bounds, in raw darts. Computed from ceil(target / expected_per_dart(depth)) via
## lean_factor / deposit_cushion (§4) at arrival; exposed so a node can be clamped. The
## player chooses any integer deposit in [min_deposit, max_deposit]; the deposit IS the
## race budget and a loss forfeits all of it (§2, §11). 0 until computed.
@export var min_deposit: int = 0
@export var max_deposit: int = 0

## Hard floor for min_deposit — the precision floor can never drop below this, so the
## leanest node still asks for a real (bankable) stake. §4 MIN_FLOOR.
@export var min_deposit_floor: int = 5

## Tuning knobs for the deposit derivation (used at arrival, not per-throw).
@export var lean_factor: float = 0.65   ## min_deposit ≈ reliable_darts × this (rare-end precision floor)
@export var deposit_cushion: int = 2    ## max_deposit ≈ reliable_darts + this (common-end safety net)

## Hard ceiling on the band's top end (max_deposit). Enforced UPSTREAM by clamping
## target_score down so the race budget the deposit funds stays achievable — NOT by
## squeezing the band under a too-high target (deposit = wager = race budget is the
## load-bearing rule, §5; a clamped band on a high target would offer an unwinnable race).
## Early act-0 challenges therefore become concise rematches of cheaper numbers. See
## MapGraph.compute_challenge_params. Default 12 (Max's playtest pick, 2026-06-06).
@export var max_deposit_cap: int = 12

## The upgrade family this node offers (rolled at generation). Rarity is EARNED by
## finish-efficiency (§6), not stored here. The grant draws a ScoringModifier of this
## family at the earned rarity from ModifierRegistry (the shop/modifier pool — the only
## pool that carries family + rarity). NONE = the generator picks a concrete family at
## roll time; it should not stay NONE on a placed node.
@export var reward_family: ScoringEnums.Family = ScoringEnums.Family.NONE

## Which benched-boss effect handicaps the race (§8). Empty = a clean precision race.
## One of the recycled aim handicaps: &"rotation", &"narrow_double", &"two_darts".
@export var handicap_id: StringName = &""


## Decompose a deposit into ice-tray rows of `darts_per_turn` with a (possibly partial)
## final row (§5). e.g. deposit 7, dpt 2 → [2,2,2,1]. The rows ARE the turn structure
## and the bust grain; this is what the deposit picker renders and the engine races on.
func ice_tray_rows(deposit: int) -> Array[int]:
	var rows: Array[int] = []
	var dpt: int = maxi(darts_per_turn, 1)
	var left: int = maxi(deposit, 0)
	while left > 0:
		var row: int = mini(dpt, left)
		rows.append(row)
		left -= row
	return rows


## The earned rarity for a won race, from how few darts were actually used to check out
## against this node's deposit band, split into thirds (§6): lean third ⇒ RARE, middle ⇒
## UNCOMMON, top third (still a win) ⇒ COMMON. Bands partition [min,max] with no gap.
func rarity_for_used(used: int) -> ScoringEnums.Rarity:
	var lo: int = min_deposit
	var hi: int = maxi(max_deposit, lo)
	var span: int = hi - lo
	if span <= 0:
		return ScoringEnums.Rarity.RARE
	# Two cut points at thirds; ≤ lower third ⇒ rare, ≤ two-thirds ⇒ uncommon, else common.
	var rare_cut: float = float(lo) + float(span) / 3.0
	var unc_cut: float = float(lo) + 2.0 * float(span) / 3.0
	if float(used) <= rare_cut:
		return ScoringEnums.Rarity.RARE
	if float(used) <= unc_cut:
		return ScoringEnums.Rarity.UNCOMMON
	return ScoringEnums.Rarity.COMMON
