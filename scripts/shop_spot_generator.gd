class_name ShopSpotGenerator
extends RefCounted
## Pure, headless-testable generator for the typed shop's lit spots (Phase 03 typed-shop slice).
## Kept autoload-free (a plain RefCounted with static methods + an injected RNG) so the §7 tests can
## drive it over a seed grid — exactly why GeometrySolver / MapGraph live outside the Node layer.
##
## Each spot rolls a FAMILY (weighted-uniform over the five), then a rarity + ring:
##   - rarity families (scoring/streak/accuracy): the rares=max(1,n/6)/uncommons=n/3/rest ratio is
##     applied to the rarity-family SUBSET only (n == 0 ⇒ no rares — no forced rare without a spot to
##     carry it). The ring teaches the tier: rare→Triple, uncommon→Double, common→a single.
##   - trade families (geometry/brush): rarity-less (always COMMON), ring fully random (rarity-less
##     means the ring signals nothing; a trade on a triple just costs more aim for the same trade).
## A spot is {wedge_index:int, ring_name:String, rarity:ScoringEnums.Rarity, family:StringName,
## active:bool}.

## The three rarity-laddered families vs the two rarity-less trade families.
const RARITY_FAMILIES: Array[StringName] = [&"scoring", &"streak", &"accuracy"]
const TRADE_FAMILIES: Array[StringName] = [&"geometry", &"brush"]

const ALL_RINGS: Array[String] = ["Inner Single", "Outer Single", "Double", "Triple"]
const SINGLE_RINGS: Array[String] = ["Inner Single", "Outer Single"]


## Build `lit_count` typed lit spots. `weights` is a family StringName -> float dict (brush should be
## pre-zeroed by the caller when no colors are owned). `rng` is injected for seed reproducibility.
static func generate(lit_count: int, weights: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	# 1. Family per spot (weighted-uniform).
	var families: Array[StringName] = []
	for _i: int in range(lit_count):
		families.append(_roll_family(weights, rng))

	# 2. Rarity over the rarity-family SUBSET only (trades stay COMMON). Shuffle which rarity spots
	#    get rare/uncommon so the assignment isn't positionally biased.
	var rarity_by_spot: Dictionary = {}   ## spot index -> ScoringEnums.Rarity
	var rarity_idxs: Array[int] = []
	for i: int in range(lit_count):
		if families[i] in RARITY_FAMILIES:
			rarity_idxs.append(i)
	var n: int = rarity_idxs.size()
	if n > 0:
		var rares: int = maxi(1, n / 6)
		var uncommons: int = n / 3
		_shuffle(rarity_idxs, rng)
		for k: int in range(n):
			var r: ScoringEnums.Rarity = ScoringEnums.Rarity.COMMON
			if k < rares:
				r = ScoringEnums.Rarity.RARE
			elif k < rares + uncommons:
				r = ScoringEnums.Rarity.UNCOMMON
			rarity_by_spot[rarity_idxs[k]] = r

	# 3. Build spot dicts (family + rarity + tier-mapped/random ring), deduping wedge+ring.
	var spots: Array[Dictionary] = []
	var used: Array[String] = []
	for i: int in range(lit_count):
		var fam: StringName = families[i]
		var rarity: ScoringEnums.Rarity = rarity_by_spot.get(i, ScoringEnums.Rarity.COMMON)
		var ring: String = ring_for(fam, rarity, rng)
		spots.append(_place(fam, rarity, ring, used, rng))
	return spots


## Weighted-uniform family roll. Falls back to scoring if all weights vanish.
static func _roll_family(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var keys: Array = weights.keys()
	var total: float = 0.0
	for k: Variant in keys:
		total += maxf(float(weights[k]), 0.0)
	if total <= 0.0:
		return &"scoring"
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k: Variant in keys:
		acc += maxf(float(weights[k]), 0.0)
		if roll < acc:
			return k as StringName
	return keys[keys.size() - 1] as StringName


## The ring a spot sits on: rarity families map the tier onto the ring (rare→Triple, uncommon→
## Double, common→a random single); trade families pick any of the four rings at random.
static func ring_for(family: StringName, rarity: ScoringEnums.Rarity, rng: RandomNumberGenerator) -> String:
	if family in TRADE_FAMILIES:
		return ALL_RINGS[rng.randi_range(0, ALL_RINGS.size() - 1)]
	match rarity:
		ScoringEnums.Rarity.RARE:
			return "Triple"
		ScoringEnums.Rarity.UNCOMMON:
			return "Double"
		_:
			return SINGLE_RINGS[rng.randi_range(0, SINGLE_RINGS.size() - 1)]


## Place a spot on a unique (wedge, ring) — the ring is fixed by family/rarity, so only the wedge is
## rolled. Falls back to a (possibly duplicate) wedge if the board is crowded at that ring.
static func _place(family: StringName, rarity: ScoringEnums.Rarity, ring: String, used: Array[String], rng: RandomNumberGenerator) -> Dictionary:
	for _attempt: int in range(40):
		var wedge_idx: int = rng.randi_range(0, 19)
		var key: String = "%d_%s" % [wedge_idx, ring]
		if key not in used:
			used.append(key)
			return {"wedge_index": wedge_idx, "ring_name": ring, "rarity": rarity, "family": family, "active": true}
	return {"wedge_index": rng.randi_range(0, 19), "ring_name": ring, "rarity": rarity, "family": family, "active": true}


## Fisher–Yates over the SEEDED rng (Array.shuffle() draws from the global RNG, breaking
## reproducibility), in place.
static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
