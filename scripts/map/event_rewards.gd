class_name EventRewards
extends RefCounted
## Pure, headless-testable event-reward roller for the accuracy swing trade
## (specs/map/03-events-impl.md §3). main.gd owns UPGRADE_TYPES + _apply_upgrade + the pick
## SURFACES; this owns the rarity ramp + swing table so the ROLLED distribution can be unit
## tested directly (the rolled-generator-spread lesson — a prior generator shipped inert and
## passed a bounds-only test). All rolls take an explicit RandomNumberGenerator so a test
## can seed them; main.gd threads a run-scoped generator in.

## index 0/1/2 == Common/Uncommon/Rare (the player-facing rarity label).
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare"]

## The diagonal swing table (§3): a bigger `+` for a smaller `−`, scaling with rarity. gain
## AND penalty are inclusive roll ranges; rare's penalty barely grows (rarer = better-priced).
const SWING_TABLE: Array[Dictionary] = [
	{"gain_min": 6, "gain_max": 8, "pen_min": 2, "pen_max": 4, "color": Color(0.6, 0.6, 0.6)},
	{"gain_min": 9, "gain_max": 11, "pen_min": 3, "pen_max": 5, "color": Color(0.3, 0.5, 1.0)},
	{"gain_min": 12, "gain_max": 14, "pen_min": 4, "pen_max": 5, "color": Color(0.7, 0.3, 0.9)},
]

## Rarity weights ramp by SECTION (= bosses cleared = node.act), events only. Each later
## section adds +10 uncommon / +10 rare; common absorbs −20. Every row sums to 100.
const SECTION_RAMP: Array[Array] = [
	[85, 10, 5],    # section 0 — pre-boss-1 (act 0)
	[65, 20, 15],   # section 1 — post-boss-1 (act 1)
	[45, 30, 25],   # section 2 — post-boss-2 (act 2)
]


## Roll a rarity index (0/1/2) off the section ramp. Section is clamped to the table range.
static func roll_rarity_index(section: int, rng: RandomNumberGenerator) -> int:
	var s: int = clampi(section, 0, SECTION_RAMP.size() - 1)
	var w: Array = SECTION_RAMP[s]
	var roll: int = rng.randi_range(1, 100)
	if roll <= int(w[0]):
		return 0
	if roll <= int(w[0]) + int(w[1]):
		return 1
	return 2


## Roll a gain/penalty pair off a rarity's swing band. Returns { "gain", "penalty", "color" }.
static func roll_swing(rarity_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var band: Dictionary = SWING_TABLE[clampi(rarity_idx, 0, SWING_TABLE.size() - 1)]
	return {
		"gain": rng.randi_range(int(band["gain_min"]), int(band["gain_max"])),
		"penalty": rng.randi_range(int(band["pen_min"]), int(band["pen_max"])),
		"color": band["color"],
	}


## Build one event option from a stat-axis UPGRADE_TYPES entry (the dict shape _apply_upgrade
## consumes): roll rarity off the section ramp, then a gain/penalty off that rarity's swing.
static func build_pick(upgrade_type: Dictionary, section: int, rng: RandomNumberGenerator) -> Dictionary:
	var rarity_idx: int = roll_rarity_index(section, rng)
	var swing: Dictionary = roll_swing(rarity_idx, rng)
	return {
		"name": upgrade_type["name"],
		"property": upgrade_type["property"],
		"scale": upgrade_type["scale"],
		"description": upgrade_type["description"],
		"rarity": RARITY_NAMES[rarity_idx],
		"color": swing["color"],
		"value": int(swing["gain"]),
		"tradeoff": true,
		"penalty_property": upgrade_type.get("penalty_property", ""),
		"penalty_name": upgrade_type.get("penalty_name", ""),
		"penalty_amount": int(swing["penalty"]),
	}


## Generate `count` DISTINCT same-family options (distinct stat axes) from `upgrade_types`,
## each rolled independently off the section ramp + swing table. count is capped at the pool.
static func generate_accuracy_picks(upgrade_types: Array, section: int, rng: RandomNumberGenerator, count: int = 3) -> Array[Dictionary]:
	var order: Array[int] = _shuffled_indices(upgrade_types.size(), rng)
	var n: int = mini(count, upgrade_types.size())
	var picks: Array[Dictionary] = []
	for i: int in range(n):
		picks.append(build_pick(upgrade_types[order[i]], section, rng))
	return picks


## Fisher–Yates over [0, n) using the supplied generator (so tests stay reproducible).
static func _shuffled_indices(n: int, rng: RandomNumberGenerator) -> Array[int]:
	var a: Array[int] = []
	for i: int in range(n):
		a.append(i)
	for i: int in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
