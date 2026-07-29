class_name Quality
extends RefCounted

## Rendering budget, picked from what the device can actually sustain.
##
## Photoreal lighting is a desktop-class cost. Rather than shipping one
## pipeline and hoping, each tier states exactly what it turns off, so the
## mobile build degrades in a way we chose rather than in a way we discovered
## at submission time.

enum Tier { LOW, MEDIUM, HIGH }

var tier: Tier = Tier.HIGH

## Screen-space reflections on the water.
var reflections: bool = true
## Screen-space ambient occlusion in tile crevices.
var ambient_occlusion: bool = true
## Real-time shadows from the sun.
var shadows: bool = true
var shadow_size: int = 4096
## Depth of field on the far edge of the map.
var depth_of_field: bool = true
## Scattered vegetation instances per living hex.
var foliage_per_tile: int = 6
## Render scale — below 1.0 renders small and upscales.
var render_scale: float = 1.0
var msaa: Viewport.MSAA = Viewport.MSAA_4X


static func detect() -> Quality:
	var q := Quality.new()
	if OS.has_feature("mobile") or OS.has_feature("web"):
		q.apply(Tier.LOW)
	else:
		q.apply(Tier.HIGH)
	return q


func apply(p_tier: Tier) -> void:
	tier = p_tier
	match tier:
		Tier.LOW:
			reflections = false
			ambient_occlusion = false
			shadows = true
			shadow_size = 2048
			depth_of_field = false
			foliage_per_tile = 2
			render_scale = 0.85
			msaa = Viewport.MSAA_2X
		Tier.MEDIUM:
			reflections = false
			ambient_occlusion = true
			shadows = true
			shadow_size = 3072
			depth_of_field = false
			foliage_per_tile = 4
			render_scale = 1.0
			msaa = Viewport.MSAA_2X
		Tier.HIGH:
			reflections = true
			ambient_occlusion = true
			shadows = true
			shadow_size = 4096
			depth_of_field = true
			foliage_per_tile = 6
			render_scale = 1.0
			msaa = Viewport.MSAA_4X


func tier_name() -> String:
	return Tier.keys()[tier].capitalize()
