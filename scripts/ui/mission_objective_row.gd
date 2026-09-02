class_name MissionObjectiveRow
extends HBoxContainer
## Eine Zeile der Aufgabenliste: Status, Symbol, Text und optionaler Zaehler.
##
## Baut sich selbst auf, damit das HUD Zeilen zur Laufzeit erzeugen kann --
## die Zielanzahl steht erst beim Missionsstart fest.

## Sekunden, die die Zeile beim Erfuellen weiss aufblitzt.
const FLASH_DURATION := 0.45

var objective: MissionObjective = null

var _status_icon: TextureRect = null
var _type_icon: TextureRect = null
var _label: RichTextLabel = null
var _counter: Label = null

var _state: int = MissionManager.State.PENDING
var _pulse_time: float = 0.0
var _flash: float = 0.0


func setup(target_objective: MissionObjective) -> void:
	objective = target_objective
	add_theme_constant_override("separation", 9)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN

	_status_icon = TextureRect.new()
	_status_icon.custom_minimum_size = Vector2(17.0, 17.0)
	_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_status_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_icon)

	_type_icon = TextureRect.new()
	_type_icon.custom_minimum_size = Vector2(15.0, 15.0)
	_type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_type_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_icon.texture = MissionStyle.icon(objective.get_type_icon_name())
	add_child(_type_icon)

	# RichTextLabel statt Label: nur damit laesst sich ein erfuelltes Ziel
	# echt durchstreichen ([s]) und gleichzeitig einfaerben.
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("normal_font", MissionStyle.body_font())
	_label.add_theme_font_size_override("normal_font_size", MissionStyle.FONT_SIZE_OBJECTIVE)
	add_child(_label)

	_counter = Label.new()
	_counter.add_theme_font_override("font", MissionStyle.header_font())
	_counter.add_theme_font_size_override("font_size", MissionStyle.FONT_SIZE_COUNTER)
	_counter.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.visible = objective.has_counter()
	add_child(_counter)

	set_state(MissionManager.get_objective_state(objective.id), false)
	set_progress(MissionManager.get_progress(objective.id))


## Setzt den Anzeigezustand. animate=true blitzt beim Erfuellen kurz auf.
func set_state(new_state: int, animate: bool = true) -> void:
	var was_done := _state == MissionManager.State.DONE
	_state = new_state

	if _status_icon:
		_status_icon.texture = MissionStyle.icon(MissionStyle.state_icon_name(_state))

	_apply_colors()
	_refresh_text()

	set_process(_state == MissionManager.State.ACTIVE or _flash > 0.0)

	if animate and _state == MissionManager.State.DONE and not was_done:
		_play_complete_flash()


func set_progress(current: int) -> void:
	if _counter == null or objective == null or not objective.has_counter():
		return
	_counter.text = "%d/%d" % [current, objective.required_count]


func _refresh_text() -> void:
	if _label == null or objective == null:
		return
	var color := MissionStyle.state_color(_state)
	if _state == MissionManager.State.DONE:
		color = MissionStyle.DONE_TEXT
	elif _state == MissionManager.State.ACTIVE:
		color = MissionStyle.TEXT_BRIGHT

	var text := objective.title
	if _state == MissionManager.State.DONE:
		text = "[s]%s[/s]" % text
	_label.text = "[color=#%s]%s[/color]" % [color.to_html(false), text]


func _apply_colors() -> void:
	var accent := MissionStyle.state_color(_state)
	if _status_icon:
		_status_icon.modulate = accent
	if _type_icon:
		var tint := accent
		tint.a = 0.55 if _state != MissionManager.State.ACTIVE else 0.85
		_type_icon.modulate = tint
	if _counter:
		_counter.add_theme_color_override("font_color", accent)


func _play_complete_flash() -> void:
	_flash = 1.0
	set_process(true)
	var tween := create_tween()
	tween.tween_method(_set_flash, 1.0, 0.0, FLASH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_flash(value: float) -> void:
	_flash = value
	if _status_icon:
		_status_icon.modulate = MissionStyle.state_color(_state).lerp(MissionStyle.FLASH, value)
	if value <= 0.0 and _state != MissionManager.State.ACTIVE:
		_apply_colors()
		set_process(false)


func _process(delta: float) -> void:
	if _state != MissionManager.State.ACTIVE or _status_icon == null:
		return
	# Ruhiges Atmen des aktiven Zielsymbols.
	_pulse_time += delta
	var pulse := 0.62 + 0.38 * (0.5 + 0.5 * sin(_pulse_time * 3.4))
	var color := MissionStyle.AMBER
	color.a = pulse
	_status_icon.modulate = color.lerp(MissionStyle.FLASH, _flash)
