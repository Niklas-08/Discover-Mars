extends CanvasLayer
## Untere Bildschirmleiste.
##
##   unten links  -- Tasten und was sie gerade tun (auf Deutsch). Wechselt
##                   je nach Lage: zu Fuss, im Mars Exploration Vehicle oder
##                   beim Fernsteuern von Perseverance.
##   unten rechts -- Luftdruck und Mars-Ortszeit.
##
## Beide Bloecke haben KEINEN Hintergrund. Sie werden nur von hellblauen
## Linien eingefasst, die in der Mitte waagerecht verlaufen und zu den Ecken
## hin diagonal abknicken (unten nach oben, oben gespiegelt).
##
## Luftdruck: Der mittlere Oberflaechendruck auf dem Mars liegt bei etwa
## 6 mbar (rund 600 Pa, unter 1 % des Erddrucks). Im Tagesverlauf schwankt er
## durch thermische Gezeiten um einige Prozent -- hier als sanfte Kurve ueber
## die Tageszeit des DayNightCycle nachgebildet.

const MARGIN := 26.0
const PAD := Vector2(22.0, 12.0)
const ROW_GAP := 5

## Luftdruck: Modell nach den Messungen der Wetterstation REMS auf dem Rover
## Curiosity im Gale-Krater (Haberle et al. 2014, J. Geophys. Res. Planets
## 119; Guzewich et al. 2016). Der Krater liegt tief, daher liegt der Druck
## dort ueber dem Marsmittel von ~6 mbar. Im Tagesverlauf schwankt er um rund
## 10 %: Hoechstwert am Morgen (~08 Uhr), Tiefstwert am spaeten Nachmittag
## (~16 Uhr). Ursache sind thermische Gezeiten -- eine taegliche und eine
## halbtaegliche Welle, die sich ueberlagern. Nachgebildet wird die Form der
## Messkurve, nicht die einzelne Messreihe.
const PRESSURE_MEAN := 8.3          ## mbar (= hPa), Gale-Krater
const PRESSURE_DIURNAL := 0.045     ## Anteil, taegliche Welle
const PRESSURE_DIURNAL_PEAK := 6.5  ## Uhrzeit (Mars-Stunden) des Maximums
const PRESSURE_SEMI := 0.015        ## Anteil, halbtaegliche Welle
const PRESSURE_SEMI_PEAK := 9.5     ## Uhrzeit eines der beiden Maxima

## Schwerebeschleunigung an der Marsoberflaeche (Mittelwert).
const MARS_GRAVITY := 3.71

const KEYS_ON_FOOT := [
	["W A S D", "Gehen"],
	["Shift", "Sprinten"],
	["Leertaste", "Springen"],
	["F", "Interagieren / Einsteigen"],
	["X", "Taschenlampe an / aus"],
	["R", "Perseverance fernsteuern"],
	["C", "Kamera wechseln"],
]
const KEYS_IN_MMSEV := [
	["W / S", "Gas / Bremsen, Rückwärts"],
	["A / D", "Lenken"],
	["Leertaste", "Handbremse"],
	["X", "Scheinwerfer an / aus"],
	["F", "Aussteigen"],
]
const KEYS_REMOTE := [
	["W / S", "Vorwärts / Rückwärts"],
	["A / D", "Lenken"],
	["Shift", "Schneller fahren"],
	["F", "Probe nehmen"],
	["R", "Zurück zum Astronauten"],
]

var _keys_box: Control
var _keys_list: VBoxContainer
var _status_box: Control
var _speed_value: Label
var _pressure_value: Label
var _gravity_value: Label
var _time_value: Label

var _mode: String = ""
var _player: Node = null
var _mmsev: Node = null
var _perseverance: Node = null
var _cycle: Node = null
var _sol: int = 1
var _last_tod: float = -1.0


func _ready() -> void:
	layer = 8
	_keys_box = _make_tray(true)
	_keys_list = VBoxContainer.new()
	_keys_list.add_theme_constant_override("separation", ROW_GAP)
	_keys_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_box.get_child(0).add_child(_keys_list)

	_status_box = _make_tray(false)
	var col: VBoxContainer = _status_box.get_child(0)
	_speed_value = _status_row(col, "TEMPO")[0]
	var pg := _status_row(col, "LUFTDRUCK", "SCHWERKRAFT")
	_pressure_value = pg[0]
	_gravity_value = pg[1]
	_gravity_value.text = ("%.2f m/s²" % MARS_GRAVITY).replace(".", ",")
	_time_value = _status_row(col, "ORTSZEIT (MARS)")[0]


func _process(_delta: float) -> void:
	_update_keys()
	_update_status()


# --- Tasten ---------------------------------------------------------------

func _update_keys() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
	var mode := "foot"
	if _player:
		if _player.get(&"remote_active"):
			mode = "remote"
		elif _player.get(&"in_rover"):
			mode = "mmsev"
	if mode == _mode:
		return
	_mode = mode
	for c in _keys_list.get_children():
		c.queue_free()
	var rows: Array = KEYS_REMOTE if mode == "remote" else (KEYS_IN_MMSEV if mode == "mmsev" else KEYS_ON_FOOT)
	for r in rows:
		_keys_list.add_child(_key_row(r[0], r[1]))


func _key_row(key: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cap := PanelContainer.new()
	var sb := ChamferStyleBox.new()
	sb.bg_color = Color(MissionStyle.ACCENT, 0.10)
	sb.border_color = MissionStyle.ACCENT_DIM
	sb.chamfer = 5.0
	sb.small_factor = 0.0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", sb)
	cap.custom_minimum_size = Vector2(96.0, 0.0)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := _label(key, MissionStyle.header_font(), 14, MissionStyle.ACCENT)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(k)
	row.add_child(cap)

	var d := _label(text, MissionStyle.body_font(), 15, MissionStyle.TEXT_BRIGHT)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)
	return row


