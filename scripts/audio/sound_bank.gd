class_name SoundBank
extends RefCounted

## Every sound the game can make, and how it should sound.
##
## >>> ALL AUDIO TUNING LIVES HERE <<< — the same rule `catalog.gd` follows for
## buildings. `audio_director.gd` knows how to play a cue; it does not know what
## any cue is.
##
## A cue names several files rather than one. The same click fired forty times
## in a row is the sound of a menu, not of a place, so the director picks a
## different take each time and shifts the pitch slightly.
##
## Files are referenced by path, not `preload`, so this file stays a plain
## table. Godot's default export mode ships every resource in the project, so
## nothing here needs to be reachable from a scene to survive an export.

const UI := "res://assets/audio/ui/Audio/"

## Ambience loops. None of these exist yet — see ASSETS.md §7. The director
## treats a missing file as silence, so the game runs today and gains its
## ambience the moment the files are dropped in.
const AMBIENCE := "res://assets/audio/ambience/"

## Applied to any field a cue leaves out.
const DEFAULTS := {
	"volume_db": -6.0,
	## Half-range, in semitone-ish scale factor. 0.04 is audible as variety
	## without sounding broken.
	"pitch_spread": 0.04,
	## Refuse to retrigger the same cue faster than this, in seconds. Stops a
	## dragged finger or a burst of settling species from turning into a buzz.
	"min_interval": 0.06,
	## Positional cues play from the tile they happened on, in 3D.
	"positional": false,
}

## Sound is deliberately sparse. This game is about a quiet place coming back;
## a cue for every leaf earned would bury the two moments that matter — a
## species arriving, and a phase turning over.
const CUES := {
	## Tapping a tile. Frequent, so it sits well under everything else.
	"select": {
		"files": ["click_001.ogg", "click_002.ogg", "click_003.ogg"],
		"volume_db": -17.0,
		"min_interval": 0.08,
	},
	## Choosing a machine from the build strip.
	"tool": {
		"files": ["select_002.ogg", "select_004.ogg", "select_006.ogg"],
		"volume_db": -11.0,
	},
	## Backing out of a selection without spending anything.
	"cancel": {
		"files": ["close_001.ogg", "close_003.ogg"],
		"volume_db": -13.0,
	},
	## A machine committed to the ground. Plays from where it landed.
	"place": {
		"files": ["drop_001.ogg", "drop_002.ogg", "drop_003.ogg", "drop_004.ogg"],
		"volume_db": -4.0,
		"positional": true,
	},
	## Refused placement — wrong ground, too few leaves, not unlocked yet.
	"denied": {
		"files": ["error_006.ogg", "error_007.ogg"],
		"volume_db": -12.0,
		"min_interval": 0.25,
	},
	## Selling a machine back. An undo, so it uses the back sound.
	"sell": {
		"files": ["back_002.ogg", "back_004.ogg"],
		"volume_db": -8.0,
		"positional": true,
	},
	## A phase turned over. One chime, no variation — it should land the same
	## way every time so it reads as the same event.
	"phase": {
		"files": ["bong_001.ogg"],
		"volume_db": -5.0,
		"pitch_spread": 0.0,
		"min_interval": 1.0,
	},
	## An animal decided the place was liveable. The warmest sound in the game,
	## and the one the player is actually playing for.
	"species": {
		"files": ["pluck_001.ogg", "pluck_002.ogg"],
		"volume_db": -3.0,
		"pitch_spread": 0.06,
		"min_interval": 0.4,
	},
	## The airship lifts. Once per run.
	"launch": {
		"files": ["maximize_006.ogg"],
		"volume_db": -3.0,
		"pitch_spread": 0.0,
	},
}

## Ambience per phase. The world opens nearly silent and gains a voice as it
## comes back — wind over dead ground, then water, then birds. Phase 4 drops
## back to wind alone: the machines are leaving and so are you.
const PHASE_AMBIENCE := {
	0: "wind.ogg",     # RESTORE
	1: "water.ogg",    # CULTIVATE
	2: "birds.ogg",    # WILDLIFE
	3: "wind.ogg",     # RECLAIM
	4: "",             # DONE — the ending is silence, on purpose.
}


## A cue with every default filled in, or an empty Dictionary if unknown.
static func cue(id: String) -> Dictionary:
	if not CUES.has(id):
		return {}
	var out: Dictionary = DEFAULTS.duplicate()
	for key in CUES[id]:
		out[key] = CUES[id][key]
	out["files"] = _prefixed(out.get("files", []))
	return out


static func _prefixed(files: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		out.append(UI + str(f))
	return out


## Full path to a phase's ambience loop, or "" when that phase is silent.
static func ambience_for_phase(phase: int) -> String:
	var file: String = PHASE_AMBIENCE.get(phase, "")
	if file.is_empty():
		return ""
	return AMBIENCE + file
