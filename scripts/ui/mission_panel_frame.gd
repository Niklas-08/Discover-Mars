extends Control
## Zeichnet den Rahmen eines Panels mit diagonal abgeschnittenen Ecken.
##
## Bewusst prozedural statt als StyleBox: Akzentlinien, Diagonal-Streifen und
## Scanlines sollen animierbar sein (Einblenden, Puls beim Zielwechsel). Der
## Fuellhintergrund kommt aus der ChamferStyleBox des PanelContainers darunter;
## dieser Rahmen liest deren Schraege und folgt exakt derselben Form.

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
## Diagonale Zierstreifen oben rechts.
@export var draw_slashes: bool = true


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


## Schraege der Panelform (aus der ChamferStyleBox des Elternteils).
func _shape() -> Vector2:
	var parent_control := get_parent() as Control
	if parent_control:
		var sb := parent_control.get_theme_stylebox(&"panel")
		if sb is ChamferStyleBox:
			return Vector2(sb.chamfer, sb.small_factor)
	return Vector2(MissionStyle.CORNER_BRACKET + 4.0, 0.4)


func _draw() -> void:
	var rect := _panel_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var glow := clampf(highlight, 0.0, 1.0)
	var border_color := MissionStyle.ACCENT_DIM
	var accent := MissionStyle.ACCENT
	if glow > 0.0:
		border_color = border_color.lerp(MissionStyle.FLASH, glow * 0.8)
		accent = accent.lerp(MissionStyle.FLASH, glow * 0.8)
	border_color.a *= frame_alpha
	accent.a *= frame_alpha

	var shape := _shape()
	var poly := ChamferStyleBox.chamfer_polygon(rect, shape.x, shape.y)
	var b: float = poly[0].x - rect.position.x   # tatsaechliche grosse Schraege

	if draw_scanlines:
		_draw_scanlines(rect, b, b * shape.y)

	# Duenner Umriss entlang der ganzen Form.
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, border_color, 1.0, true)

	# Kraeftige Akzente auf den beiden grossen Schraegen, jeweils ein Stueck
	# in die angrenzenden Kanten verlaengert -- wie gerichtete Eckwinkel.
	var arm := minf(b * 1.6, rect.size.x * 0.25)
	var l := rect.position.x
	var t := rect.position.y
	var r := rect.end.x
	var bo := rect.end.y
	draw_polyline(PackedVector2Array([Vector2(l, t + b + arm * 0.5), Vector2(l, t + b), Vector2(l + b, t), Vector2(l + b + arm, t)]), accent, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(r, bo - b - arm * 0.5), Vector2(r, bo - b), Vector2(r - b, bo), Vector2(r - b - arm, bo)]), accent, 2.0, true)

	# Diagonale Zierstreifen an der Oberkante rechts.
	if draw_slashes and rect.size.x > 160.0:
		var slash_color := accent
		slash_color.a *= 0.7
		var x0 := r - b * shape.y - 18.0
		for i in 4:
			var x := x0 - i * 7.0
			draw_line(Vector2(x, t + 2.0), Vector2(x - 6.0, t + 9.0), slash_color, 2.0, true)


## Feine Bildschirmzeilen -- auf die abgeschraegte Form zugeschnitten.
func _draw_scanlines(rect: Rect2, big: float, small: float) -> void:
	var color := Color(MissionStyle.ACCENT, 0.035 * frame_alpha)
	var y := rect.position.y + scanline_spacing
	var y_limit := rect.end.y
	while y < y_limit:
		var dy_top := y - rect.position.y
		var dy_bot := rect.end.y - y
		# Linker Rand: oben grosse Schraege, unten kleine; rechter Rand umgekehrt.
		var x_start := rect.position.x + 1.0 + maxf(0.0, maxf(big - dy_top, small - dy_bot))
		var x_end := rect.end.x - 1.0 - maxf(0.0, maxf(small - dy_top, big - dy_bot))
		if x_end > x_start:
			draw_line(Vector2(x_start, y), Vector2(x_end, y), color, 1.0)
		y += scanline_spacing
