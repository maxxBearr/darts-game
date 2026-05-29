extends Node
@onready var dart_thunk_1: AudioStreamPlayer = $DartThunk1
@onready var dart_thunk_2: AudioStreamPlayer = $DartThunk2
@onready var bonus_score: AudioStreamPlayer = $BonusScore
@onready var hit_void_thunk: AudioStreamPlayer = $hit_void_thunk
@onready var ui_click: AudioStreamPlayer = $UIclick
@onready var leg_win_sound: AudioStreamPlayer = $leg_win_sound
@onready var leg_lost_sound: AudioStreamPlayer = $leg_lost_sound
@onready var source_label_slam: AudioStreamPlayer = $SourceLabelSlam
@onready var menu_music: AudioStreamPlayer = $MenuMusic
@onready var game_music: AudioStreamPlayer = $GameMusic

const BONUS_BASE_PITCH: float = 0.9
const BONUS_PITCH_STEP: float = 0.15
const MUSIC_FADE_DURATION: float = 1.5
const PITCH_TWEEN_DURATION: float = 0.4
const MUSIC_SILENT_DB: float = -40.0

var _music_tween: Tween = null
var _pitch_tween: Tween = null


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	menu_music.finished.connect(menu_music.play)
	game_music.finished.connect(game_music.play)
	menu_music.play()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play_ui_click)


func play_dart_thunk() -> void:
	var pitch: float = randf_range(0.88, 1.2)
	var roll: int = randi() % 2
	if roll == 0:
		print("dart thunk 2 played from 2.3")
		dart_thunk_2.pitch_scale = pitch
		dart_thunk_2.play(2.3)
	elif roll == 1:
		dart_thunk_2.pitch_scale = pitch
		print("dart think 2 played from 0.34")
		dart_thunk_2.play(0.34)
		get_tree().create_timer(0.5).timeout.connect(
			func(): dart_thunk_2.stop()
		)



func play_void_hit() -> void:
	hit_void_thunk.play()


func play_ui_click() -> void:
	ui_click.play()


func play_leg_win(pitch: float = 1.0) -> void:
	leg_win_sound.pitch_scale = pitch
	leg_win_sound.play()


func play_bonus_hit(trigger_index: int) -> void:
	bonus_score.pitch_scale = BONUS_BASE_PITCH + BONUS_PITCH_STEP * trigger_index
	bonus_score.play()


var _slam_pitch_accumulator: float = 0.0


func play_source_label_slam(is_replacement: bool = false) -> void:
	var base: float = 1.1 if is_replacement else 1.0
	source_label_slam.pitch_scale = base + _slam_pitch_accumulator
	source_label_slam.play(0.05)
	get_tree().create_timer(0.55).timeout.connect(func(): source_label_slam.stop())
	_slam_pitch_accumulator += 0.01


func reset_slam_pitch() -> void:
	_slam_pitch_accumulator = 0.0


func transition_to_game_music() -> void:
	_kill_music_tween()
	_kill_pitch_tween()
	game_music.volume_db = MUSIC_SILENT_DB
	game_music.pitch_scale = 0.85
	game_music.play()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(menu_music, "volume_db", MUSIC_SILENT_DB, MUSIC_FADE_DURATION)
	_music_tween.tween_property(menu_music, "pitch_scale", 0.85, MUSIC_FADE_DURATION)
	_music_tween.tween_property(game_music, "volume_db", -13.0, MUSIC_FADE_DURATION)
	_music_tween.tween_property(game_music, "pitch_scale", 1.0, MUSIC_FADE_DURATION)
	_music_tween.set_parallel(false)
	_music_tween.tween_callback(menu_music.stop)


func transition_to_menu_music() -> void:
	_kill_music_tween()
	_kill_pitch_tween()
	menu_music.volume_db = MUSIC_SILENT_DB
	menu_music.pitch_scale = 0.85
	menu_music.play()
	var current_game_pitch: float = game_music.pitch_scale
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(game_music, "volume_db", MUSIC_SILENT_DB, MUSIC_FADE_DURATION)
	_music_tween.tween_property(game_music, "pitch_scale", maxf(current_game_pitch - 0.15, 0.3), MUSIC_FADE_DURATION)
	_music_tween.tween_property(menu_music, "volume_db", 0.0, MUSIC_FADE_DURATION)
	_music_tween.tween_property(menu_music, "pitch_scale", 1.0, MUSIC_FADE_DURATION)
	_music_tween.set_parallel(false)
	_music_tween.tween_callback(game_music.stop)


func on_turn_ended(turn_number: int) -> void:
	var delta: float
	if turn_number ==1:
		delta = -0.035
	if turn_number ==2:
		delta = -0.043
	elif turn_number == 3:
		delta = -0.05
	elif turn_number ==4:
		delta = -0.07
	_tween_game_pitch(game_music.pitch_scale + delta)


func on_leg_won() -> void:
	_tween_game_pitch(1.0)


func on_leg_lost() -> void:
	_tween_game_pitch(game_music.pitch_scale - 0.5)


func _tween_game_pitch(target: float) -> void:
	_kill_pitch_tween()
	_pitch_tween = create_tween()
	_pitch_tween.tween_property(game_music, "pitch_scale", target, PITCH_TWEEN_DURATION)


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


func _kill_pitch_tween() -> void:
	if _pitch_tween != null and _pitch_tween.is_valid():
		_pitch_tween.kill()
	_pitch_tween = null
