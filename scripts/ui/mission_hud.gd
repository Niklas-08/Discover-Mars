extends CanvasLayer
## Missionsuebersicht oben rechts.
##
## Baut das Panel vollstaendig im Code auf. Grund: Die Zielzeilen entstehen
## ohnehin erst zur Laufzeit aus der geladenen Mission, und die Gestaltung ist
## prozedural (Eckwinkel, Scanlines, Tweens). Eine .tscn haette hier nur einen
## leeren Rumpf enthalten.
##
## Das HUD liest niemals Weltknoten aus -- es reagiert ausschliesslich auf die
## Signale des MissionManagers.

## Einblendzeit des Panels beim Missionsstart.
const SLIDE_DURATION := 0.55
## Wie lange die Abschlussmeldung stehen bleibt, bevor das Panel ausblendet.
const COMPLETE_HOLD := 4.5

var _root: Control = null
var _panel: PanelContainer = null
var _frame: Control = null
var _eyebrow: Label = null
var _title: Label = null
var _objective_box: VBoxContainer = null
var _banner: Label = null

## objective_id -> MissionObjectiveRow
var _rows: Dictionary = {}
var _slide_tween: Tween = null


func _ready() -> void:
	add_to_group(&"mission_hud")
	_build_ui()
	_root.modulate.a = 0.0
	_root.visible = false

	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.objective_activated.connect(_on_objective_activated)
	MissionManager.objective_completed.connect(_on_objective_completed)
	MissionManager.objective_progress_changed.connect(_on_objective_progress_changed)

	# Laeuft bereits eine Mission (z. B. nach einem Editor-Reload), sofort zeigen.
	if MissionManager.active_mission != null:
		_on_mission_started(MissionManager.active_mission)


# --- Aufbau ---------------------------------------------------------------

