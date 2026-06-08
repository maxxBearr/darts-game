extends SceneTree
## Headless unit test for Phase 03 event nodes (specs/map/03-events-impl.md §6). Tests the
## pure EventRewards roller directly (swing bands, the section rarity ramp's realized
## DISTRIBUTION — not just bounds — and 3-distinct-options), then source-scans main.gd for
## the flow guarantees that can't run headless (per-leg pick removed; events never touch the
## bank; brush availability fallback). Run with:
##   godot --headless --script res://tests/test_events.gd
## Exits non-zero on any failure.

# Mirror of main.gd's UPGRADE_TYPES (the 6 throw-stat trades) — the accuracy family pool.
# Kept local so the roller can be tested without instantiating main.gd (which pulls autoloads).
const UPGRADE_TYPES: Array[Dictionary] = [
	{"name": "Horizontal Range", "property": "horizontal_range", "scale": "direct", "penalty_property": "vertical_range", "penalty_name": "Vertical Range", "description": ""},
	{"name": "Vertical Range", "property": "vertical_range", "scale": "direct", "penalty_property": "horizontal_range", "penalty_name": "Horizontal Range", "description": ""},
	{"name": "V Speed Control", "property": "vertical_speed", "scale": "speed", "penalty_property": "horizontal_speed", "penalty_name": "H Speed Control", "description": ""},
	{"name": "H Speed Control", "property": "horizontal_speed", "scale": "speed", "penalty_property": "vertical_speed", "penalty_name": "V Speed Control", "description": ""},
	{"name": "Vertical Accuracy", "property": "vertical_accuracy", "scale": "direct", "penalty_property": "horizontal_accuracy", "penalty_name": "Horizontal Accuracy", "description": ""},
	{"name": "Horizontal Accuracy", "property": "horizontal_accuracy", "scale": "direct", "penalty_property": "vertical_accuracy", "penalty_name": "Vertical Accuracy", "description": ""},
]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_swing_bands()
	_test_diagonal()
	_test_section_ramp_distribution()
	_test_three_distinct_options()
	_test_main_flow_guards()
	print("\nEvents test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ── §3 swing table bands ──────────────────────────────────────────────────────

func _test_swing_bands() -> void:
	print("— Swing table bands (§3)")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	for rarity_idx: int in range(3):
		var band: Dictionary = EventRewards.SWING_TABLE[rarity_idx]
		for _i: int in range(4000):
			var swing: Dictionary = EventRewards.roll_swing(rarity_idx, rng)
			_check(swing["gain"] >= int(band["gain_min"]) and swing["gain"] <= int(band["gain_max"]),
				"%s gain %d in [%d,%d]" % [EventRewards.RARITY_NAMES[rarity_idx], swing["gain"], band["gain_min"], band["gain_max"]], -1)
			_check(swing["penalty"] >= int(band["pen_min"]) and swing["penalty"] <= int(band["pen_max"]),
				"%s penalty %d in [%d,%d]" % [EventRewards.RARITY_NAMES[rarity_idx], swing["penalty"], band["pen_min"], band["pen_max"]], -1)


## The diagonal: rarer = a bigger gain for a barely-bigger penalty, so net (gain − penalty)
## is monotone non-decreasing across rarities at the min, max, AND average.
func _test_diagonal() -> void:
	print("— Diagonal swing (rare net ≥ uncommon net ≥ common net)")
	var min_nets: Array[int] = []
	var max_nets: Array[int] = []
	for rarity_idx: int in range(3):
		var b: Dictionary = EventRewards.SWING_TABLE[rarity_idx]
		min_nets.append(int(b["gain_min"]) - int(b["pen_max"]))   # leanest swing
		max_nets.append(int(b["gain_max"]) - int(b["pen_min"]))   # fattest swing
	_check(min_nets[0] <= min_nets[1] and min_nets[1] <= min_nets[2], "min net monotone %s" % str(min_nets), -1)
	_check(max_nets[0] <= max_nets[1] and max_nets[1] <= max_nets[2], "max net monotone %s" % str(max_nets), -1)


# ── §3 section rarity ramp (realized distribution, not just bounds) ────────────

func _test_section_ramp_distribution() -> void:
	print("— Section rarity ramp (85/10/5 → 65/20/15 → 45/30/25), realized distribution")
	# Each row sums to 100, and later sections strictly raise uncommon + rare.
	var prev_unc_rare: int = -1
	for s: int in range(EventRewards.SECTION_RAMP.size()):
		var w: Array = EventRewards.SECTION_RAMP[s]
		_check(int(w[0]) + int(w[1]) + int(w[2]) == 100, "section %d weights sum to 100" % s, -1)
		var unc_rare: int = int(w[1]) + int(w[2])
		_check(unc_rare > prev_unc_rare, "section %d raises uncommon+rare (%d > %d)" % [s, unc_rare, prev_unc_rare], -1)
		prev_unc_rare = unc_rare

	# Realized distribution must MATCH the weights (the rolled-generator-spread lesson — a
	# prior generator shipped inert and passed a bounds-only test). Sample heavily, compare.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	const N := 40000
	const TOL := 0.02   # 2% absolute, comfortably within sampling noise at N=40000
	for s: int in range(EventRewards.SECTION_RAMP.size()):
		var counts: Array[int] = [0, 0, 0]
		for _i: int in range(N):
			counts[EventRewards.roll_rarity_index(s, rng)] += 1
		var w: Array = EventRewards.SECTION_RAMP[s]
		var dist_str: String = ""
		for r: int in range(3):
			var realized: float = float(counts[r]) / float(N)
			var expected: float = float(int(w[r])) / 100.0
			dist_str += "%s %.3f(want %.2f)  " % [EventRewards.RARITY_NAMES[r], realized, expected]
			_check(absf(realized - expected) <= TOL, "section %d %s realized %.3f ≈ %.2f" % [s, EventRewards.RARITY_NAMES[r], realized, expected], -1)
		print("   section %d: %s" % [s, dist_str.strip_edges()])


# ── §6 three distinct same-family options ─────────────────────────────────────

func _test_three_distinct_options() -> void:
	print("— Three distinct same-family options")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for _i: int in range(2000):
		var section: int = rng.randi_range(0, 2)
		var picks: Array[Dictionary] = EventRewards.generate_accuracy_picks(UPGRADE_TYPES, section, rng)
		_check(picks.size() == 3, "event offers exactly 3 options", -1)
		var seen_props: Dictionary = {}
		for p: Dictionary in picks:
			seen_props[p["property"]] = true
			# Every option is a trade-shaped accuracy stat (one of the 6 throw axes).
			_check(p["tradeoff"] == true, "option is a tradeoff", -1)
			_check(p["penalty_property"] != "", "option carries a penalty axis", -1)
			var is_accuracy_axis: bool = false
			for ut: Dictionary in UPGRADE_TYPES:
				if ut["property"] == p["property"]:
					is_accuracy_axis = true
			_check(is_accuracy_axis, "option is from the accuracy family pool", -1)
			# The dict shape _apply_upgrade consumes (value = gain, penalty_amount = penalty).
			_check(p.has("value") and p.has("penalty_amount") and p.has("rarity"), "option has apply-ready shape", -1)
		_check(seen_props.size() == 3, "the 3 options are distinct stat axes", -1)


# ── §6 main.gd flow guards (source-scanned — can't run main.gd headless) ──────

func _test_main_flow_guards() -> void:
	print("— main.gd flow guards (per-leg pick removed; no bank touch; brush fallback)")
	var src: String = _read("res://scripts/main.gd")
	_check(src != "", "main.gd readable", -1)

	# 1) Per-leg pick removed (§5b): _show_accuracy_pick is no longer CALLED anywhere (only
	#    its definition remains). A call site is the bare name + "()" on a non-func line.
	var call_sites: int = 0
	for line: String in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("func "):
			continue
		if "_show_accuracy_pick()" in stripped:
			call_sites += 1
	_check(call_sites == 0, "_show_accuracy_pick() has no call sites (per-leg pick removed), found %d" % call_sites, -1)

	# 2) Events never mutate the bank (§4). Scan the event-function block for an assignment to
	#    _banked_darts (=, +=, -=). Reads (passing it to the shop-pick UI) are fine.
	var block: String = _slice(src, "func _enter_event(", "func _start_next_dart_timer(")
	_check(block != "", "event function block located", -1)
	var bank_mutation: bool = false
	for line: String in block.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("_banked_darts =") or s.begins_with("_banked_darts +=") or s.begins_with("_banked_darts -="):
			bank_mutation = true
	_check(not bank_mutation, "event block never mutates _banked_darts (§4 no bank touch)", -1)

	# 3) Brush ungate + unbias (Max 2026-06-07/08): brush is ALWAYS offerable — the old arrival
	#    downgrade (no colors ⇒ accuracy) was removed, and the 2026-06-08 ruling made the roll fully
	#    UNBIASED: generate() rolls the full ALL_COLORS pool unconditionally (no available-colors
	#    gate / steering). A colorless brush event still yields valid picks. The accuracy surface is
	#    still routed for the accuracy family. (Behavioural coverage: test_typed_shop._test_brush_rulings.)
	_check("_enter_accuracy_event(section)" in block, "accuracy family routes to the accuracy surface", -1)
	var brush_src: String = _read("res://scripts/modifiers/brush_modifier.gd")
	_check("ALL_COLORS" in brush_src and not ("available_brush_colors" in brush_src),
		"BrushModifier rolls the full ALL_COLORS pool, ungated/unbiased (no available-colors gate)", -1)

	# 4) EVENT is routed to _enter_event (not the leg stub).
	_check("MapNode.Type.EVENT:" in src and "_enter_event(node)" in src, "EVENT node routes to _enter_event", -1)


# ── helpers ───────────────────────────────────────────────────────────────────

func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


## Return the substring from the first occurrence of `start` up to (excluding) the next
## occurrence of `stop`. Empty string if `start` isn't found.
func _slice(src: String, start: String, stop: String) -> String:
	var i: int = src.find(start)
	if i == -1:
		return ""
	var j: int = src.find(stop, i + start.length())
	if j == -1:
		j = src.length()
	return src.substr(i, j - i)


func _check(condition: bool, label: String, seed_value: int) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL [%s] (seed %d)" % [label, seed_value])
		print("   FAIL [%s] (seed %d)" % [label, seed_value])
