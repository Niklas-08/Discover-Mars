extends CanvasLayer
## Zentrales Info-Fenster: Briefings, Debriefings, Satellitenbild, Analysen
## und Abschlussbildschirm.
##
## - Mittig, ca. 60 % der Bildschirmbreite, kein Vollbild.
## - Gleiche Gestaltung wie das Missionspanel (MissionStyle, Eckwinkel und
##   Scanlines aus mission_panel_frame.gd).
## - Mehrseitig: "[F] Weiter" blaettert, auf der letzten Seite "[F] Schliessen"
##   (auch ESC).
## - Anfragen werden in eine WARTESCHLANGE gestellt und nacheinander gezeigt,
##   damit z. B. Analyse -> Debriefing -> naechstes Briefing nie uebereinander
##   liegen.
## - Waehrend es offen ist, ist das Spiel pausiert (dieser Knoten laeuft mit
##   PROCESS_MODE_ALWAYS weiter). Das blockiert Spieler, Fahrzeug und Rover
##   zuverlaessig. Die Maus wird freigegeben und beim Schliessen
##   wiederhergestellt.
##
## Seite = Dictionary: { eyebrow, title, body (BBCode), image (Texture2D) }

## Ein Eintrag der Warteschlange wurde geschlossen.
signal entry_closed(tag: StringName)

const WIDTH_FRACTION := 0.6
const MAX_BODY_FRACTION := 0.5      ## max. Texthoehe relativ zur Bildschirmhoehe
const IMAGE_FRACTION := 0.34        ## Bildhoehe relativ zur Bildschirmhoehe
const INPUT_GUARD_MS := 300         ## dieselbe Taste darf das Fenster nicht sofort schliessen
const FADE := 0.22

var _queue: Array[Dictionary] = []
var _entry: Dictionary = {}
var _page: int = 0
var _opened_ms: int = 0

var _was_paused: bool = false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## Ein Fenster (oder eine Folge von Fenstern) ist offen; Pause/Maus gesichert.
var _session: bool = false

var _dim: ColorRect
var _panel: PanelContainer
var _frame: Control
var _eyebrow: Label
var _title: Label
var _image: TextureRect
var _scroll: ScrollContainer
var _body: RichTextLabel
var _page_label: Label
var _hint: Label
var _buttons: HBoxContainer


func _ready() -> void:
	add_to_group(&"info_overlay")
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_dim.visible = false


# --- Oeffentliche API ------------------------------------------------------

func is_open() -> bool:
	return not _entry.is_empty()


## Eine oder mehrere Seiten anzeigen (Warteschlange).
func show_pages(pages: Array, tag: StringName = &"") -> void:
	_enqueue({ "pages": pages, "buttons": [], "tag": tag })


## Einseitiger Text.
func show_text(eyebrow: String, title: String, body: String, image: Texture2D = null, tag: StringName = &"") -> void:
	show_pages([{ "eyebrow": eyebrow, "title": title, "body": body, "image": image }], tag)


## Seite mit Schaltflaechen statt [F]-Schliessen. buttons = [[Text, Callable], ...]
func show_choice(eyebrow: String, title: String, body: String, buttons: Array, tag: StringName = &"") -> void:
	_enqueue({ "pages": [{ "eyebrow": eyebrow, "title": title, "body": body }], "buttons": buttons, "tag": tag })


# --- Ablauf ---------------------------------------------------------------

func _enqueue(entry: Dictionary) -> void:
	_queue.append(entry)
	if not is_open():
		_open_next()


func _open_next() -> void:
	if _queue.is_empty():
		_close_all()
		return
	_entry = _queue.pop_front()
	_page = 0
	# Pause/Maus nur beim ersten Fenster einer Folge sichern, sonst wuerde
	# z. B. Debriefing -> Briefing den bereits pausierten Zustand "merken".
	if not _session:
		_session = true
		_was_paused = get_tree().paused
		_prev_mouse_mode = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_page()


func _show_page() -> void:
	var pages: Array = _entry.pages
	var p: Dictionary = pages[_page]
	var last := _page == pages.size() - 1

	_eyebrow.text = String(p.get("eyebrow", ""))
	_eyebrow.visible = not _eyebrow.text.is_empty()
	_title.text = p.get("title", "")
	var img: Texture2D = p.get("image", null)
	_image.texture = img
	_image.visible = img != null
	_body.text = p.get("body", "")
	_scroll.scroll_vertical = 0
	_page_label.text = "SEITE %d / %d" % [_page + 1, pages.size()] if pages.size() > 1 else ""

	# Schaltflaechen (Abschlussbildschirm) oder Tastenhinweis
	for c in _buttons.get_children():
		c.queue_free()
	var buttons: Array = _entry.buttons
	_buttons.visible = last and not buttons.is_empty()
	_hint.visible = not _buttons.visible
	_hint.text = "[F]  Schließen" if last else "[F]  Weiter"
	if _buttons.visible:
		for b in buttons:
			_buttons.add_child(_make_button(b[0], b[1]))

	_layout()
	_dim.visible = true
	_opened_ms = Time.get_ticks_msec()
	_fade_in()
	if _buttons.visible and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Button).grab_focus.call_deferred()


