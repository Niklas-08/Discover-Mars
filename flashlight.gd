extends SpotLight3D

var flashlight_enabled: bool = false

func _ready() -> void:
	visible = flashlight_enabled

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("flashlight_switch"):
		flashlight_enabled = !flashlight_enabled
		visible = flashlight_enabled
