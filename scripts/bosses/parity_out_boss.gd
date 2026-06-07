class_name ParityOutBoss
extends Boss
## Parity Out — a challenge race handicap (geometry spec §9b). The finishing double must sit on a
## wedge whose CURRENT effective face value matches a parity (Even Out / Odd Out). It halves the
## out-set and rewires the checkout table rather than making the same checkout harder, and it is
## CONTESTABLE: a Wedge Value +1 flips a dead double live mid-race (validity reads the live
## effective_wedge_values via the manager). The bull is EXEMPT ("the bull always outs" — 25 is
## odd, but exempting it keeps 50 finishable under Even Out).
##
## Driven directly by main as a recycled benched-boss handicap (not via boss_manager). The
## even/odd variant is selected from the handicap_id main passes into configure(): both
## &"even_out" and &"odd_out" map here. The actual finish-validity lives in the out-rule seam
## (ScoringModifierManager / x01_game checkout_parity, mirrored to the dartboard for dimming via
## main._sync_board_and_solver); this boss just sets and clears that one knob across the leg.

## 0 = grow/keep EVEN-valued wedges (Even Out), 1 = ODD-valued wedges (Odd Out). Defaults to even.
var parity: int = 0


func configure(tuning: Dictionary) -> void:
	# Prefer an explicit parity if a caller sets it; otherwise derive from the handicap id.
	if tuning.has("parity"):
		parity = int(tuning["parity"])
	else:
		var id: StringName = tuning.get("handicap_id", &"even_out")
		parity = 1 if id == &"odd_out" else 0


func get_status_text() -> String:
	return "Finish on %s-valued wedges only" % ("even" if parity == 0 else "odd")


func on_leg_start(game_state: Dictionary) -> void:
	# Set the out-rule on BOTH the engine (live win/bust) and the manager (solver + board dim).
	# main._sync_board_and_solver() then mirrors the manager's parity to the dartboard and studs.
	var x01: Node = game_state["x01_game"]
	var smm: Node = game_state["scoring_modifier_manager"]
	x01.checkout_parity = parity
	smm.checkout_parity = parity


func on_leg_end(game_state: Dictionary) -> void:
	# Clear the out-rule back to standard double-out so the next leg races clean.
	var x01: Node = game_state["x01_game"]
	var smm: Node = game_state["scoring_modifier_manager"]
	x01.checkout_parity = -1
	smm.checkout_parity = -1
