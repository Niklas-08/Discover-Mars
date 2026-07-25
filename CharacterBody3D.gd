extends CharacterBody3D

# === Bewegungseinstellungen ===
@export_category("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8
@export var air_control: float = 0.3
@export var acceleration: float = 10.0
@export var friction: float = 8.0

# === Kamera Einstellungen ===
@export_category("Camera")
@export var mouse_sensitivity: float = 0.003
@export var camera_smoothing: float = 10.0
@export var fov: float = 75.0
@export var head_bob_enabled: bool = true
@export var head_bob_intensity: float = 0.05
@export var head_bob_speed: float = 14.0

# === Third Person Einstellungen ===
@export_category("Third Person")
@export var third_person_distance: float = 5.0
@export var third_person_height: float = 2.0
@export var camera_lag_speed: float = 2.0  # Langsamer Start
@export var camera_lag_acceleration: float = 8.0  # Beschleunigung in der Mitte
@export var camera_lag_max_speed: float = 12.0  # Maximale Geschwindigkeit
@export var camera_offset_smoothing: float = 5.0

# === Post-Processing Einstellungen ===
@export_category("Post Processing")
@export var motion_blur_enabled: bool = false
@export var motion_blur_intensity: float = 0.5
@export var vignette_enabled: bool = true
@export var vignette_intensity: float = 0.3
@export var chromatic_aberration: float = 0.0

# === Flight Mode ===
@export_category("Flight")
@export var flight_speed: float = 10.0
@export var flight_acceleration: float = 5.0

# Interne Variablen
var current_speed: float = 0.0
var is_first_person: bool = true
var flight_mode: bool = false
var head_bob_time: float = 0.0
var camera_rotation: Vector2 = Vector2.ZERO
var third_person_offset: Vector3 = Vector3.ZERO
var camera_velocity: float = 0.0  # Für das Lag-System

# Node Referenzen
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var world_environment: WorldEnvironment = get_viewport().find_child("WorldEnvironment", true, false)

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = fov
	update_post_processing()

func _input(event):
	# Maus-Look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.y * mouse_sensitivity
		camera_rotation.y -= event.relative.x * mouse_sensitivity
		camera_rotation.x = clamp(camera_rotation.x, -PI/2, PI/2)
	
	# Perspektive wechseln
	if event.is_action_pressed("toggle_camera"):  # 'C' Key
		is_first_person = !is_first_person
	
	# Flight Mode
	if event.is_action_pressed("toggle_flight"):  # 'F4' Key
		flight_mode = !flight_mode
		if flight_mode:
			velocity.y = 0
	
	# ESC zum Freigeben der Maus
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	if flight_mode:
		handle_flight_movement(delta)
	else:
		handle_normal_movement(delta)
	
	handle_camera(delta)
	move_and_slide()

func handle_normal_movement(delta):
	# Gravitation
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Springen
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	# Bewegungsgeschwindigkeit
	var speed = walk_speed
	if Input.is_action_pressed("sprint"):
		speed = sprint_speed
	elif Input.is_action_pressed("crouch"):
		speed = crouch_speed
	
	# Bewegungsrichtung
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Bewegung mit Beschleunigung/Reibung
	if direction:
		var target_velocity = direction * speed
		var accel = acceleration if is_on_floor() else acceleration * air_control
		velocity.x = lerp(velocity.x, target_velocity.x, accel * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, accel * delta)
		
		# Head Bob
		if is_on_floor() and head_bob_enabled and is_first_person:
			head_bob_time += delta * head_bob_speed * (velocity.length() / walk_speed)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)
	
	current_speed = Vector2(velocity.x, velocity.z).length()

func handle_flight_movement(delta):
	# 3D Flugbewegung
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fly_up = Input.get_axis("crouch", "jump")
	
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var camera_forward = -camera.global_transform.basis.z
	var camera_right = camera.global_transform.basis.x
	
	var flight_direction = (camera_forward * -input_dir.y + camera_right * input_dir.x).normalized()
	flight_direction.y += fly_up
	flight_direction = flight_direction.normalized()
	
	if flight_direction:
		velocity = velocity.lerp(flight_direction * flight_speed, flight_acceleration * delta)
	else:
		velocity = velocity.lerp(Vector3.ZERO, friction * delta)

