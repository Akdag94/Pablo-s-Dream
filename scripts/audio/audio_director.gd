extends Node

## Owns every sound that comes out of the game.
##
## Autoloaded as `Audio`. Call sites say what happened — `Audio.play("place")` —
## and never which file to load or how loud it should be. That split is the
## same one `core/` and `render/` already have: the thing that knows the event
## does not know the presentation.
##
## Voices are pooled and reused. Creating an AudioStreamPlayer per sound works
## on desktop and stutters on a phone, and this game is a phone game first.

const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"

## Enough voices that a burst never cuts something audible short, few enough
## that they all fit in a mobile mixer without thought.
const UI_VOICES := 8
const WORLD_VOICES := 6

## Beyond this the sound of a machine is not worth mixing in.
const WORLD_MAX_DISTANCE := 60.0

const AMBIENCE_FADE := 2.5

## Set false to silence the game without tearing anything down.
var enabled := true

var _ui_pool: Array[AudioStreamPlayer] = []
var _world_pool: Array[AudioStreamPlayer3D] = []
var _ui_next := 0
var _world_next := 0

## Cue id -> the tick it last fired on, for the per-cue rate limit.
var _last_fired: Dictionary = {}
## Path -> AudioStream. Cues are drawn from a fixed set, so this settles fast.
var _cache: Dictionary = {}
## Paths already found missing, so a stub ambience file is looked for once.
var _missing: Dictionary = {}

var _rng := RandomNumberGenerator.new()

var _ambience: AudioStreamPlayer
var _ambience_path := ""
var _ambience_tween: Tween


func _ready() -> void:
	_rng.randomize()
	_ensure_bus(BUS_SFX, 0.0)
	# Ambience sits under the effects so a cue always reads over the top of it.
	_ensure_bus(BUS_AMBIENCE, -8.0)
	_build_pools()


## Godot ships a bus layout with Master alone. Creating the two we want here
## rather than in a `.tres` keeps the mix readable in a diff, and means a
## missing resource can never silence the game.
func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, volume_db)


func _build_pools() -> void:
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_ui_pool.append(p)

	for i in WORLD_VOICES:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUS_SFX
		p3.max_distance = WORLD_MAX_DISTANCE
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_world_pool.append(p3)

	_ambience = AudioStreamPlayer.new()
	_ambience.bus = BUS_AMBIENCE
	_ambience.volume_db = -80.0
	add_child(_ambience)


# ---------------------------------------------------------------------- cues

## Fire a cue by name. `world_position` is only read by positional cues; pass
## the tile something happened on and the sound comes from there.
func play(id: String, world_position: Variant = null) -> void:
	if not enabled:
		return

	var cue := SoundBank.cue(id)
	if cue.is_empty():
		push_warning("Unknown sound cue: %s" % id)
		return

	if not _rate_allows(id, float(cue["min_interval"])):
		return

	var stream := _pick(cue["files"])
	if stream == null:
		return

	var pitch := 1.0
	var spread: float = cue["pitch_spread"]
	if spread > 0.0:
		pitch = 1.0 + _rng.randf_range(-spread, spread)

	if cue["positional"] and world_position is Vector3:
		var p3 := _take_world()
		p3.global_position = world_position
		p3.stream = stream
		p3.volume_db = cue["volume_db"]
		p3.pitch_scale = pitch
		p3.play()
	else:
		var p := _take_ui()
		p.stream = stream
		p.volume_db = cue["volume_db"]
		p.pitch_scale = pitch
		p.play()


func _rate_allows(id: String, min_interval: float) -> bool:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var last: float = _last_fired.get(id, -1000.0)
	if now - last < min_interval:
		return false
	_last_fired[id] = now
	return true


## A different take each time, never the same one twice running.
func _pick(files: PackedStringArray) -> AudioStream:
	if files.is_empty():
		return null
	var path := files[_rng.randi() % files.size()]
	return _load(path)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if _missing.has(path):
		return null
	if not ResourceLoader.exists(path):
		_missing[path] = true
		return null
	var stream: AudioStream = load(path)
	_cache[path] = stream
	return stream


## Prefer a voice that is not busy; steal the oldest one only when they all are.
func _take_ui() -> AudioStreamPlayer:
	for p in _ui_pool:
		if not p.playing:
			return p
	var chosen := _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_pool.size()
	return chosen


func _take_world() -> AudioStreamPlayer3D:
	for p in _world_pool:
		if not p.playing:
			return p
	var chosen := _world_pool[_world_next]
	_world_next = (_world_next + 1) % _world_pool.size()
	return chosen


# ----------------------------------------------------------------- ambience

## Cross-fade to a looping bed. Passing "" fades to silence.
##
## The files this reaches for are not in the repo yet (ASSETS.md §7). Until
## they are, every call lands on silence and nothing else changes — which is
## the behaviour we want anyway for the ending.
func set_ambience(path: String) -> void:
	if path == _ambience_path:
		return
	_ambience_path = path

	var stream: AudioStream = null
	if not path.is_empty():
		stream = _load(path)

	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
		_ambience_tween = null

	# Nothing playing and nothing to play — the common case until the ambience
	# files land. Silence is the correct outcome, so there is no fade to run.
	if stream == null and not _ambience.playing:
		return

	_ambience_tween = create_tween()

	if _ambience.playing:
		_ambience_tween.tween_property(_ambience, "volume_db", -80.0, AMBIENCE_FADE * 0.5)
		_ambience_tween.tween_callback(func() -> void: _ambience.stop())

	if stream == null:
		return

	_ambience_tween.tween_callback(func() -> void:
		_ambience.stream = stream
		_ambience.volume_db = -80.0
		_ambience.play())
	_ambience_tween.tween_property(_ambience, "volume_db", 0.0, AMBIENCE_FADE)


func set_ambience_for_phase(phase: int) -> void:
	set_ambience(SoundBank.ambience_for_phase(phase))


# -------------------------------------------------------------------- mixing

func set_bus_volume(bus_name: String, volume_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, volume_db)


func set_muted(muted: bool) -> void:
	enabled = not muted
	var idx := AudioServer.get_bus_index("Master")
	if idx != -1:
		AudioServer.set_bus_mute(idx, muted)
	if muted:
		_ambience.stop()
		_ambience_path = ""
