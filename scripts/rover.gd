extends VehicleBody3D

## Drivable exploration rover (MMSEV).
##
## Uses Godot's built-in VehicleBody3D / VehicleWheel3D, which provides real
## raycast suspension (spring + damper), per-wheel traction, load transfer and
## friction. WASD only responds while a driver is aboard.

# === Antrieb ===
@export_category("Drive")
@export var max_engine_force: float = 3200.0
@export var max_reverse_force: float = 1800.0
@export var max_brake: float = 12.0
@export var handbrake_force: float = 45.0
@export var parked_brake: float = 150.0
@export var max_speed_kph: float = 45.0

## Material fuer die Rover-Huelle. Wird aus dem .glb extrahiert
## (Albedo + Normal Map liegen in assets/models/Rover/textures/).
@export var hull_material: Material
const HULL_MATERIAL_PATH := "res://assets/materials/rover_hull.tres"

# === Lenkung ===
@export_category("Steering")
@export var max_steer_angle: float = 0.55   # rad
@export var steer_speed: float = 3.5        # wie schnell eingelenkt wird
@export var steer_return_speed: float = 5.0
@export var speed_steer_falloff: float = 0.55  # weniger Lenkeinschlag bei Tempo

var driver_aboard: bool = false
var _steer_target: float = 0.0

@onready var driver_camera: Camera3D = $DriverCamera

func _wheels_on_ground() -> int:
	var n := 0
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			n += 1
	return n

func _ready() -> void:
	add_to_group("rover")
	if hull_material == null:
		hull_material = load(HULL_MATERIAL_PATH)
	_apply_hull_material(self)
	# Bis jemand einsteigt: gebremst stehen bleiben.
	engine_force = 0.0
	brake = parked_brake

func _apply_hull_material(node: Node) -> void:
	if hull_material == null:
		return
	if node is MeshInstance3D:
		node.material_override = hull_material
	for c in node.get_children():
		_apply_hull_material(c)

## Vom Spieler aufgerufen beim Einsteigen.
func activate() -> void:
	driver_aboard = true
	freeze = false
	if driver_camera:
		driver_camera.current = true

## Vom Spieler aufgerufen beim Aussteigen.
func deactivate() -> void:
	driver_aboard = false
	engine_force = 0.0
	steering = 0.0
	brake = parked_brake
	if driver_camera:
		driver_camera.current = false

func get_speed_kph() -> float:
	return linear_velocity.length() * 3.6

func _physics_process(delta: float) -> void:
	if not driver_aboard:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, steer_return_speed * delta)
		brake = parked_brake
		# Ohne Fahrer: sobald der Rover wirklich steht UND auf dem Boden
		# aufliegt, einfrieren. Sonst rutscht er auf dem geneigten
		# Kratergelaende langsam weg.
		if not freeze \
				and _wheels_on_ground() >= 2 \
				and linear_velocity.length() < 0.6 \
				and angular_velocity.length() < 0.6:
			freeze = true
		return

	var throttle := Input.get_axis("move_back", "move_forward")   # W = +1, S = -1
	var steer_input := Input.get_axis("move_right", "move_left")  # A = +1, D = -1

	# --- Lenkung: sanft einlenken, bei hohem Tempo weniger Einschlag ---
	var speed_factor: float = clamp(get_speed_kph() / max_speed_kph, 0.0, 1.0)
	var steer_limit: float = max_steer_angle * (1.0 - speed_factor * speed_steer_falloff)
	_steer_target = steer_input * steer_limit
	var rate: float = steer_speed if absf(steer_input) > 0.01 else steer_return_speed
	steering = move_toward(steering, _steer_target, rate * delta)

	# --- Antrieb ---
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)
	var over_limit := get_speed_kph() >= max_speed_kph

	if absf(throttle) < 0.05:
		# Kein Gas: Motorbremse
		engine_force = 0.0
		brake = max_brake * 0.35
	elif throttle > 0.0:
		if forward_speed < -0.5:
			# Vorwaerts druecken waehrend rueckwaerts rollend = bremsen
			engine_force = 0.0
			brake = max_brake
		else:
			engine_force = 0.0 if over_limit else max_engine_force * throttle
			brake = 0.0
	else:
		if forward_speed > 0.5:
			engine_force = 0.0
			brake = max_brake
		else:
			engine_force = max_reverse_force * throttle
			brake = 0.0

	# Handbremse
	if Input.is_action_pressed("jump"):
		engine_force = 0.0
		brake = handbrake_force
