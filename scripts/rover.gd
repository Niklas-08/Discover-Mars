extends VehicleBody3D

## Drivable exploration rover (MMSEV).
##
## Uses Godot's built-in VehicleBody3D / VehicleWheel3D, which provides real
## raycast suspension (spring + damper), per-wheel traction, load transfer and
## friction. WASD only responds while a driver is aboard.
##
## FEDERUNG -- Daempfung muss zur Federhaerte passen:
##
##   kritische Daempfung = 2 * sqrt(suspension_stiffness)
##   Daempfungsgrad d    = damping_wert / (2 * sqrt(suspension_stiffness))
##
## Godots Standardwerte sind ein abgestimmtes Paar (Haerte 5.88, Daempfung
## 0.83/0.88 -> d ~ 0.18). Wird nur die Haerte angehoben und die Daempfung
## stehen gelassen, sinkt d und die Federung schaukelt sich auf: genau das
## passierte hier zuvor mit Haerte 28 und Daempfung 0.75/0.9 (d ~ 0.07).
##
## Aktuelle Abstimmung in exploration_vehicle.tscn:
##   suspension_stiffness = 22.0   -> kritische Daempfung = 9.38
##   damping_compression  = 4.0    -> d = 0.43
##   damping_relaxation   = 5.2    -> d = 0.55
##
## Ausfedern wird staerker gedaempft als Einfedern (5.2 > 4.0). Das ist auch
## im Fahrzeugbau ueblich und verhindert, dass die Feder den Aufbau nach einer
## Bodenwelle zurueckwirft -- der Mechanismus, der das Aufschaukeln antreibt.
##
## Wer die Haerte aendert, muss beide Daempfungswerte mitskalieren
## (Faktor sqrt(neue_haerte / alte_haerte)).

## Ein Fahrer ist eingestiegen. Das Missionssystem hoert hierauf, ohne dass
## Rover oder Spieler das Missionssystem kennen muessen.
signal driver_boarded
## Der Fahrer hat den Rover verlassen.
signal driver_left

# === Antrieb ===
@export_category("Drive")
## Antriebskraft pro Antriebsrad. VehicleBody3D legt engine_force auf JEDES
## Rad mit use_as_traction, bei vier Antriebsraedern wirkt also das Vierfache.
## 2400 N x 4 = 9600 N auf 900 kg ~ 10.7 m/s^2 in der Ebene und genug Reserve
## fuer die Haenge der Pahrump Hills.
@export var max_engine_force: float = 2400.0
@export var max_reverse_force: float = 1400.0
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
	if driver_aboard:
		return
	driver_aboard = true
	freeze = false
	if driver_camera:
		driver_camera.current = true
	driver_boarded.emit()

## Vom Spieler aufgerufen beim Aussteigen.
func deactivate() -> void:
	if not driver_aboard:
		return
	driver_aboard = false
	engine_force = 0.0
	steering = 0.0
	brake = parked_brake
	if driver_camera:
		driver_camera.current = false
	driver_left.emit()

func get_speed_kph() -> float:
	return linear_velocity.length() * 3.6

## Fahrtrichtung des Fahrzeugs in Weltkoordinaten.
##
## Das MMSEV-Modell und die Fahrerkamera blicken entlang +Z, nicht entlang -Z.
## (Die Fahrerkamera sitzt bei z = -7.4, also hinter dem Fahrzeug, und schaut
## nach +Z.) Ohne diese Korrektur misst forward_speed die Geschwindigkeit mit
## umgekehrtem Vorzeichen: Beim Gasgeben glaubt die Logik dann, das Fahrzeug
## rolle rueckwaerts, bremst voll ab und schneidet den Motor weg. Das Ergebnis
## war ein Grenzzyklus bei etwa 2 km/h -- das Fahrzeug liess sich nicht fahren.
func get_forward_axis() -> Vector3:
	return global_transform.basis.z

## Vorzeichenbehaftete Laengsgeschwindigkeit in m/s. Positiv = vorwaerts.
func get_forward_speed() -> float:
	return linear_velocity.dot(get_forward_axis())

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
	var forward_speed := get_forward_speed()
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
