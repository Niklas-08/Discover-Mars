@tool
class_name ChamferStyleBox
extends StyleBox
## Panelhintergrund mit diagonal abgeschnittenen Ecken.
##
## Oben links und unten rechts ist die Ecke deutlich schraeg abgeschnitten,
## oben rechts und unten links nur leicht. Das ergibt die gerichtete,
## technische Form der Oberflaeche statt eines einfachen Rechtecks. Der
## passende Rahmen (Linien, Diagonal-Akzente) kommt aus mission_panel_frame.gd,
## der dieselbe Form ueber chamfer_polygon() abfragt.

@export var bg_color: Color = Color(0.02, 0.05, 0.08, 0.62):
	set(v):
		bg_color = v
		emit_changed()
## Groesse der grossen Schraegen (oben links / unten rechts) in Pixeln.
@export var chamfer: float = 16.0:
	set(v):
		chamfer = v
		emit_changed()
## Faktor fuer die kleinen Schraegen (oben rechts / unten links).
@export var small_factor: float = 0.4:
	set(v):
		small_factor = v
		emit_changed()
## Optionale Umrisslinie (z. B. fuer Tastenkappen). Alpha 0 = keine.
@export var border_color: Color = Color(0, 0, 0, 0):
	set(v):
		border_color = v
		emit_changed()
@export var border_width: float = 1.0:
	set(v):
		border_width = v
		emit_changed()


## Umriss der Form in einem Rechteck (im Uhrzeigersinn).
static func chamfer_polygon(rect: Rect2, big: float, small_f: float = 0.4) -> PackedVector2Array:
	var b := minf(big, minf(rect.size.x, rect.size.y) * 0.35)
	var s := b * small_f
	var l := rect.position.x
	var t := rect.position.y
	var r := rect.end.x
	var bo := rect.end.y
	return PackedVector2Array([
		Vector2(l + b, t), Vector2(r - s, t), Vector2(r, t + s),
		Vector2(r, bo - b), Vector2(r - b, bo), Vector2(l + s, bo),
		Vector2(l, bo - s), Vector2(l, t + b),
	])


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var poly := chamfer_polygon(rect, chamfer, small_factor)
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, poly, PackedColorArray([bg_color]))
	if border_color.a > 0.0 and border_width > 0.0:
		var closed := poly.duplicate()
		closed.append(poly[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, closed, PackedColorArray([border_color]), border_width, true)
