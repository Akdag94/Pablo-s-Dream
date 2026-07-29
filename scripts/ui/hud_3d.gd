extends Control

## Touch-first HUD for the 3D scene.
##
## Differences from the desktop prototype that matter on a phone: every target
## is at least 44pt, the build bar scrolls horizontally instead of wrapping,
## and placement is a two-step confirm so a fat finger never spends leaves by
## accident. Layout respects the notch and the home indicator.

## Apple's minimum comfortable touch target, in points.
const MIN_TOUCH := 44
const BUILD_BUTTON := Vector2(96, 76)

@export var controller_path: NodePath

var _controller: Node3D
var _state: GameState

var _leaf_label: Label
var _objective_label: Label
var _pablo_label: Label
var _tooltip: Label
var _build_strip: HBoxContainer
var _build_scroll: ScrollContainer
var _confirm_bar: HBoxContainer
var _confirm_button: Button
var _cancel_button: Button
var _launch_button: Button
var _wildlife_list: VBoxContainer

var _safe := Rect2i()


func _ready() -> void:
	_controller = get_node(controller_path)
	_state = _controller.state

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_measure_safe_area()
	_build_top()
	_build_bottom()
	_build_wildlife()

	_state.leaves_changed.connect(func(n): _leaf_label.text = "%s  %d" % [tr("UI_LEAVES"), n])
	_state.phase_changed.connect(func(_p): Audio.play("phase"); _populate_build_strip(); _refresh())
	_state.objective_updated.connect(_refresh)
	_state.run_finished.connect(_on_finished)
	_state.wildlife.species_settled.connect(_on_settled)
	_state.wildlife.species_lost.connect(func(_id): _refresh_wildlife())
	_state.pablo.mood_changed.connect(func(_m): _refresh_pablo())

	_controller.selection_changed.connect(_on_selection_changed)
	_controller.placement_result.connect(_on_placement_result)

	get_viewport().size_changed.connect(_on_viewport_resized)

	_populate_build_strip()
	_refresh()
	_refresh_wildlife()
	_refresh_pablo()


## Keep UI clear of the notch, the status bar and the home indicator.
func _measure_safe_area() -> void:
	var window := DisplayServer.window_get_size()
	var area := DisplayServer.get_display_safe_area()
	if area.size.x <= 0 or area.size.y <= 0:
		_safe = Rect2i(Vector2i.ZERO, window)
	else:
		_safe = area


func _on_viewport_resized() -> void:
	_measure_safe_area()
	_apply_insets()


func _inset_left() -> int:
	return maxi(_safe.position.x, 16)


func _inset_top() -> int:
	return maxi(_safe.position.y, 16)


func _inset_bottom() -> int:
	var window := DisplayServer.window_get_size()
	return maxi(window.y - (_safe.position.y + _safe.size.y), 16)


# --------------------------------------------------------------------- layout

func _build_top() -> void:
	var row := HBoxContainer.new()
	row.name = "TopRow"
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_leaf_label = Label.new()
	_leaf_label.add_theme_font_size_override("font_size", 24)
	row.add_child(_leaf_label)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_objective_label)


func _build_bottom() -> void:
	var column = VBoxContainer.new()
	column.name = "BottomColumn"
	column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	_tooltip = Label.new()
	_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip.add_theme_font_size_override("font_size", 16)
	column.add_child(_tooltip)

	# Confirm bar sits above the build strip so it never covers the map.
	_confirm_bar = HBoxContainer.new()
	_confirm_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_bar.add_theme_constant_override("separation", 12)
	_confirm_bar.visible = false
	column.add_child(_confirm_bar)

	_cancel_button = _make_action_button(tr("UI_CANCEL"), func(): _cancel())
	_confirm_bar.add_child(_cancel_button)

	_confirm_button = _make_action_button(tr("UI_CONFIRM"), func():
		_controller.confirm_placement())
	_confirm_bar.add_child(_confirm_button)

	_launch_button = _make_action_button(tr("UI_LAUNCH"), func():
		Audio.play("launch")
		_state.launch())
	_launch_button.visible = false
	column.add_child(_launch_button)

	_build_scroll = ScrollContainer.new()
	_build_scroll.custom_minimum_size = Vector2(0, BUILD_BUTTON.y + 12)
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_build_scroll)

	_build_strip = HBoxContainer.new()
	_build_strip.add_theme_constant_override("separation", 8)
	_build_scroll.add_child(_build_strip)

	_apply_insets()


func _make_action_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, MIN_TOUCH + 8)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	return b


