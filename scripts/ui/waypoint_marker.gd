extends Control
## Bildschirmmarker fuer das aktive Missionsziel.
##
## Zeigt eine Raute mit Entfernung, solange das Ziel im Bild ist. Sonst wird
## der Marker an den Bildschirmrand geklemmt und durch einen Richtungspfeil
## ersetzt.
##
## Die Kamera wird bewusst ueber get_viewport().get_camera_3d() bestimmt und
## nicht fest verdrahtet: Beim Einsteigen macht rover.gd die DriverCamera
## aktuell, damit folgt der Marker dem Kamerawechsel ohne Zusatzlogik.

## Abstand des geklemmten Markers vom Bildschirmrand.
@export var edge_padding: float = 72.0
## Kantenlaenge des Richtungspfeils.
@export var arrow_size: float = 17.0
## Groesse der Zielraute in Pixeln.
@export var diamond_size: float = 34.0
## Ausblenden, wenn das Ziel naeher als dieser Abstand ist. Vermeidet, dass
## der Marker direkt am Ziel noch im Bild steht und die Sicht verstellt.
@export var hide_below_distance: float = 7.0

var _tracked: MissionObjective = null
var _waypoint: Node3D = null

var _diamond: TextureRect = null
var _distance_label: Label = null
var _arrow: Control = null

var _pulse_time: float = 0.0
var _arrow_angle: float = 0.0
var _arrow_alpha: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_set_visible(false)

	MissionManager.tracked_objective_changed.connect(_on_tracked_changed)
	MissionManager.mission_completed.connect(func(_m: Mission) -> void: _on_tracked_changed(null))

	if MissionManager.active_mission != null:
		_on_tracked_changed(MissionManager.get_active_objective())


func _build_ui() -> void:
	_diamond = TextureRect.new()
	_diamond.name = "Diamond"
	_diamond.texture = MissionStyle.icon("waypoint_diamond")
	_diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_diamond.size = Vector2(diamond_size, diamond_size)
	_diamond.pivot_offset = Vector2(diamond_size, diamond_size) * 0.5
	_diamond.modulate = MissionStyle.WAYPOINT
	_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_diamond)

	# Der Pfeil wird gezeichnet statt rotiert: eine rotierte Textur franst an
	# den Kanten aus, ein Polygon bleibt bei jedem Winkel sauber.
	_arrow = Control.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)

	_distance_label = Label.new()
	_distance_label.name = "Distance"
	_distance_label.add_theme_font_override("font", MissionStyle.header_font())
	_distance_label.add_theme_font_size_override("font_size", 14)
	_distance_label.add_theme_color_override("font_color", MissionStyle.WAYPOINT)
	_distance_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	_distance_label.add_theme_constant_override("outline_size", 5)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_distance_label)


# --- Zielwechsel ----------------------------------------------------------

func _on_tracked_changed(objective: MissionObjective) -> void:
	_tracked = objective
	_waypoint = null
	if objective == null:
		_set_visible(false)
		set_process(false)
		return
	_resolve_waypoint()
	set_process(true)


## Sucht den MissionWaypoint-Knoten zum aktiven Ziel.
func _resolve_waypoint() -> void:
	if _tracked == null:
		return
	for node in get_tree().get_nodes_in_group(&"mission_waypoint"):
		if node.get("objective_id") == _tracked.id:
			_waypoint = node
			return
	_waypoint = null


# --- Darstellung ----------------------------------------------------------

