extends Node
@onready var dart_thunk_1: AudioStreamPlayer = $DartThunk1
@onready var dart_thunk_2: AudioStreamPlayer = $DartThunk2
@onready var bonus_score: AudioStreamPlayer = $BonusScore

const BONUS_BASE_PITCH: float = 0.9
const BONUS_PITCH_STEP: float = 0.15




func play_dart_thunk() -> void:
	var pitch: float = randf_range(0.88, 1.2)
	if randi() % 2 == 0:
		dart_thunk_1.pitch_scale = pitch
		dart_thunk_1.play()
	else:
		dart_thunk_2.pitch_scale = pitch
		dart_thunk_2.play(2.1)


func play_bonus_hit(trigger_index: int) -> void:
	bonus_score.pitch_scale = BONUS_BASE_PITCH + BONUS_PITCH_STEP * trigger_index
	bonus_score.play()