func _build_wildlife() -> void:
	var panel := PanelContainer.new()
	panel.name = "WildlifePanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(panel)

	_wildlife_list = VBoxContainer.new()
	_wildlife_list.add_theme_constant_override("separation", 4)
	panel.add_child(_wildlife_list)

	_pablo_label = Label.new()
	_pablo_label.name = "PabloLabel"
	_pablo_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pablo_label.add_theme_font_size_override("font_size", 16)
	add_child(_pablo_label)


## Push every anchored element in past the safe area.
func _apply_insets() -> void:
	var left := _inset_left()
	var top := _inset_top()
	var bottom := _inset_bottom()

	var row := get_node_or_null("TopRow")
	if row:
		row.offset_left = left
		row.offset_top = top
		row.offset_right = -left

	var column = get_node_or_null("BottomColumn")
	if column:
		column.offset_left = left
		column.offset_right = -left
		column.offset_bottom = -bottom
		column.offset_top = -(BUILD_BUTTON.y + MIN_TOUCH + 110)

	var panel := get_node_or_null("WildlifePanel")
	if panel:
		panel.offset_left = -280
		panel.offset_right = -left
		panel.offset_top = top + 56

	var pablo := get_node_or_null("PabloLabel")
	if pablo:
		pablo.offset_left = left
		pablo.offset_top = -(bottom + BUILD_BUTTON.y + MIN_TOUCH + 140)


# ----------------------------------------------------------------- build strip

func _populate_build_strip() -> void:
	for child in _build_strip.get_children():
		child.queue_free()

	var max_tier: int = _state._max_unlocked_tier()
	for tier in range(1, max_tier + 1):
		for def in Catalog.by_tier(tier):
			_build_strip.add_child(_make_build_button(def))


func _make_build_button(def: BuildingDef) -> Button:
	var b := Button.new()
	b.text = "%s\n%d" % [def.name_text(), def.cost]
	b.custom_minimum_size = BUILD_BUTTON
	b.toggle_mode = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void:
		for other in _build_strip.get_children():
			if other is Button and other != b:
				other.button_pressed = false
		var chosen: BuildingDef = def if b.button_pressed else null
		Audio.play("tool" if b.button_pressed else "cancel")
		_controller.select_building(chosen)
		_tooltip.text = def.description_text() if b.button_pressed else ""
		_refresh_confirm()
	)
	return b


func _cancel() -> void:
	Audio.play("cancel")
	_controller.select_building(null)
	for child in _build_strip.get_children():
		if child is Button:
			child.button_pressed = false
	_tooltip.text = ""
	_refresh_confirm()


# --------------------------------------------------------------------- events

func _on_selection_changed(_axial: Vector2i, _valid: bool) -> void:
	_refresh_confirm()


func _on_placement_result(ok: bool) -> void:
	if not ok:
		_tooltip.text = tr("UI_CANNOT_BUILD")
	_refresh_confirm()


func _refresh_confirm() -> void:
	var can: bool = _controller.can_confirm()
	_confirm_bar.visible = _controller.selected_def != null
	_confirm_button.disabled = not can


func _refresh() -> void:
	_objective_label.text = _state.objective_text()
	_launch_button.visible = _state.ready_to_launch()
	if _state.phase == GameState.Phase.WILDLIFE:
		_refresh_wildlife()


func _refresh_wildlife() -> void:
	for child in _wildlife_list.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "%s  %d / %d" % [
		tr("UI_WILDLIFE"), _state.wildlife.count(), _state.level.required_species]
	heading.add_theme_font_size_override("font_size", 17)
	_wildlife_list.add_child(heading)

	for id in _state.wildlife.settled:
		var def: SpeciesDef = Bestiary.get_species(id)
		var row := Label.new()
		row.text = "  ✓  %s" % def.name_text()
		row.add_theme_color_override("font_color", def.color)
		row.add_theme_font_size_override("font_size", 15)
		_wildlife_list.add_child(row)

	for entry in _state.wildlife.nearest_candidates(3):
		var def: SpeciesDef = entry.def
		var row := Label.new()
		row.text = "  ·  %s  %%%d" % [def.name_text(), int(entry.progress * 100.0)]
		row.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		row.add_theme_font_size_override("font_size", 14)
		_wildlife_list.add_child(row)


func _refresh_pablo() -> void:
	_pablo_label.text = tr("PABLO_" + Pablo.Mood.keys()[_state.pablo.mood])


func _on_settled(id: String, _axial: Vector2i) -> void:
	Audio.play("species")
	var def: SpeciesDef = Bestiary.get_species(id)
	_tooltip.text = tr("UI_SETTLED").format([def.name_text()], "{0}")
	_refresh_wildlife()


func _on_finished(summary: Dictionary) -> void:
	_build_scroll.hide()
	_confirm_bar.hide()
	_launch_button.hide()
	_tooltip.text = ""
	_objective_label.text = tr("OBJ_SUMMARY").format([
		int(summary.restored * 100.0), summary.species.size()])
