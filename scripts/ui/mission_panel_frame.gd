extends Control
## Zeichnet den Rahmen des Missionspanels.
##
## Bewusst prozedural statt als StyleBox: Eckwinkel, Akzentbalken und
## Scanlines sollen animierbar sein (Einblenden, Puls beim Zielwechsel), und
## eine StyleBox kann keine Eckwinkel zeichnen. Der Fuellhintergrund kommt
## weiterhin aus der StyleBox des PanelContainer darunter.

## Deckkraft des gesamten Rahmens. Wird beim Einblenden getweent.
@export var frame_alpha: float = 1.0:
	set(value):
		frame_alpha = value
		queue_redraw()

## Zusaetzliches Aufleuchten (0..1), z. B. wenn ein Ziel erfuellt wurde.
@export var highlight: float = 0.0:
	set(value):
		highlight = value
		queue_redraw()

@export var draw_scanlines: bool = true
## Abstand der Scanlines in Pixeln.
@export var scanline_spacing: float = 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Rechteck des Panels in lokalen Koordinaten.
##
## Ein PanelContainer rueckt alle Kinder um seine content_margins ein. Ohne
## diese Korrektur wuerde der Rahmen innerhalb der Polsterung landen statt auf
## der Panelkante. -position verschiebt zurueck auf die echte Panelecke.
func _panel_rect() -> Rect2:
	var parent_control := get_parent() as Control
	if parent_control == null:
		return Rect2(Vector2.ZERO, size)
	return Rect2(-position, parent_control.size)


func _draw() -> void:
	var rect := _panel_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var glow := clampf(highlight, 0.0, 1.0)
	var border_color := MissionStyle.AMBER_DIM
	var bracket_color := MissionStyle.AMBER
	if glow > 0.0:
		border_color = border_color.lerp(MissionStyle.FLASH, glow * 0.8)
		bracket_color = bracket_color.lerp(MissionStyle.FLASH, glow * 0.8)
	border_color.a *= frame_alpha
	bracket_color.a *= frame_alpha

	if draw_scanlines:
		_draw_scanlines(rect)

	# Duenner Grundrahmen.
	draw_rect(rect, border_color, false, 1.0)

	# Akzentbalken an der linken Kante.
	var bar_color := bracket_color
	bar_color.a *= 0.9
	draw_rect(Rect2(rect.position.x, rect.position.y, 3.0, rect.size.y), bar_color, true)

	_draw_corner_brackets(rect, bracket_color)


## Klassische Sci-Fi-Eckwinkel an allen vier Ecken.
func _draw_corner_brackets(rect: Rect2, color: Color) -> void:
	var b: float = minf(MissionStyle.CORNER_BRACKET, minf(rect.size.x, rect.size.y) * 0.4)
	var w := 2.0
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.position.x + rect.size.x
	var bottom := rect.position.y + rect.size.y

	# Oben links
	draw_line(Vector2(left, top), Vector2(left + b, top), color, w)
	draw_line(Vector2(left, top), Vector2(left, top + b), color, w)
	# Oben rechts
	draw_line(Vector2(right, top), Vector2(right - b, top), color, w)
	draw_line(Vector2(right, top), Vector2(right, top + b), color, w)
	# Unten links
	draw_line(Vector2(left, bottom), Vector2(left + b, bottom), color, w)
	draw_line(Vector2(left, bottom), Vector2(left, bottom - b), color, w)
	# Unten rechts
	draw_line(Vector2(right, bottom), Vector2(right - b, bottom), color, w)
	draw_line(Vector2(right, bottom), Vector2(right, bottom - b), color, w)


## Feine Bildschirmzeilen -- lassen die Flaeche wie ein Monitor wirken.
func _draw_scanlines(rect: Rect2) -> void:
	var color := Color(1.0, 1.0, 1.0, 0.03 * frame_alpha)
	var x_start := rect.position.x + 1.0
	var x_end := rect.position.x + rect.size.x - 1.0
	var y := rect.position.y + scanline_spacing
	var y_limit := rect.position.y + rect.size.y
	while y < y_limit:
		draw_line(Vector2(x_start, y), Vector2(x_end, y), color, 1.0)
		y += scanline_spacing
