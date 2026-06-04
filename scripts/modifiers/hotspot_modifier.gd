class_name HotspotModifier
extends ScoringModifier
## Marks one chosen ring on one wedge as a "hotspot" — a flat bonus folded into that
## segment's baseline multiplier every time a dart lands there (face × (ring + hotspot)
## × streak). The headline Scoring-family item: the cleanest expression of the
## "scoring lives on the board" thesis. Consumable — one ring per item, no panel
## presence after acquisition (the on-board indicator is its only marker).
##
## Magnitude folds into the ADDITIVE baseline (it is NOT a standalone ×N), so it stays
## legible and bounded: common +1, uncommon +2, rare +3 to the multiplier.
##
## No-stack (LOCKED): one hotspot tier per ring, max +3. A second hotspot must go on a
## different ring — duplicates spread the board rather than over-juicing one spot. The
## segment picker enforces this by disallowing an already-hot ring (never a silent
## downgrade). The manager (ScoringModifierManager._register_hotspot) reads the stored
## choice below and writes it into hotspot_rings on acquire.

## Flat multiplier bonus this hotspot grants the chosen ring. Rolled by rarity at
## generation: common 1, uncommon 2, rare 3. Folds additively into the baseline.
@export var hotspot_bonus: int = 1

## The wedge index (0-19) the hotspot was placed on. Set during apply_to_board, read by
## the manager to register the hotspot. -1 = unconfigured.
var applied_wedge_index: int = -1

## The ring the hotspot was placed on, as the lowercase dict key ("inner_single",
## "triple", "outer_single", "double") supplied by the segment picker. The manager
## converts this to the display ring name when keying hotspot_rings.
var applied_ring_key: String = ""


func _init() -> void:
	modifier_name = "Hotspot"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_SEGMENT
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION
	family = ScoringEnums.Family.SCORING


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), hotspot_bonus]


## Record the player's segment choice. A hotspot does NOT mutate wedge values or colors —
## it lives in the manager's hotspot_rings board state — so this only stores the choice
## for the manager to register after the call.
func apply_to_board(_wedge_values: Array[int], _wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	applied_wedge_index = config["wedge_index"]
	applied_ring_key = config["ring_name"]


func get_pick_segment_header() -> String:
	return "Place a +%d hotspot" % hotspot_bonus


func get_pick_segment_prompt(ring_display: String, face_value: int, _color_name: String) -> String:
	return "Make %s %d a +%d hotspot? Click to confirm, Escape to cancel" % [ring_display, face_value, hotspot_bonus]


static func get_pool_weight() -> int:
	return 25


static func get_rarity_weights() -> Array[int]:
	return [65, 25, 10]


static func generate(rarity_tier: ScoringEnums.Rarity) -> HotspotModifier:
	var mod: HotspotModifier = HotspotModifier.new()
	mod.rarity_tier = rarity_tier

	# Magnitude ladder mirrors the rarity tiers — common/uncommon/rare = +1/+2/+3, capped
	# at +3 by construction (the no-stack rule keeps a single ring at one tier).
	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.hotspot_bonus = 1
		ScoringEnums.Rarity.UNCOMMON:
			mod.hotspot_bonus = 2
		ScoringEnums.Rarity.RARE:
			mod.hotspot_bonus = 3

	mod.modifier_name = "Hotspot +%d" % mod.hotspot_bonus
	mod.description = "Mark a ring as a +%d hotspot (adds to its multiplier)" % mod.hotspot_bonus

	return mod
