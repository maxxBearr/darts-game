extends SceneTree
## Headless tests for the typed shop (Phase 03 typed-shop slice, §7) — the parts that are
## headless-reachable: the pure ShopSpotGenerator (ring mapping, rarity-subset ratio, family
## spread, spot shape) and the EventFamilyIcons wiring (5 icons live, streak key, enum→key map).
## The pick-generation + rendering live on main.gd / dartboard.gd (autoload-bound, not loadable
## under --script) — pick family-purity at rarity is already guarded by test_challenge_nodes'
## all-three-rarities regression; node/spot rendering + §4a live tracking are boot/eyeball checks.
## Run:  godot --headless --script res://tests/test_typed_shop.gd  — exits non-zero on any failure.

const SEEDS := 300
const RARITY_FAMILIES: Array[StringName] = [&"scoring", &"streak", &"accuracy"]
const TRADE_FAMILIES: Array[StringName] = [&"geometry", &"brush"]
const ALL_FAMILIES: Array[StringName] = [&"scoring", &"streak", &"accuracy", &"geometry", &"brush"]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_spot_shape_and_ring_mapping()
	_test_rarity_subset_ratio()
	_test_family_spread()
	_test_icons_wired()
	_test_brush_rulings()
	_test_brush_main_source()
	_test_accuracy_suppressed()
	print("\nTypedShop test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _uniform_weights() -> Dictionary:
	return {&"scoring": 1.0, &"streak": 1.0, &"accuracy": 1.0, &"geometry": 1.0, &"brush": 1.0}


## §7 ring mapping + spot shape: every rarity-family spot's ring teaches its tier (rare→Triple,
## uncommon→Double, common→a single); every trade-family spot is COMMON; trade spots are observed
## on ALL FOUR rings across seeds; every spot is well-formed.
func _test_spot_shape_and_ring_mapping() -> void:
	print("— ShopSpotGenerator: spot shape + ring-teaches-tier mapping")
	var trade_rings_seen: Dictionary = {}
	for s: int in range(SEEDS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s
		var spots: Array[Dictionary] = ShopSpotGenerator.generate(10, _uniform_weights(), rng)
		for spot: Dictionary in spots:
			var fam: StringName = spot["family"]
			var ring: String = spot["ring_name"]
			var rarity: int = spot["rarity"]
			# Shape.
			_check(fam in ALL_FAMILIES, "spot family %s is one of the five" % fam, s)
			_check(ring in ShopSpotGenerator.ALL_RINGS, "spot ring %s is a real ring" % ring, s)
			_check(spot["wedge_index"] >= 0 and spot["wedge_index"] <= 19, "spot wedge in [0,19]", s)
			_check(bool(spot["active"]), "spot starts active", s)
			if fam in TRADE_FAMILIES:
				_check(rarity == ScoringEnums.Rarity.COMMON, "trade-family spot is rarity-less (COMMON)", s)
				trade_rings_seen[ring] = true
			else:
				# Rarity family: the ring must teach the tier.
				match rarity:
					ScoringEnums.Rarity.RARE:
						_check(ring == "Triple", "rare rarity-spot on a Triple (got %s)" % ring, s)
					ScoringEnums.Rarity.UNCOMMON:
						_check(ring == "Double", "uncommon rarity-spot on a Double (got %s)" % ring, s)
					_:
						_check(ring in ShopSpotGenerator.SINGLE_RINGS, "common rarity-spot on a single (got %s)" % ring, s)
	# Trade spots are rarity-less, so their ring is random — all four must show up across seeds.
	for ring: String in ShopSpotGenerator.ALL_RINGS:
		_check(trade_rings_seen.has(ring), "trade spots observed on ring %s across seeds" % ring, -1)


## §7 rarity-subset ratio: rares=max(1,n/6), uncommons=n/3, rest common — over the rarity-family
## SUBSET only (n = count of scoring/streak/accuracy spots). Plus the n==0 edge: a trades-only
## weight set yields no rares/uncommons at all.
func _test_rarity_subset_ratio() -> void:
	print("— ShopSpotGenerator: rarity ratio over the rarity-family subset (incl n==0)")
	for s: int in range(SEEDS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s * 7 + 1
		var spots: Array[Dictionary] = ShopSpotGenerator.generate(12, _uniform_weights(), rng)
		var n: int = 0
		var rares: int = 0
		var uncommons: int = 0
		for spot: Dictionary in spots:
			if spot["family"] in RARITY_FAMILIES:
				n += 1
				if spot["rarity"] == ScoringEnums.Rarity.RARE:
					rares += 1
				elif spot["rarity"] == ScoringEnums.Rarity.UNCOMMON:
					uncommons += 1
		var want_rares: int = (maxi(1, n / 6) if n > 0 else 0)
		var want_uncommons: int = n / 3
		_check(rares == want_rares, "rares == max(1,n/6) for n=%d (got %d want %d)" % [n, rares, want_rares], s)
		_check(uncommons == want_uncommons, "uncommons == n/3 for n=%d (got %d want %d)" % [n, uncommons, want_uncommons], s)
	# n == 0 edge: only trade families in the weights ⇒ zero rarity spots ⇒ no rare/uncommon anywhere.
	var trades_only: Dictionary = {&"geometry": 1.0, &"brush": 1.0}
	for s: int in range(40):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s * 13 + 3
		var spots: Array[Dictionary] = ShopSpotGenerator.generate(10, trades_only, rng)
		for spot: Dictionary in spots:
			_check(spot["rarity"] == ScoringEnums.Rarity.COMMON, "n==0 edge: trades-only shop has no rare/uncommon", s)


## §7 distribution spread (the rolled-generator-spread lesson): under uniform weights all five
## families appear at ~equal observed rates, and shops are not one canonical composition.
func _test_family_spread() -> void:
	print("— ShopSpotGenerator: family spread + composition variety")
	var counts: Dictionary = {}
	var distinct_compositions: Dictionary = {}
	var total: int = 0
	for s: int in range(SEEDS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s * 31 + 5
		var spots: Array[Dictionary] = ShopSpotGenerator.generate(10, _uniform_weights(), rng)
		var fam_seq: Array[String] = []
		for spot: Dictionary in spots:
			var fam: StringName = spot["family"]
			counts[fam] = counts.get(fam, 0) + 1
			total += 1
			fam_seq.append(String(fam))
		distinct_compositions[str(fam_seq)] = true
	for fam: StringName in ALL_FAMILIES:
		var c: int = counts.get(fam, 0)
		var frac: float = float(c) / float(total)
		# Uniform 5-way ⇒ ~0.20 each; assert a generous band so it catches a pinned/missing family.
		_check(frac >= 0.12 and frac <= 0.28, "family %s ~uniform share (%.3f over %d)" % [fam, frac, total], -1)
	_check(distinct_compositions.size() > SEEDS / 2, "shops are not one canonical composition (%d distinct over %d)" % [distinct_compositions.size(), SEEDS], -1)
	print("   family shares: %s ; distinct compositions=%d/%d" % [str(counts), distinct_compositions.size(), SEEDS])


## §1 icons wired: all five family icons live, the streak key was added, and the Family-enum →
## StringName key map is correct.
func _test_icons_wired() -> void:
	print("— EventFamilyIcons: 5 icons live + streak key + enum→key map")
	var fi: EventFamilyIcons = EventFamilyIcons.new()
	for key: StringName in ALL_FAMILIES:
		_check(fi.texture_for(key) != null, "icon texture for %s is wired" % key, -1)
	# Enum → key mapping (challenge nodes carry the enum).
	_check(EventFamilyIcons.key_for_family(ScoringEnums.Family.SCORING) == &"scoring", "SCORING → &scoring", -1)
	_check(EventFamilyIcons.key_for_family(ScoringEnums.Family.STREAK) == &"streak", "STREAK → &streak", -1)
	_check(EventFamilyIcons.key_for_family(ScoringEnums.Family.GEOMETRY) == &"geometry", "GEOMETRY → &geometry", -1)
	_check(EventFamilyIcons.key_for_family(ScoringEnums.Family.BRUSH) == &"brush", "BRUSH → &brush", -1)
	_check(EventFamilyIcons.key_for_family(ScoringEnums.Family.NONE) == &"", "NONE → empty key (no icon)", -1)
	# A challenge reward (SCORING/STREAK) resolves to a real texture via the map.
	_check(fi.texture_for(EventFamilyIcons.key_for_family(ScoringEnums.Family.STREAK)) != null, "challenge STREAK reward resolves to a texture", -1)


## §4 suppress-accuracy: the Tunnel Vision relic zeroes &"accuracy" in the shop family weights
## (main._effective_shop_family_weights). With that weight at 0, NO accuracy spot ever rolls across
## a seed grid (a distribution check, not just membership), and the other four families still fill
## the shop. This is the exact dict the shop roll site feeds ShopSpotGenerator post-suppression.
func _test_accuracy_suppressed() -> void:
	print("— Suppress-accuracy: zeroed accuracy weight ⇒ no accuracy spot across seeds")
	var suppressed: Dictionary = {&"scoring": 1.0, &"streak": 1.0, &"accuracy": 0.0, &"geometry": 1.0, &"brush": 1.0}
	var seen: Dictionary = {}
	var accuracy_spots: int = 0
	for s: int in range(SEEDS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s * 17 + 7
		var spots: Array[Dictionary] = ShopSpotGenerator.generate(10, suppressed, rng)
		for spot: Dictionary in spots:
			var fam: StringName = spot["family"]
			seen[fam] = true
			if fam == &"accuracy":
				accuracy_spots += 1
	_check(accuracy_spots == 0, "no accuracy spots when suppressed (got %d over %d seeds)" % [accuracy_spots, SEEDS], -1)
	for fam: StringName in [&"scoring", &"streak", &"geometry", &"brush"]:
		_check(seen.has(fam), "non-suppressed family %s still rolls" % fam, -1)


## Brush rulings (spec §5 + the 2026-06-08 follow-ups): brush is UNGATED (rolls with no owned
## colors) and UNBIASED (owned streak colors never steer the roll); pick surfaces sweep the full
## 4-color pool with DISTINCT colors. Tests the BrushModifier primitives directly (headless-safe).
func _test_brush_rulings() -> void:
	print("— Brush rulings: ungated + unbiased + distinct-color picks")
	var brush: GDScript = preload("res://scripts/modifiers/brush_modifier.gd")
	# Full pool of 4 distinct colors.
	_check(brush.ALL_COLORS.size() == 4, "ALL_COLORS has 4 entries", -1)
	var distinct_colors: Dictionary = {}
	for c: int in brush.ALL_COLORS:
		distinct_colors[int(c)] = true
	_check(distinct_colors.size() == 4, "ALL_COLORS are 4 distinct colors", -1)
	# make(c) builds the requested color; the 4 colors carry distinct fingerprints.
	var fps: Dictionary = {}
	for c: int in brush.ALL_COLORS:
		var b: ScoringModifier = brush.make(c)
		_check(int(b.target_color) == int(c), "make(%d) sets target_color" % int(c), -1)
		fps[b.get_config_fingerprint()] = true
	_check(fps.size() == 4, "the 4 brush colors have distinct fingerprints", -1)
	# UNBIASED: even with a single owned color, generate() still rolls all 4 (no affinity steering).
	ModifierRegistry.available_brush_colors = [ScoringEnums.SegmentColor.RED] as Array[ScoringEnums.SegmentColor]
	var seen_owned: Dictionary = {}
	for _i: int in range(400):
		seen_owned[int(brush.generate(ScoringEnums.Rarity.COMMON).target_color)] = true
	_check(seen_owned.size() == 4, "generate() rolls all 4 colors despite an owned color (unbiased, got %d)" % seen_owned.size(), -1)
	# UNGATED: with NO owned colors it still rolls (never empty), all 4 appear.
	ModifierRegistry.available_brush_colors = [] as Array[ScoringEnums.SegmentColor]
	var seen_none: Dictionary = {}
	for _i: int in range(400):
		seen_none[int(brush.generate(ScoringEnums.Rarity.COMMON).target_color)] = true
	_check(seen_none.size() == 4, "generate() rolls all 4 colors with NO owned colors (ungated, got %d)" % seen_none.size(), -1)
	# The pick-surface sweep (shuffled ALL_COLORS → make → take N) yields DISTINCT colors for N ≤ 4.
	for _trial: int in range(20):
		var colors: Array = brush.ALL_COLORS.duplicate()
		colors.shuffle()
		var pcs: Dictionary = {}
		for k: int in range(3):
			pcs[int(brush.make(colors[k]).target_color)] = true
		_check(pcs.size() == 3, "a 3-pick brush sweep yields 3 distinct colors", -1)


## Source-scrape of main.gd (autoload-bound, not loadable under --script) to lock the brush rulings
## + the §4a hover wording at their actual call sites.
func _test_brush_main_source() -> void:
	print("— main.gd: brush pick wiring + shop-spot label wording")
	var src: String = _read("res://scripts/main.gd")
	_check(src != "", "main.gd readable", -1)
	var bp: String = _slice(src, "func _generate_brush_shop_picks(", "func _generate_shop_accuracy_pick(")
	_check("ALL_COLORS" in bp and ".make(" in bp, "brush shop picks sweep ALL_COLORS via make()", -1)
	_check(not ("_sync_brush_affinity" in bp), "brush shop picks are unbiased (no affinity sync)", -1)
	_check("_get_owned_fingerprints" in bp, "brush shop picks skip owned fingerprints (distinct)", -1)
	var ev: String = _slice(src, "func _enter_brush_event(", "func _generate_event_picks(")
	_check("_generate_brush_shop_picks(" in ev, "brush EVENT uses the same direct roll as the shop", -1)
	var lbl: String = _slice(src, "func _shop_spot_label(", "func _generate_shop_picks(")
	_check('"%s Trade"' in lbl, "trade spot label reads '<Family> Trade' (no tier)", -1)
	_check('"%s %s Upgrade"' in lbl, "rarity spot label reads '<Rarity> <Family> Upgrade'", -1)


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


## The substring of `src` from the first occurrence of `start` up to (excluding) `stop`.
func _slice(src: String, start: String, stop: String) -> String:
	var i: int = src.find(start)
	if i < 0:
		return ""
	var j: int = src.find(stop, i)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)


func _check(condition: bool, label: String, seed_value: int) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL [%s] (seed %d)" % [label, seed_value])
		print("   FAIL [%s] (seed %d)" % [label, seed_value])
