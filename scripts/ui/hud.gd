extends Control

## Top bar (leaves + current objective) and the bottom build bar.
##
## The bar is rebuilt whenever the phase changes, so each phase only ever
## offers the buildings that belong to it.

@export var world_view_path: NodePath

var _view: Node2D
var _state: GameState

var _leaf_label: Label
var _objective_label: Label
var _build_bar: HBoxContainer
var _launch_button: Button
var _tooltip: Label
var _wildlife_list: VBoxContainer
var _pablo_label: Label


func _ready() -> void:
	_view = get_node(world_view_path)
	_state = _view.state

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar()
	_build_bottom_bar()
	_build_wildlife_panel()

	_state.leaves_changed.connect(_on_leaves_changed)
	_state.phase_changed.connect(_on_phase_changed)
	_state.objective_updated.connect(_refresh_objective)
	_state.run_finished.connect(_on_run_finished)
	_view.build_attempted.connect(_on_build_attempted)
	_state.wildlife.species_settled.connect(_on_species_settled)
	_state.wildlife.species_lost.connect(func(_id): _refresh_wildlife())
	_state.pablo.mood_changed.connect(func(_m): _refresh_pablo())

	_on_leaves_changed(_state.leaves)
	_populate_build_bar()
	_refresh_wildlife()
	_refresh_pablo()


# --------------------------------------------------------------------- layout

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	_leaf_label = Label.new()
	_leaf_label.add_theme_font_size_override("font_size", 22)
	row.add_child(_leaf_label)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_objective_label)


func _build_bottom_bar() -> void:
	var wrap := VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.alignment = BoxContainer.ALIGNMENT_END
	wrap.offset_top = -150
	add_child(wrap)

	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", 15)
	_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(_tooltip)

	var panel := PanelContainer.new()
	wrap.add_child(panel)

	_build_bar = HBoxContainer.new()
	_build_bar.add_theme_constant_override("separation", 8)
	_build_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_build_bar)

	_launch_button = Button.new()
	_launch_button.text = tr("UI_LAUNCH")
	_launch_button.visible = false
	_launch_button.pressed.connect(_on_launch_pressed)
	wrap.add_child(_launch_button)


## Right-hand column: who lives here, and who is nearly ready to.
func _build_wildlife_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -260
	panel.offset_top = 56
	panel.offset_right = -12
	add_child(panel)

	_wildlife_list = VBoxContainer.new()
	_wildlife_list.add_theme_constant_override("separation", 4)
	panel.add_child(_wildlife_list)

	_pablo_label = Label.new()
	_pablo_label.add_theme_font_size_override("font_size", 15)
	_pablo_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pablo_label.offset_left = 16
	_pablo_label.offset_top = -180
	add_child(_pablo_label)


func _refresh_wildlife() -> void:
	for child in _wildlife_list.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "%s  %d / %d" % [
		tr("UI_WILDLIFE"), _state.wildlife.count(), GameState.REQUIRED_SPECIES
	]
	heading.add_theme_font_size_override("font_size", 16)
	_wildlife_list.add_child(heading)

	for id in _state.wildlife.settled:
		var def: SpeciesDef = Bestiary.get_species(id)
		var row := Label.new()
		row.text = "  ✓  %s" % def.name_text()
		row.add_theme_color_override("font_color", def.color)
		row.add_theme_font_size_override("font_size", 14)
		_wildlife_list.add_child(row)

	# Show the three closest near-misses so the player knows what to build next.
	for entry in _state.wildlife.nearest_candidates(3):
		var def: SpeciesDef = entry.def
		var row := Label.new()
		row.text = "  ·  %s  %%%d" % [def.name_text(), int(entry.progress * 100.0)]
		row.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		row.add_theme_font_size_override("font_size", 13)
		row.tooltip_text = "%s\n%s" % [
			def.description_text(), ", ".join(def.requirement_lines())
		]
		_wildlife_list.add_child(row)


func _refresh_pablo() -> void:
	_pablo_label.text = tr("PABLO_" + Pablo.Mood.keys()[_state.pablo.mood])


func _on_species_settled(id: String, _axial: Vector2i) -> void:
	var def: SpeciesDef = Bestiary.get_species(id)
	_tooltip.text = tr("UI_SETTLED").format([def.name_text()], "{0}")
	_refresh_wildlife()


# ------------------------------------------------------------------ build bar

func _populate_build_bar() -> void:
	for child in _build_bar.get_children():
		child.queue_free()

	# Show everything unlocked so far, not just the current phase.
	var max_tier: int = _state._max_unlocked_tier()
	for tier in range(1, max_tier + 1):
		for def in Catalog.by_tier(tier):
			_build_bar.add_child(_make_button(def))


func _make_button(def: BuildingDef) -> Button:
	var b := Button.new()
	b.text = "%s\n%d" % [def.name_text(), def.cost]
	b.custom_minimum_size = Vector2(112, 56)
	b.toggle_mode = true
	b.pressed.connect(func() -> void:
		for other in _build_bar.get_children():
			if other is Button and other != b:
				other.button_pressed = false
		_view.select_building(def if b.button_pressed else null)
		_tooltip.text = def.description_text() if b.button_pressed else ""
	)
	return b


# --------------------------------------------------------------------- events

func _on_leaves_changed(amount: int) -> void:
	_leaf_label.text = "%s  %d" % [tr("UI_LEAVES"), amount]


func _refresh_objective() -> void:
	_objective_label.text = _state.objective_text()
	_launch_button.visible = _state.ready_to_launch()
	if _state.phase == GameState.Phase.WILDLIFE:
		_refresh_wildlife()


func _on_phase_changed(_phase: int) -> void:
	_populate_build_bar()
	_refresh_objective()


func _on_build_attempted(_axial: Vector2i, ok: bool) -> void:
	if not ok:
		_tooltip.text = tr("UI_CANNOT_BUILD")


func _on_launch_pressed() -> void:
	_state.launch()


func _on_run_finished(summary: Dictionary) -> void:
	_build_bar.hide()
	_launch_button.hide()
	_tooltip.text = ""
	_objective_label.text = tr("OBJ_SUMMARY").format([
		int(summary.restored * 100.0), summary.species.size()
	])
