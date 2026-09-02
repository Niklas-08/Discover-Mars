extends Control
## Gestrichelte Trennlinie unter der Kopfzeile des Missionspanels.

@export var line_alpha: float = 1.0:
	set(value):
		line_alpha = value
		queue_redraw()

@export var dash_length: float = 4.0
@export var gap_length: float = 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 1.0)


func _draw() -> void:
	if size.x <= 0.0:
		return
	var color := MissionStyle.AMBER_FAINT
	color.a *= line_alpha
	var x := 0.0
	var y := size.y * 0.5
	while x < size.x:
		var x_end: float = minf(x + dash_length, size.x)
		draw_line(Vector2(x, y), Vector2(x_end, y), color, 1.0)
		x = x_end + gap_length
