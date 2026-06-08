class_name ChallengeEntryView
extends Control
## The challenge node's pre-entry readout + ice-tray deposit picker (Phase 02 §10). Built
## programmatically (code-first rough visuals, matching slice 1's grey-rect MapView — art
## reskin later). Surfaces everything difficulty-relevant BEFORE the wager: target, the
## rolled darts-per-turn (the bust grain), the deposit band, the offered reward family, and
## any handicap. The player picks an integer deposit (clamped to their bank); the ice-tray
## preview renders it as rows of dpt with a partial last row so the bust unit is visible.

## Emitted with the chosen deposit (raw darts) when the player confirms the wager.
signal confirmed(deposit: int)
## Emitted when the player declines — they take the parallel leg instead (§12).
signal skipped

var _challenge: ChallengeNode = null
var _bank: int = 0
var _deposit: int = 0
var _max_affordable: int = 0      ## min(max_deposit, bank) — can't stake darts you don't have

## Lazily-built family-icon source, so the reward line can show the reward-family glyph inline
## (RichTextLabel [img]) — the same icons the map nodes + typed shop use.
var _family_icons: EventFamilyIcons = null

var _readout: RichTextLabel
var _deposit_label: Label
var _ice_tray_label: Label
var _confirm_btn: Button
var _minus_btn: Button
var _plus_btn: Button


func _ready() -> void:
	# Full-rect dimmer that eats clicks so the board/map behind can't be touched.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "CHALLENGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.fit_content = true
	_readout.custom_minimum_size = Vector2(0, 150)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_readout)

	# Deposit stepper row: [−]  deposit N  [+]
	var stepper: HBoxContainer = HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override("separation", 12)
	vbox.add_child(stepper)

	_minus_btn = Button.new()
	_minus_btn.text = "−"
	_minus_btn.custom_minimum_size = Vector2(44, 44)
	_minus_btn.pressed.connect(_on_step.bind(-1))
	stepper.add_child(_minus_btn)

	_deposit_label = Label.new()
	_deposit_label.custom_minimum_size = Vector2(160, 0)
	_deposit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deposit_label.add_theme_font_size_override("font_size", 20)
	stepper.add_child(_deposit_label)

	_plus_btn = Button.new()
	_plus_btn.text = "+"
	_plus_btn.custom_minimum_size = Vector2(44, 44)
	_plus_btn.pressed.connect(_on_step.bind(1))
	stepper.add_child(_plus_btn)

	_ice_tray_label = Label.new()
	_ice_tray_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ice_tray_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_ice_tray_label)

	# Action row: [Wager N darts]  [Skip]
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	vbox.add_child(actions)

	_confirm_btn = Button.new()
	_confirm_btn.custom_minimum_size = Vector2(180, 48)
	_confirm_btn.pressed.connect(_on_confirm)
	actions.add_child(_confirm_btn)

	var skip_btn: Button = Button.new()
	skip_btn.text = "Skip (take the leg)"
	skip_btn.custom_minimum_size = Vector2(180, 48)
	skip_btn.pressed.connect(_on_skip)
	actions.add_child(skip_btn)


## Open the picker for a challenge whose target/deposit band have already been computed
## (MapGraph.compute_challenge_params). `bank` is the player's current banked darts.
func show_for(challenge: ChallengeNode, bank: int) -> void:
	_challenge = challenge
	_bank = bank
	_max_affordable = mini(challenge.max_deposit, bank)
	_deposit = clampi(challenge.min_deposit, challenge.min_deposit, maxi(_max_affordable, challenge.min_deposit))
	_refresh()
	visible = true


func _family_name(f: ScoringEnums.Family) -> String:
	match f:
		ScoringEnums.Family.SCORING: return "Scoring"
		ScoringEnums.Family.PLACEMENT: return "Placement"
		ScoringEnums.Family.BRUSH: return "Brush"
		_: return "Any"


## Inline BBCode `[img]` for the reward-family icon (the same texture the map node shows), or ""
## when the family has no icon. Reuses EventFamilyIcons so the path isn't duplicated.
func _reward_icon_bb(f: ScoringEnums.Family) -> String:
	if _family_icons == null:
		_family_icons = EventFamilyIcons.new()
	var tex: Texture2D = _family_icons.texture_for(EventFamilyIcons.key_for_family(f))
	if tex == null or tex.resource_path == "":
		return ""
	return "[img=20x20]%s[/img] " % tex.resource_path


func _handicap_name(id: StringName) -> String:
	match id:
		&"rotation": return "Rotating board"
		&"narrow_double": return "Narrowed double ring"
		&"even_out": return "Even Out (finish on even-valued wedges)"
		&"odd_out": return "Odd Out (finish on odd-valued wedges)"
		_: return "None (clean race)"


func _refresh() -> void:
	var c: ChallengeNode = _challenge
	var affordable: bool = _bank >= c.min_deposit
	var text: String = ""
	text += "[b]Target:[/b] %d   [b]Darts/turn:[/b] %d\n" % [c.target_score, c.darts_per_turn]
	text += "[b]Wager band:[/b] %d–%d darts\n" % [c.min_deposit, c.max_deposit]
	text += "[b]Reward:[/b] %s%s item (rarer the fewer darts you use)\n" % [_reward_icon_bb(c.reward_family), _family_name(c.reward_family)]
	text += "[b]Handicap:[/b] %s\n" % _handicap_name(c.handicap_id)
	text += "[b]Bank:[/b] %d darts\n" % _bank
	text += "\n[i]The wager IS your budget. Lose and you forfeit all of it; win and unused darts return to the bank.[/i]"
	if not affordable:
		text += "\n\n[color=#ff6666]Bank too low — need at least %d to enter.[/color]" % c.min_deposit
	_readout.text = text

	_deposit_label.text = "Wager: %d" % _deposit
	_ice_tray_label.text = "Rows: %s" % _ice_tray_string()

	_confirm_btn.disabled = not affordable
	_confirm_btn.text = "Wager %d darts" % _deposit if affordable else "Can't afford"
	_minus_btn.disabled = (not affordable) or _deposit <= c.min_deposit
	_plus_btn.disabled = (not affordable) or _deposit >= _max_affordable


## Render the current deposit as ice-tray rows, e.g. "[2][2][2][1]".
func _ice_tray_string() -> String:
	var s: String = ""
	for row: int in _challenge.ice_tray_rows(_deposit):
		s += "[%d]" % row
	return s


func _on_step(delta: int) -> void:
	_deposit = clampi(_deposit + delta, _challenge.min_deposit, _max_affordable)
	_refresh()


func _on_confirm() -> void:
	if _bank < _challenge.min_deposit:
		return
	visible = false
	confirmed.emit(_deposit)


func _on_skip() -> void:
	visible = false
	skipped.emit()