func _build_ui() -> void:
	# Zuerst und damit unter dem Panel: der Bildschirmmarker darf die
	# Aufgabenliste nie ueberdecken.
	var waypoint_layer := Control.new()
	waypoint_layer.name = "WaypointLayer"
	waypoint_layer.set_script(load("res://scripts/ui/waypoint_marker.gd"))
	waypoint_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(waypoint_layer)

	_root = Control.new()
	_root.name = "TrackerRoot"
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Nach rechts und unten wachsen lassen, verankert an der rechten Oberkante.
	_root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.grow_vertical = Control.GROW_DIRECTION_END
	_root.offset_left = -(MissionStyle.PANEL_WIDTH + MissionStyle.PANEL_MARGIN)
	_root.offset_right = -MissionStyle.PANEL_MARGIN
	_root.offset_top = MissionStyle.PANEL_MARGIN
	_root.offset_bottom = MissionStyle.PANEL_MARGIN
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", MissionStyle.panel_stylebox())
	# set_anchors_and_offsets_preset, nicht set_anchors_preset: letzteres
	# behaelt das aktuelle (noch leere) Rechteck bei und liefert Groesse 0.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	column.add_child(_build_header())

	var divider := Control.new()
	divider.name = "Divider"
	divider.set_script(load("res://scripts/ui/mission_divider.gd"))
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(divider)

	_objective_box = VBoxContainer.new()
	_objective_box.name = "Objectives"
	_objective_box.add_theme_constant_override("separation", MissionStyle.ROW_SPACING)
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_objective_box)

	_banner = Label.new()
	_banner.name = "Banner"
	_banner.add_theme_font_override("font", MissionStyle.header_font())
	_banner.add_theme_font_size_override("font_size", MissionStyle.FONT_SIZE_BANNER)
	_banner.add_theme_color_override("font_color", MissionStyle.DONE_GREEN)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	column.add_child(_banner)

	# Rahmen zuletzt und ueber dem Panel, damit er nichts vom Layout verdeckt.
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.set_script(load("res://scripts/ui/mission_panel_frame.gd"))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge := TextureRect.new()
	badge.name = "Badge"
	badge.texture = MissionStyle.icon("mission_flag")
	badge.custom_minimum_size = Vector2(22.0, 22.0)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.modulate = MissionStyle.AMBER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(badge)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 0)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_eyebrow = Label.new()
	_eyebrow.name = "Eyebrow"
	_eyebrow.add_theme_font_override("font", MissionStyle.header_font())
	_eyebrow.add_theme_font_size_override("font_size", MissionStyle.FONT_SIZE_EYEBROW)
	_eyebrow.add_theme_color_override("font_color", MissionStyle.AMBER)
	_eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_eyebrow)

	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_override("font", MissionStyle.header_font())
	_title.add_theme_font_size_override("font_size", MissionStyle.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", MissionStyle.TEXT_BRIGHT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_title)

	header.add_child(text_column)
	return header


# --- Missions-Signale -----------------------------------------------------

func _on_mission_started(mission: Mission) -> void:
	_clear_rows()
	_banner.visible = false

	_eyebrow.text = "%s  \u00B7  AKTIVE MISSION" % mission.codename.to_upper()
	_title.text = mission.title

	for objective in mission.objectives:
		if objective == null:
			continue
		var row := MissionObjectiveRow.new()
		_objective_box.add_child(row)
		row.setup(objective)
		_rows[objective.id] = row

	_slide_in()


func _on_objective_activated(objective: MissionObjective) -> void:
	_sync_row_states()
	var row: MissionObjectiveRow = _rows.get(objective.id)
	if row != null:
		row.set_state(MissionManager.State.ACTIVE)


func _on_objective_completed(objective: MissionObjective) -> void:
	var row: MissionObjectiveRow = _rows.get(objective.id)
	if row != null:
		row.set_state(MissionManager.State.DONE)
	_pulse_frame()
	_sync_row_states()


func _on_objective_progress_changed(objective: MissionObjective, current: int, _required: int) -> void:
	var row: MissionObjectiveRow = _rows.get(objective.id)
	if row != null:
		row.set_progress(current)


func _on_mission_completed(mission: Mission) -> void:
	_sync_row_states()
	_banner.text = "MISSION ABGESCHLOSSEN"
	_banner.visible = true
	_pulse_frame()

	if not mission.debrief.is_empty():
		print_rich("[color=#6FBF7F]%s abgeschlossen.[/color] %s" % [mission.codename, mission.debrief])

	await get_tree().create_timer(COMPLETE_HOLD).timeout
	_slide_out()


# --- Zustandsabgleich -----------------------------------------------------

## Alle Zeilen auf den Zustand im MissionManager bringen. Guenstiger als
## Einzelfaelle zu verfolgen und kann nicht auseinanderlaufen.
func _sync_row_states() -> void:
	for objective_id: StringName in _rows:
		var row: MissionObjectiveRow = _rows[objective_id]
		if row != null and is_instance_valid(row):
			row.set_state(MissionManager.get_objective_state(objective_id))


func _clear_rows() -> void:
	for child in _objective_box.get_children():
		child.queue_free()
	_rows.clear()


# --- Animation ------------------------------------------------------------

func _slide_in() -> void:
	_root.visible = true
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	var end_x := -(MissionStyle.PANEL_WIDTH + MissionStyle.PANEL_MARGIN)
	var start_x := end_x + 60.0
	_root.offset_left = start_x
	_root.offset_right = start_x + MissionStyle.PANEL_WIDTH
	_root.modulate.a = 0.0

	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.tween_property(_root, "modulate:a", 1.0, SLIDE_DURATION * 0.7)
	_slide_tween.tween_property(_root, "offset_left", end_x, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(_root, "offset_right", end_x + MissionStyle.PANEL_WIDTH, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _slide_out() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.tween_property(_root, "modulate:a", 0.0, SLIDE_DURATION * 0.8)
	_slide_tween.tween_property(_root, "offset_left", _root.offset_left + 60.0, SLIDE_DURATION)
	_slide_tween.tween_property(_root, "offset_right", _root.offset_right + 60.0, SLIDE_DURATION)
	_slide_tween.chain().tween_callback(func() -> void: _root.visible = false)


## Kurzes Aufleuchten des Rahmens, wenn sich etwas Wichtiges aendert.
func _pulse_frame() -> void:
	if _frame == null or not is_instance_valid(_frame):
		return
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void: _frame.highlight = value,
		1.0, 0.0, 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