func _advance() -> void:
	if _page < (_entry.pages as Array).size() - 1:
		_page += 1
		_show_page()
	else:
		_finish_entry()


func _finish_entry() -> void:
	var tag: StringName = _entry.get("tag", &"")
	_entry = {}
	entry_closed.emit(tag)
	# Ein Hoerer kann dabei schon das naechste Fenster geoeffnet haben.
	if is_open():
		return
	if _queue.is_empty():
		_close_all()
	else:
		_open_next()


func _close_all() -> void:
	_entry = {}
	_dim.visible = false
	if not _session:
		return
	_session = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _prev_mouse_mode


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	# Alles schlucken, solange das Fenster offen ist (Tasten, Aktionen,
	# Gamepad) -- sonst wuerde dieselbe [F], die das Fenster schliesst, danach
	# noch beim Rover oder einer Interaktion ankommen. Mausereignisse bleiben
	# frei fuer die Schaltflaechen.
	if not event is InputEventMouse:
		get_viewport().set_input_as_handled()
	if (_entry.buttons as Array).size() > 0 and _page == (_entry.pages as Array).size() - 1:
		return   # Abschlussbildschirm: nur Schaltflaechen
	if Time.get_ticks_msec() - _opened_ms < INPUT_GUARD_MS:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		_advance()


# --- Aufbau ---------------------------------------------------------------

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var box := MissionStyle.panel_stylebox()
	box.bg_color = Color(MissionStyle.PANEL_BG, 0.94)
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.content_margin_top = 24
	box.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", box)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	_eyebrow = _label(MissionStyle.header_font(), 14, MissionStyle.AMBER)
	_eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_eyebrow)

	_title = _label(MissionStyle.header_font(), 26, MissionStyle.TEXT_BRIGHT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)

	var divider := Control.new()
	divider.set_script(load("res://scripts/ui/mission_divider.gd"))
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(divider)

	_image = TextureRect.new()
	_image.name = "Image"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(_image)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_override("normal_font", MissionStyle.body_font())
	_body.add_theme_font_override("bold_font", MissionStyle.header_font())
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_font_size_override("bold_font_size", 18)
	_body.add_theme_color_override("default_color", MissionStyle.TEXT_BRIGHT)
	_body.add_theme_constant_override("line_separation", 5)
	_scroll.add_child(_body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	col.add_child(footer)

	_page_label = _label(MissionStyle.header_font(), 13, MissionStyle.TEXT_MUTED)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_page_label)

	_hint = _label(MissionStyle.header_font(), 17, MissionStyle.AMBER)
	footer.add_child(_hint)

	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	footer.add_child(_buttons)

	_frame = Control.new()
	_frame.set_script(load("res://scripts/ui/mission_panel_frame.gd"))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.add_theme_font_override("font", MissionStyle.header_font())
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", MissionStyle.TEXT_BRIGHT)
	b.add_theme_color_override("font_hover_color", MissionStyle.AMBER)
	b.add_theme_color_override("font_focus_color", MissionStyle.AMBER)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(MissionStyle.AMBER, 0.18 if state in ["hover", "focus"] else (0.3 if state == "pressed" else 0.06))
		sb.border_color = MissionStyle.AMBER if state != "normal" else MissionStyle.AMBER_DIM
		sb.set_border_width_all(1)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func() -> void:
		_finish_entry()
		action.call())
	return b


## Breite ~60 %, Bild und Text in der Hoehe begrenzt (Text scrollt).
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := vp.x * WIDTH_FRACTION
	_panel.custom_minimum_size = Vector2(w, 0.0)
	_image.custom_minimum_size = Vector2(0.0, vp.y * IMAGE_FRACTION) if _image.visible else Vector2.ZERO
	var max_body := vp.y * (MAX_BODY_FRACTION - (IMAGE_FRACTION * 0.6 if _image.visible else 0.0))
	_body.custom_minimum_size = Vector2(w - 70.0, 0.0)
	_body.size.x = w - 70.0
	# Erst nach dem Umbruch kennt das Label seine Hoehe.
	var h := _body.get_content_height()
	_scroll.custom_minimum_size = Vector2(0.0, clampf(h + 4.0, 40.0, max_body))
	_fix_height_next_frame.call_deferred(max_body)


func _fix_height_next_frame(max_body: float) -> void:
	var h := _body.get_content_height()
	_scroll.custom_minimum_size.y = clampf(h + 4.0, 40.0, max_body)


func _fade_in() -> void:
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.98, 0.98)
	var t := create_tween().set_parallel(true)
	t.tween_property(_panel, "modulate:a", 1.0, FADE)
	t.tween_property(_panel, "scale", Vector2.ONE, FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _frame.has_method("set"):
		t.tween_method(func(v: float) -> void: _frame.highlight = v, 1.0, 0.0, 0.6)
