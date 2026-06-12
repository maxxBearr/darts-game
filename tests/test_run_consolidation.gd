extends SceneTree
## Headless tests for the run-consolidation spec (2026-06-12): the act-ceiling tier ladder and the
## persistent benchmarks (best run + per-tier high scores). Two pure-ish surfaces:
##   • MapGraph.act_ceilings(level) — the static tier list the home/records UI shows. For the
##     consolidated 1501/3-act run it must be exactly [501, 1001, 1501] (today's boss tiers).
##   • PlayerProgress benchmark recording — record_tier_clear / record_run_point and their getters.
##     PlayerProgress is an autoload, but the script has no autoload deps at load time, so we
##     instantiate a STANDALONE copy via load().new() (no _ready/_load fires). Its record_* methods
##     call _save(), which writes user://progress.tres — so we snapshot that file up front and
##     restore it after, leaving the real player save untouched.
## Run:  godot --headless --script res://tests/test_run_consolidation.gd  (run --import first).

const SAVE_PATH: String = "user://progress.tres"

var _failures: int = 0
var _checks: int = 0
var _saved_bytes: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _init() -> void:
	_backup_save()
	_test_act_ceilings()
	_test_tier_records()
	_test_best_run()
	_test_benchmarks_vary()
	_restore_save()
	print("\nRun-consolidation test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: %s" % label)


# ── MapGraph.act_ceilings ────────────────────────────────────────────────────

func _test_act_ceilings() -> void:
	# The consolidated run: 1501 max, 3 acts → the 501 / 1001 / 1501 ante ramp. Built inline rather
	# than loaded from level_1501.tres — that resource carries a level_cleared_condition sub-resource
	# which references the PlayerProgress autoload (absent under --script), and its compile noise is
	# irrelevant to the ceiling math (which reads only max_score_target + boss_count).
	var run_level: LevelDefinition = LevelDefinition.new()
	run_level.max_score_target = 1501
	run_level.boss_count = 3
	var ceils: Array[int] = MapGraph.act_ceilings(run_level)
	_check(ceils == [501, 1001, 1501], "act_ceilings(1501/3) == [501,1001,1501], got %s" % str(ceils))

	# Degenerate single-act level (the old 501) → one tier.
	var l501: LevelDefinition = LevelDefinition.new()
	l501.max_score_target = 501
	l501.boss_count = 1
	_check(MapGraph.act_ceilings(l501) == [501], "act_ceilings(501/1) == [501]")

	# Two acts → [501, 1001] (the old 1001 ramp).
	var l1001: LevelDefinition = LevelDefinition.new()
	l1001.max_score_target = 1001
	l1001.boss_count = 2
	_check(MapGraph.act_ceilings(l1001) == [501, 1001], "act_ceilings(1001/2) == [501,1001]")


# ── PlayerProgress.record_tier_clear / get_tier_record ───────────────────────

func _test_tier_records() -> void:
	var pp: Node = load("res://scripts/player_progress.gd").new()

	# Unseen tier reads as zeros, never cleared.
	var fresh: Dictionary = pp.get_tier_record(1501)
	_check(int(fresh["clears"]) == 0 and int(fresh["fewest_darts"]) == 0, "unseen tier reads zeros")

	# First clear at 27 cumulative darts.
	pp.record_tier_clear(501, 27)
	var r1: Dictionary = pp.get_tier_record(501)
	_check(int(r1["clears"]) == 1 and int(r1["fewest_darts"]) == 27, "501 first clear: ×1, best 27")

	# A slower second clear bumps the count but does NOT raise the fewest-darts best.
	pp.record_tier_clear(501, 40)
	var r2: Dictionary = pp.get_tier_record(501)
	_check(int(r2["clears"]) == 2 and int(r2["fewest_darts"]) == 27, "501 slower clear: ×2, best stays 27")

	# A faster third clear lowers the best.
	pp.record_tier_clear(501, 22)
	var r3: Dictionary = pp.get_tier_record(501)
	_check(int(r3["clears"]) == 3 and int(r3["fewest_darts"]) == 22, "501 faster clear: ×3, best 22")

	# Tiers are independent — clearing 1001 doesn't touch 501.
	pp.record_tier_clear(1001, 64)
	_check(int(pp.get_tier_record(1001)["fewest_darts"]) == 64, "1001 best 64")
	_check(int(pp.get_tier_record(501)["clears"]) == 3, "501 untouched by 1001 clear")
	pp.free()


# ── PlayerProgress.record_run_point / get_best_run ───────────────────────────

func _test_best_run() -> void:
	var pp: Node = load("res://scripts/player_progress.gd").new()
	_check(pp.get_best_run().is_empty(), "best run empty before any run")

	# First run end: died in act 0 at depth 4, 30 darts.
	pp.record_run_point(0, 4, 30)
	var b1: Dictionary = pp.get_best_run()
	_check(int(b1["act"]) == 0 and int(b1["depth"]) == 4 and int(b1["darts"]) == 30, "first point recorded")

	# A SHALLOWER later run does not replace it, even with more darts.
	pp.record_run_point(0, 2, 99)
	_check(int(pp.get_best_run()["depth"]) == 4, "shallower run does not overwrite")

	# A DEEPER run wins even with MORE darts (furthest is the primary key).
	pp.record_run_point(1, 1, 200)
	var b2: Dictionary = pp.get_best_run()
	_check(int(b2["act"]) == 1 and int(b2["depth"]) == 1, "deeper run wins regardless of darts")

	# Same depth, fewer darts → improves; same depth, more darts → ignored.
	pp.record_run_point(1, 1, 150)
	_check(int(pp.get_best_run()["darts"]) == 150, "tie on depth breaks to fewer darts")
	pp.record_run_point(1, 1, 175)
	_check(int(pp.get_best_run()["darts"]) == 150, "costlier tie ignored")
	pp.free()


# ── Anti-inert guard (feedback-rolled-generator-spread): distinct runs must produce distinct
# recorded benchmark values, not a default-frozen display. ──────────────────────────────────

func _test_benchmarks_vary() -> void:
	var pp: Node = load("res://scripts/player_progress.gd").new()
	pp.record_tier_clear(501, 27)
	pp.record_tier_clear(1001, 64)
	pp.record_run_point(2, 5, 142)
	# The three surfaces hold three genuinely different numbers (not all equal to a default 0/seed).
	var darts501: int = int(pp.get_tier_record(501)["fewest_darts"])
	var darts1001: int = int(pp.get_tier_record(1001)["fewest_darts"])
	var bestdarts: int = int(pp.get_best_run()["darts"])
	_check(darts501 == 27 and darts1001 == 64 and bestdarts == 142, "recorded values are the inputs")
	_check(darts501 != darts1001 and darts1001 != bestdarts, "benchmark numbers vary, not inert")
	pp.free()


# ── Non-destructive save snapshot/restore ────────────────────────────────────

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		_saved_bytes = f.get_buffer(f.get_length())
		f.close()


func _restore_save() -> void:
	if _had_save:
		var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		# No save existed before — remove the one our standalone instances wrote.
		var d: DirAccess = DirAccess.open("user://")
		if d != null:
			d.remove("progress.tres")
