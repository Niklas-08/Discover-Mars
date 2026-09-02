extends CanvasLayer
## Interaktionshinweis ("[F] ...") unten mittig auf dem Bildschirm.
##
## Zwei Aufgaben:
##
## 1. Registry: Mehrere Systeme (Rover, Missionsobjekte) melden gleichzeitig
##    Hinweise an. Angezeigt wird der Eintrag mit der hoechsten Prioritaet.
##    Ohne diese Entkopplung wuerde der Spieler-Controller, der seinen
##    Rover-Hinweis in jedem Physikframe setzt, jeden anderen ueberschreiben.
##
## 2. Darstellung: Das Panel wird im Code aufgebaut und nutzt dieselben Farben,
##    Schriften und Rahmenelemente wie die Missionsanzeige (MissionStyle und
##    mission_panel_frame.gd), damit beide Einblendungen als ein System lesbar
##    sind statt als zwei zufaellig verschiedene Overlays.

## Prioritaet des Rover-Hinweises. Missionsobjekte liegen bewusst darueber.
const PRIORITY_ROVER := 0
const PRIORITY_MISSION := 10

## Abstand des Panels ueber dem unteren Bildschirmrand.
const BOTTOM_MARGIN := 96.0
const FONT_SIZE_TEXT := 24
const FONT_SIZE_KEY := 21
const FADE_DURATION := 0.16

## Erkennt eine fuehrende Taste in eckigen Klammern: "[F]  Rover betreten".
const KEY_PATTERN := "^\\s*\\[([^\\]]+)\\]\\s*(.*)$"

var _root: Control = null
var _panel: PanelContainer = null
var _frame: Control = null
var _key_wrap: PanelContainer = null
var _key_label: Label = null
var _text_label: Label = null
var _key_regex: RegEx = null
var _fade_tween: Tween = null

## Textlabel des Hinweises. Oeffentlich, damit Tests und Fremdcode den
## angezeigten Text lesen koennen.
var label: Label:
	get: return _text_label

## source (StringName) -> { "text": String, "priority": int, "order": int }
var _entries: Dictionary = {}
var _order_counter: int = 0
var _current_source: StringName = &""
var _current_text: String = ""


func _ready() -> void:
	_key_regex = RegEx.new()
	_key_regex.compile(KEY_PATTERN)
	_build_ui()
	_root.visible = false
	_root.modulate.a = 0.0


# --- Aufbau ---------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "PromptRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_root.offset_top = -(BOTTOM_MARGIN + 90.0)
	_root.offset_bottom = -BOTTOM_MARGIN
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# CenterContainer zentriert das inhaltsbreite Panel waagerecht.
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _prompt_stylebox())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 13)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	# Tastenkappe: eigener Rahmen, damit die Taste sofort als Eingabe lesbar ist.
	_key_wrap = PanelContainer.new()
	_key_wrap.name = "KeyCap"
	_key_wrap.add_theme_stylebox_override("panel", _keycap_stylebox())
	_key_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_key_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_key_wrap)

	_key_label = Label.new()
	_key_label.name = "Key"
	_key_label.add_theme_font_override("font", MissionStyle.header_font())
	_key_label.add_theme_font_size_override("font_size", FONT_SIZE_KEY)
	_key_label.add_theme_color_override("font_color", MissionStyle.AMBER)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_wrap.add_child(_key_label)

	_text_label = Label.new()
	_text_label.name = "Text"
	_text_label.add_theme_font_override("font", MissionStyle.header_font())
	_text_label.add_theme_font_size_override("font_size", FONT_SIZE_TEXT)
	_text_label.add_theme_color_override("font_color", MissionStyle.TEXT_BRIGHT)
	_text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text_label)

	# Gleiche Eckwinkel, Scanlines und Akzentkante wie die Missionsanzeige.
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.set_script(load("res://scripts/ui/mission_panel_frame.gd"))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_frame)


func _prompt_stylebox() -> StyleBoxFlat:
	var box := MissionStyle.panel_stylebox()
	box.content_margin_left = 18.0
	box.content_margin_right = 20.0
	box.content_margin_top = 11.0
	box.content_margin_bottom = 11.0
	return box


func _keycap_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(MissionStyle.AMBER.r, MissionStyle.AMBER.g, MissionStyle.AMBER.b, 0.14)
	box.border_color = MissionStyle.AMBER_DIM
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 3.0
	return box


# --- Oeffentliche API -----------------------------------------------------

## Meldet einen Hinweis an. Erneuter Aufruf mit derselben source aktualisiert
## den Eintrag, ohne ihn zu duplizieren.
func request_prompt(source: StringName, text: String, priority: int = 0) -> void:
	var existing: Dictionary = _entries.get(source, {})
	# Reihenfolge nur bei echtem Neueintrag hochzaehlen, damit ein pro Frame
	# aktualisierter Hinweis nicht dauerhaft aeltere Eintraege verdraengt.
	var order: int = int(existing.get("order", -1))
	if order < 0:
		_order_counter += 1
		order = _order_counter

	if existing.get("text", "") == text and int(existing.get("priority", -1)) == priority:
		return

	_entries[source] = { "text": text, "priority": priority, "order": order }
	_refresh()


## Entfernt den Hinweis dieser Quelle.
func clear_prompt(source: StringName) -> void:
	if not _entries.has(source):
		return
	_entries.erase(source)
	_refresh()


## Quelle des aktuell sichtbaren Hinweises, oder &"" wenn nichts angezeigt wird.
## Der Spieler nutzt das, um [F] dem hoechstprioren System zu ueberlassen.
func get_top_source() -> StringName:
	return _current_source


func has_prompt() -> bool:
	return not _entries.is_empty()


# --- Kompatibilitaet ------------------------------------------------------
# Altes API, damit vorhandener Code unveraendert weiterlaeuft.

func show_prompt(text: String) -> void:
	request_prompt(&"legacy", text, PRIORITY_ROVER)


func hide_prompt() -> void:
	clear_prompt(&"legacy")


# --- Intern ---------------------------------------------------------------

func _refresh() -> void:
	var best_source: StringName = &""
	var best_priority: int = -0x7FFFFFFF
	var best_order: int = -1
	var best_text: String = ""

	for source: StringName in _entries:
		var entry: Dictionary = _entries[source]
		var priority: int = int(entry["priority"])
		var order: int = int(entry["order"])
		# Hoechste Prioritaet gewinnt; bei Gleichstand der juengere Eintrag.
		if priority > best_priority or (priority == best_priority and order > best_order):
			best_priority = priority
			best_order = order
			best_source = source
			best_text = String(entry["text"])

	_current_source = best_source

	if best_source.is_empty():
		_set_shown(false)
		_current_text = ""
		return

	if best_text != _current_text:
		_apply_text(best_text)
		_current_text = best_text
	_set_shown(true)


## Trennt eine fuehrende "[Taste]" vom Hinweistext ab.
func _apply_text(text: String) -> void:
	var key := ""
	var body := text

	var match_result := _key_regex.search(text)
	if match_result != null:
		key = match_result.get_string(1).strip_edges()
		body = match_result.get_string(2).strip_edges()

	_key_wrap.visible = not key.is_empty()
	_key_label.text = key
	_text_label.text = body


func _set_shown(value: bool) -> void:
	if _root == null:
		return
	if value and _root.visible and _root.modulate.a >= 1.0:
		return
	if not value and not _root.visible:
		return

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	if value:
		_root.visible = true
		_fade_tween = create_tween()
		_fade_tween.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)
	else:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
		_fade_tween.tween_callback(func() -> void: _root.visible = false)