# --- Luftdruck / Zeit -----------------------------------------------------

## Eine Statuszeile: Bezeichnung + Wert, optional ein zweites Paar daneben.
## Liefert die Wert-Labels.
func _status_row(col: VBoxContainer, caption: String, caption2: String = "") -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var values := []
	for cap in ([caption] if caption2.is_empty() else [caption, caption2]):
		var c := _label(cap, MissionStyle.header_font(), 13, MissionStyle.ACCENT)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if caption2.is_empty():
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
		var v := _label("--", MissionStyle.header_font(), 20, MissionStyle.TEXT_BRIGHT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if not caption2.is_empty():
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		values.append(v)
	return values


func _update_status() -> void:
	if _cycle == null or not is_instance_valid(_cycle):
		_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	var tod: float = 0.5
	var scale: float = 1.0
	if _cycle and _cycle.get(&"time_of_day") != null:
		tod = float(_cycle.get(&"time_of_day"))
		if _cycle.has_method("get_time_scale"):
			scale = _cycle.get_time_scale()
	# Neuer Sol, sobald die Tageszeit ueber Mitternacht springt.
	if _last_tod >= 0.0 and tod < _last_tod - 0.5:
		_sol += 1
	_last_tod = tod

	var minutes := int(tod * 24.0 * 60.0) % (24 * 60)
	_time_value.text = "SOL %d  ·  %02d:%02d   ×%d" % [_sol, minutes / 60, minutes % 60, roundi(scale)]

	# Luftdruck nach REMS-Modell (siehe Konstanten oben).
	var hour := tod * 24.0
	var p := PRESSURE_MEAN * (1.0
		+ PRESSURE_DIURNAL * cos(TAU * (hour - PRESSURE_DIURNAL_PEAK) / 24.0)
		+ PRESSURE_SEMI * cos(TAU * (hour - PRESSURE_SEMI_PEAK) / 12.0))
	_pressure_value.text = ("%.2f mbar" % p).replace(".", ",")

	_speed_value.text = "%d km/h" % roundi(_current_speed_kph())


## Tempo dessen, was gerade gesteuert wird: Astronaut, MMSEV oder Perseverance.
func _current_speed_kph() -> float:
	match _mode:
		"remote":
			if _perseverance == null or not is_instance_valid(_perseverance):
				_perseverance = get_tree().get_first_node_in_group(&"perseverance")
			if _perseverance and _perseverance.has_method("get_speed_kph"):
				return _perseverance.get_speed_kph()
		"mmsev":
			if _mmsev == null or not is_instance_valid(_mmsev):
				_mmsev = get_tree().get_first_node_in_group(&"rover")
			if _mmsev and _mmsev.has_method("get_speed_kph"):
				return _mmsev.get_speed_kph()
		_:
			if _player is CharacterBody3D:
				var v: Vector3 = _player.velocity
				return Vector2(v.x, v.z).length() * 3.6
	return 0.0


# --- Rahmen ---------------------------------------------------------------

## Erzeugt einen Block mit Linienrahmen in der linken oder rechten unteren Ecke.
func _make_tray(left: bool) -> Control:
	var tray := Control.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	tray.grow_horizontal = Control.GROW_DIRECTION_END if left else Control.GROW_DIRECTION_BEGIN
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(tray)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = PAD
	col.add_theme_constant_override("separation", 6)
	tray.add_child(col)
	col.resized.connect(func() -> void: _fit_tray(tray, col, left))
	tray.draw.connect(func() -> void: _draw_tray(tray))
	return tray


func _fit_tray(tray: Control, col: Control, left: bool) -> void:
	var s := col.get_combined_minimum_size() + PAD * 2.0
	if not left:
		s.x = maxf(s.x, 300.0)
	tray.size = s
	tray.position = Vector2(MARGIN, -MARGIN - s.y) if left else Vector2(-MARGIN - s.x, -MARGIN - s.y)
	if left:
		tray.offset_left = MARGIN
		tray.offset_right = MARGIN + s.x
	else:
		tray.offset_left = -MARGIN - s.x
		tray.offset_right = -MARGIN
	tray.offset_top = -MARGIN - s.y
	tray.offset_bottom = -MARGIN
	if not left:
		col.size.x = s.x - PAD.x * 2.0
	tray.queue_redraw()


## Unten: waagerecht in der Mitte, zu den Ecken diagonal nach oben.
## Oben: gespiegelt und schwaecher.
func _draw_tray(tray: Control) -> void:
	var w := tray.size.x
	var h := tray.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var d := clampf(h * 0.28, 12.0, 26.0)
	var strong := MissionStyle.ACCENT
	var faint := MissionStyle.ACCENT_DIM
	faint.a *= 0.6
	tray.draw_polyline(PackedVector2Array([Vector2(0, h - d), Vector2(d, h), Vector2(w - d, h), Vector2(w, h - d)]), strong, 2.0, true)
	tray.draw_polyline(PackedVector2Array([Vector2(0, d), Vector2(d, 0), Vector2(w - d, 0), Vector2(w, d)]), faint, 1.0, true)
	# kleine Endmarken an den Knickpunkten unten
	tray.draw_line(Vector2(d, h - 4), Vector2(d, h), strong, 2.0)
	tray.draw_line(Vector2(w - d, h - 4), Vector2(w - d, h), strong, 2.0)
	# diagonale Zierstreifen unten mittig
	for i in 3:
		var x := w * 0.5 - 8.0 + i * 7.0
		tray.draw_line(Vector2(x, h - 7), Vector2(x + 5, h - 2), faint, 1.5, true)


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
