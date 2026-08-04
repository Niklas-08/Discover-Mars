extends VehicleBody3D

# === Rover Einstellungen ===
@export_category("Driving")
@export var max_engine_force: float = 120.0
@export var max_brake_force: float = 60.0
@export var max_steering_angle: float = 0.45  # Radians (~25 Grad)
@export var steering_speed: float = 3.0

@export_category("Camera")
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -30.0
@export var max_pitch: float = 20.0

# Interne Variablen
var is_active: bool = false
var current_steering: float = 0.0
var camera_yaw: float = 0.0    # Weltkoordinaten Grad
var camera_pitch: float = -15.0  # Grad, leicht nach unten

@onready var camera_yaw_node: Node3D = $CameraYaw
@onready var camera_pitch_node: Node3D = $CameraYaw/CameraPitch
@onready var camera: Camera3D = $CameraYaw/CameraPitch/Camera3D

func _ready():
	camera.current = false
	add_to_group("rover")

func activate():
	is_active = true
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_yaw = rotation_degrees.y
	camera_pitch = -15.0

func deactivate():
	is_active = false
	camera.current = false
	engine_force = 0.0
	brake = max_brake_force
	steering = 0.0

func _input(event):
	if not is_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity * 57.2958
		camera_pitch -= event.relative.y * mouse_sensitivity * 57.2958
		camera_pitch = clamp(camera_pitch, min_pitch, max_pitch)

func _physics_process(delta):
	if not is_active:
		return
	_handle_driving(delta)
	_handle_camera()

func _handle_driving(delta):
	# Gas / Bremsen
	var throttle = Input.get_axis("move_back", "move_forward")
	if throttle > 0.0:
		engine_force = throttle * max_engine_force
		brake = 0.0
	elif throttle < 0.0:
		engine_force = throttle * max_engine_force * 0.6
		brake = 0.0
	else:
		engine_force = 0.0
		brake = max_brake_force * 0.3

	# Handbremse (Space)
	if Input.is_action_pressed("jump"):
		brake = max_brake_force
		engine_force = 0.0

	# Lenkung
	var steer_input = Input.get_axis("move_right", "move_left")
	var target_steering = steer_input * max_steering_angle
	current_steering = lerp(current_steering, target_steering, steering_speed * delta)
	steering = current_steering

func _handle_camera():
	# Yaw: Kamera dreht sich frei in der Welt (unabhängig vom Rover)
	camera_yaw_node.global_rotation_degrees.y = camera_yaw
	# Pitch: Kamera kippt lokal auf dem Yaw-Node
	camera_pitch_node.rotation_degrees.x = camera_pitch
