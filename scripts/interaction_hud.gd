extends CanvasLayer

## Kleiner Interaktions-Hinweis ("Press F ...") unten mittig auf dem Bildschirm.

@onready var label: Label = $Prompt

func _ready() -> void:
	hide_prompt()

func show_prompt(text: String) -> void:
	if label:
		label.text = text
		label.visible = true

func hide_prompt() -> void:
	if label:
		label.visible = false