func _process(delta: float) -> void:
	if _tracked == null:
		_set_visible(false)
		return

	if _waypoint == null or not is_instance_valid(_waypoint):
		# Wegpunkte werden verzoegert aufgebaut; erneut versuchen.
		_resolve_waypoint()
		if _waypoint == null:
			_set_visible(false)
			return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_set_visible(false)
		return

	var target: Vector3 = _waypoint.get_target_position()
	var distance := camera.global_position.distance_to(target)
	if hide_below_distance > 0.0 and distance < hide_below_distance:
		_set_visible(false)
		return

	_pulse_time += delta

	# Bewusst die Viewport-Groesse statt der eigenen: Die Layout-Groesse eines
	# Controls unter einem CanvasLayer ist im ersten Frame noch 0, der Viewport
	# ist sofort gueltig und in diesem Vollbild-Control deckungsgleich.
	var view_size := get_viewport_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		_set_visible(false)
		return

	# Auf sehr kleinen Fenstern darf der Randabstand die Flaeche nicht auffressen.
	var padding: float = minf(edge_padding, minf(view_size.x, view_size.y) * 0.25)
	var center := view_size * 0.5

	var behind := camera.is_position_behind(target)
	var screen_position := camera.unproject_position(target)
	var bounds := Rect2(Vector2(padding, padding), view_size - Vector2(padding, padding) * 2.0)

	# Hinter der Kamera liefert unproject_position gespiegelte Koordinaten.
	if behind:
		screen_position = center - (screen_position - center)

	var off_screen := behind or not bounds.has_point(screen_position)
	_set_visible(true)

	if off_screen:
		_show_edge_arrow(screen_position, bounds, center, distance)
	else:
		_show_on_screen(screen_position, distance)


func _show_on_screen(screen_position: Vector2, distance: float) -> void:
	_arrow_alpha = 0.0
	_arrow.visible = false
	_diamond.visible = true

	var pulse := 1.0 + sin(_pulse_time * 3.2) * 0.08
	var draw_size := diamond_size * pulse
	_diamond.size = Vector2(draw_size, draw_size)
	_diamond.position = screen_position - Vector2(draw_size, draw_size) * 0.5

	var alpha := 0.75 + 0.25 * (0.5 + 0.5 * sin(_pulse_time * 3.2))
	var color := MissionStyle.WAYPOINT
	color.a = alpha
	_diamond.modulate = color

	_place_distance(screen_position + Vector2(0.0, draw_size * 0.5 + 6.0), distance)


func _show_edge_arrow(screen_position: Vector2, bounds: Rect2, center: Vector2, distance: float) -> void:
	_diamond.visible = false
	_arrow.visible = true

	var direction := screen_position - center
	if direction.length_squared() < 0.001:
		direction = Vector2.UP

	var clamped := Vector2(
		clampf(screen_position.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(screen_position.y, bounds.position.y, bounds.position.y + bounds.size.y)
	)

	_arrow_angle = direction.angle()
	_arrow_alpha = 1.0
	_arrow.position = clamped
	_arrow.queue_redraw()

	# Beschriftung zur Bildmitte hin versetzen, damit sie nicht abgeschnitten wird.
	_place_distance(clamped - direction.normalized() * 22.0, distance)


func _place_distance(anchor: Vector2, distance: float) -> void:
	_distance_label.visible = true
	_distance_label.text = MissionStyle.format_distance(distance)
	_distance_label.reset_size()

	var view_size := get_viewport_rect().size
	var pos := anchor - Vector2(_distance_label.size.x * 0.5, 0.0)
	# Am Bildrand wuerde die zentrierte Beschriftung sonst abgeschnitten.
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view_size.x - _distance_label.size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, view_size.y - _distance_label.size.y - 4.0))
	_distance_label.position = pos


func _draw_arrow() -> void:
	if _arrow_alpha <= 0.0:
		return
	var color := MissionStyle.WAYPOINT
	color.a = _arrow_alpha * (0.8 + 0.2 * sin(_pulse_time * 3.2))

	# Gleichschenkliges Dreieck, das in Richtung des Ziels zeigt.
	var tip := Vector2(arrow_size, 0.0).rotated(_arrow_angle)
	var left := Vector2(-arrow_size * 0.65, -arrow_size * 0.72).rotated(_arrow_angle)
	var right := Vector2(-arrow_size * 0.65, arrow_size * 0.72).rotated(_arrow_angle)
	_arrow.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)

	var outline := Color(0.0, 0.0, 0.0, 0.55 * _arrow_alpha)
	_arrow.draw_polyline(PackedVector2Array([tip, left, right, tip]), outline, 1.5)


func _set_visible(value: bool) -> void:
	if _diamond:
		_diamond.visible = value and _diamond.visible
	if _arrow:
		_arrow.visible = value and _arrow.visible
	if _distance_label:
		_distance_label.visible = value
	if not value:
		if _diamond:
			_diamond.visible = false
		if _arrow:
			_arrow.visible = false
