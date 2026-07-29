extends SceneTree

## Measures how much a tile's terrain noise resembles the tile next to it.

func _init() -> void:
	print("— noise coherence —\n")
	_measure("terrain (world.gd)", 0.09, 10.0)
	_measure("detail/rivers  ", 0.20, 10.0)
	print("\nsame noise, sampled at tile coordinates instead:")
	_measure("terrain fixed  ", 0.09, 1.0)
	_measure("detail fixed   ", 0.20, 1.0)
	quit(0)


func _measure(label: String, frequency: float, coord_scale: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 12345
	noise.frequency = frequency
	noise.fractal_octaves = 3

	var diff := 0.0
	var n := 0
	for x in range(-14, 15):
		for y in range(-14, 15):
			var here := noise.get_noise_2d(x * coord_scale, y * coord_scale)
			var east := noise.get_noise_2d((x + 1) * coord_scale, y * coord_scale)
			diff += absf(here - east)
			n += 1

	# A coherent heightfield changes a little between neighbours. Uncorrelated
	# samples average ~0.35 apart for this noise's range.
	print("  %s  freq %.2f · step %4.1f  →  mean neighbour jump %.3f" % [
		label, frequency, frequency * coord_scale, diff / float(n)])