func handle_camera(delta):
	# Basis Rotation
	rotation.y = camera_rotation.y
	head.rotation.x = camera_rotation.x
	
	if is_first_person:
		# Erste Person - Head Bob
		camera.position = Vector3.ZERO
		if head_bob_enabled and is_on_floor():
			var bob_offset = Vector3(
				sin(head_bob_time * 0.5) * head_bob_intensity,
				abs(sin(head_bob_time)) * head_bob_intensity,
				0
			)
			camera.position += bob_offset
	else:
		# Dritte Person mit dynamischem Lag-System
		var target_offset = Vector3(0, third_person_height, third_person_distance)
		
		# Berechne die Distanz zum Ziel
		var distance_to_target = third_person_offset.distance_to(target_offset)
		
		# Dynamische Geschwindigkeit basierend auf Distanz
		var dynamic_speed: float
		var half_distance = third_person_distance / 2.0
		
		if distance_to_target < half_distance:
			# Anfangsphase: langsam starten (0 -> camera_lag_speed)
			var t = distance_to_target / half_distance
			dynamic_speed = lerp(camera_lag_speed, camera_lag_max_speed, t)
		else:
			# Endphase: wieder verlangsamen (camera_lag_max_speed -> camera_lag_speed)
			var t = (distance_to_target - half_distance) / half_distance
			dynamic_speed = lerp(camera_lag_max_speed, camera_lag_speed, t)
		
		# Beschleunigung in der Mitte
		camera_velocity = lerp(camera_velocity, dynamic_speed, camera_lag_acceleration * delta)
		
		# Interpolation mit dynamischer Geschwindigkeit
		third_person_offset = third_person_offset.lerp(target_offset, camera_velocity * delta)
		
		# Kamera Position mit Kollisionserkennung
		var desired_position = head.global_position + head.global_transform.basis * third_person_offset
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(head.global_position, desired_position)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		if result:
			camera.global_position = result.position - (head.global_position - result.position).normalized() * 0.2
		else:
			camera.global_position = desired_position

func update_post_processing():
	if not world_environment or not world_environment.environment:
		return
	
	var env = world_environment.environment
	
	# Motion Blur (simuliert mit Glow)
	env.glow_enabled = motion_blur_enabled
	if motion_blur_enabled:
		env.glow_intensity = motion_blur_intensity
		env.glow_strength = 0.8
	
	# Vignette (via Adjustment)
	env.adjustment_enabled = vignette_enabled
	if vignette_enabled:
		env.adjustment_brightness = 1.0 - vignette_intensity * 0.3
		env.adjustment_contrast = 1.0 + vignette_intensity * 0.2

# Debug Info
func _process(_delta):
	if Input.is_action_just_pressed("ui_text_backspace"):
		print("=== Controller Debug ===")
		print("Mode: ", "First Person" if is_first_person else "Third Person")
		print("Flight: ", flight_mode)
		print("Speed: ", current_speed)
		print("Velocity: ", velocity)
		print("On Floor: ", is_on_floor())

#extends CharacterBody3D
#
#
#const SPEED = 5.0
#const JUMP_VELOCITY = 4.5
#
## Get the gravity from the project settings to be synced with RigidBody nodes.
#var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
#
#
#func _physics_process(delta):
	## Add the gravity.
	#if not is_on_floor():
		#velocity.y -= gravity * delta
#
	## Handle jump.
	#if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		#velocity.y = JUMP_VELOCITY
#
	## Get the input direction and handle the movement/deceleration.
	## As good practice, you should replace UI actions with custom gameplay actions.
	#var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	#var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#if direction:
		#velocity.x = direction.x * SPEED
		#velocity.z = direction.z * SPEED
	#else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
		#velocity.z = move_toward(velocity.z, 0, SPEED)
#
	#move_and_slide()
