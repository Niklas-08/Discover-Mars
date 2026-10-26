extends VehicleBody3D

## Mars 2020 "Perseverance" - remote-controlled rover.
##
## Press R (anywhere, except while sitting in the MMSEV) to take control: the
## astronaut stays where he is, the camera follows the rover, WASD drives.
## R again hands control back to the astronaut. F takes a sample (arm
## animation); the rover can't move while it plays.
##
## The player script (CharacterBody3D.gd) owns the R toggle and calls
## take_control() / release_control().
##
## FOR MISSIONS: listen to the signals below, e.g.
##     var rover := get_tree().get_first_node_in_group("perseverance")
##     rover.sample_finished.connect(func(pos, _t): if pos.distance_to(site) < 5: ...)
## or call rover.take_sample() from code. Nothing here knows about missions.

## Control switched to the rover.
signal control_taken
## Control handed back to the astronaut.
signal control_released
## The sampling animation started at this world position.
signal sample_started(world_position: Vector3)
## The sampling animation finished. world_position = where the drill touched
## the ground (in front of the rover), time_s = game time in seconds.
signal sample_finished(world_position: Vector3, time_s: float)

# === Drive ===
@export_category("Drive")
## Top speed. The real rover does ~0.15 km/h; this is a playable compromise.
@export var max_speed_kph: float = 10.0
## Top speed while Shift ("sprint") is held.
@export var boost_speed_kph: float = 20.0
## Engine force PER DRIVEN WHEEL (all six are driven, like the real rover).
@export var engine_force_per_wheel: float = 700.0
@export var max_brake: float = 6.0
## Brake while parked / nobody controls it.
@export var parked_brake: float = 60.0

# === Steering ===
@export_category("Steering")
## Max angle of the four corner wheels. Front and rear turn in opposite
## directions (rocker-bogie style), so the rover turns on a tight circle.
@export var max_steer_angle_deg: float = 28.0
@export var steer_speed: float = 1.6

# === Camera ===
@export_category("Camera")
## Chase-camera offset behind/above the rover (rover space, rover faces +Z).
@export var camera_offset: Vector3 = Vector3(0.0, 2.6, -5.5)
## Point the camera looks at, relative to the rover.
@export var camera_look_offset: Vector3 = Vector3(0.0, 0.9, 1.0)
@export var camera_smoothing: float = 4.0

# === Sampling ===
@export_category("Sampling")
## Playback speed of the arm animation (the original takes ~24 s).
@export var sample_animation_speed: float = 2.0
## Arm reach in front of the rover - where sample_finished reports the sample.
@export var sample_reach: float = 2.2

## Animations from the model that together make up "taking a sample":
## the arm segments, the turret at its end, and the turret's camera covers.
const SAMPLE_SOURCE_ANIMATIONS := [
	"armAction", "arm_002Action", "arm_003Action", "arm_004Action",
	"turret_objAction", "turret_cam_cover_01", "turret_001Action_001",
]
const SAMPLE_ANIM := &"take_sample"

## Wheel name -> centre of that wheel in the model (measured from the mesh).
const WHEEL_CENTRES := {
	"WheelLF": Vector3(1.06, 0.26, 1.09), "WheelRF": Vector3(-1.06, 0.26, 1.09),
	"WheelLM": Vector3(1.18, 0.26, -0.09), "WheelRM": Vector3(-1.18, 0.26, -0.09),
	"WheelLB": Vector3(1.06, 0.26, -1.16), "WheelRB": Vector3(-1.06, 0.26, -1.16),
}

var controlled: bool = false
var sampling: bool = false

var _steer: float = 0.0
@onready var _camera: Camera3D = $ChaseCamera
@onready var _model: Node3D = $Model
var _anim: AnimationPlayer = null


func _ready() -> void:
	add_to_group("perseverance")
	_camera.top_level = true
	_camera.current = false
	_split_wheels()
	_build_sample_animation()
	engine_force = 0.0
	brake = parked_brake


# ---------------------------------------------------------------------------
#  Control (called by the player script on R)
# ---------------------------------------------------------------------------
func take_control() -> void:
	if controlled:
		return
	controlled = true
	freeze = false
	_camera.global_transform = _camera_target()
	_camera.current = true
	control_taken.emit()


func release_control() -> void:
	if not controlled:
		return
	controlled = false
	engine_force = 0.0
	brake = parked_brake
	_camera.current = false
	control_released.emit()


func get_speed_kph() -> float:
	return linear_velocity.length() * 3.6


## Signed speed along the rover's nose (+Z). Positive = forwards.
func get_forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)


# ---------------------------------------------------------------------------
#  Sampling
# ---------------------------------------------------------------------------
## Starts the sampling animation. Returns false if it can't run right now.
## Can be called by missions, too - the rover stops for the duration.
func take_sample() -> bool:
	if sampling or _anim == null or not _anim.has_animation(SAMPLE_ANIM):
		return false
	sampling = true
	sample_started.emit(get_sample_position())
	_anim.play(SAMPLE_ANIM, -1.0, sample_animation_speed)
	return true


## Where the arm reaches the ground (in front of the rover), world space.
func get_sample_position() -> Vector3:
	return global_position + global_transform.basis.z * sample_reach


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != SAMPLE_ANIM:
		return
	sampling = false
	_anim.stop()
	sample_finished.emit(get_sample_position(), Time.get_ticks_msec() / 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if controlled and event.is_action_pressed("interact"):
		take_sample()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
#  Driving
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_input := 0.0
	if controlled and not sampling:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_input = Input.get_axis("move_right", "move_left")

	# --- Steering: front corner wheels one way, rear corners the other ---
	_steer = move_toward(_steer, steer_input * deg_to_rad(max_steer_angle_deg), steer_speed * delta)
	for w in ["WheelLF", "WheelRF"]:
		get_node(w).steering = _steer
	for w in ["WheelLB", "WheelRB"]:
		get_node(w).steering = -_steer

	# --- Drive ---
	if not controlled or sampling:
		engine_force = 0.0
		brake = parked_brake
		# Lock in place once (nearly) stopped and standing on the ground: brakes
		# alone let it creep down slopes, and during sampling it must not move.
		if not freeze and linear_velocity.length() < 0.35 \
				and angular_velocity.length() < 0.35 and _wheels_on_ground() >= 4:
			freeze = true
		return

	if freeze:
		freeze = false

	var fwd := get_forward_speed()
	if absf(throttle) < 0.05:
		engine_force = 0.0
		brake = max_brake * 0.5
	elif signf(throttle) != signf(fwd) and absf(fwd) > 0.3:
		engine_force = 0.0          # pressing against the motion: brake first
		brake = max_brake
	else:
		var top := boost_speed_kph if Input.is_action_pressed("sprint") else max_speed_kph
		var limit := absf(fwd) * 3.6 >= top
		engine_force = 0.0 if limit else engine_force_per_wheel * throttle
		brake = 0.0


func _process(delta: float) -> void:
	if _camera.current:
		var t := _camera_target()
		var k := 1.0 - exp(-camera_smoothing * delta)
		_camera.global_position = _camera.global_position.lerp(t.origin, k)
		var look := global_position + global_transform.basis * camera_look_offset
		var dir := look - _camera.global_position
		# Nach einem grossen Sprung kann die Kamera kurz senkrecht ueber dem
		# Ziel stehen -- dann ist look_at() undefiniert.
		if dir.length() > 0.01 and absf(dir.normalized().dot(Vector3.UP)) < 0.99:
			_camera.look_at(look, Vector3.UP)


## Desired camera transform: behind the rover, following only its heading
## (not its pitch/roll), so bumps don't shake the view.
func _camera_target() -> Transform3D:
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var heading := Basis.looking_at(-fwd, Vector3.UP)   # +Z of this basis = fwd
	var pos := global_position + heading * camera_offset
	return Transform3D(Basis(), pos).looking_at(global_position + global_transform.basis * camera_look_offset, Vector3.UP)


func _wheels_on_ground() -> int:
	var n := 0
	for c in get_children():
		if c is VehicleWheel3D and c.is_in_contact():
			n += 1
	return n


# ---------------------------------------------------------------------------
#  Setup: split the single wheel mesh into six spinning/steering wheels
# ---------------------------------------------------------------------------
## The model stores all six wheels as ONE mesh ("Wheels_objs"). Each triangle
## is assigned to its nearest wheel centre, and each wheel becomes its own
## mesh, centred on its hub and placed INSIDE its VehicleWheel3D. Godot moves
## that node with the wheel's spin, steering and suspension travel, so the
## visible wheels do exactly what the physics wheels do.
func _split_wheels() -> void:
	var src: MeshInstance3D = _model.get_node_or_null("Wheels_objs")
	if src == null or src.mesh == null:
		push_warning("Perseverance: Wheels_objs not found - wheels won't animate.")
		return
	var to_model: Transform3D = _model.global_transform.affine_inverse() * src.global_transform
	var names: Array = WHEEL_CENTRES.keys()
	var meshes := {}
	for n in names:
		meshes[n] = ArrayMesh.new()

	for si in src.mesh.get_surface_count():
		var arrays: Array = src.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] else PackedFloat32Array()
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var mat: Material = src.get_active_material(si)

		# model-space positions
		var mv := PackedVector3Array()
		mv.resize(verts.size())
		for i in verts.size():
			mv[i] = to_model * verts[i]

		# triangles -> nearest wheel
		var per_wheel := {}
		for n in names:
			per_wheel[n] = PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c := (mv[idx[t]] + mv[idx[t + 1]] + mv[idx[t + 2]]) / 3.0
			var best := ""
			var bd := INF
			for n in names:
				var d: float = c.distance_squared_to(WHEEL_CENTRES[n])
				if d < bd:
					bd = d
					best = n
			per_wheel[best].append(idx[t])
			per_wheel[best].append(idx[t + 1])
			per_wheel[best].append(idx[t + 2])

		for n in names:
			var tri: PackedInt32Array = per_wheel[n]
			if tri.is_empty():
				continue
			# compact: only the vertices this wheel uses, centred on its hub
			var remap := {}
			var nv := PackedVector3Array()
			var nn := PackedVector3Array()
			var nt := PackedFloat32Array()
			var nu := PackedVector2Array()
			var ni := PackedInt32Array()
			var centre: Vector3 = WHEEL_CENTRES[n]
			var basis := to_model.basis
			for old in tri:
				if not remap.has(old):
					remap[old] = nv.size()
					nv.append(mv[old] - centre)
					nn.append((basis * normals[old]).normalized())
					if not tangents.is_empty():
						var tv := (basis * Vector3(tangents[old * 4], tangents[old * 4 + 1], tangents[old * 4 + 2])).normalized()
						nt.append_array([tv.x, tv.y, tv.z, tangents[old * 4 + 3]])
					if uvs:
						nu.append(uvs[old])
				ni.append(remap[old])
			var out := []
			out.resize(Mesh.ARRAY_MAX)
			out[Mesh.ARRAY_VERTEX] = nv
			out[Mesh.ARRAY_NORMAL] = nn
			if not nt.is_empty():
				out[Mesh.ARRAY_TANGENT] = nt
			if uvs:
				out[Mesh.ARRAY_TEX_UV] = nu
			out[Mesh.ARRAY_INDEX] = ni
			var am: ArrayMesh = meshes[n]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
			am.surface_set_material(am.get_surface_count() - 1, mat)

	for n in names:
		var wheel: VehicleWheel3D = get_node_or_null(n)
		if wheel == null:
			continue
		var vis := MeshInstance3D.new()
		vis.name = "Visual"
		vis.mesh = meshes[n]
		wheel.add_child(vis)
	src.visible = false


# ---------------------------------------------------------------------------
#  Setup: combine the arm animations into one "take_sample" animation
# ---------------------------------------------------------------------------
## Every animation in the model keys EVERY part (most of them just hold
## still), so playing several at once would fight. This takes from each
## source animation only the tracks that actually move, and merges them.
func _build_sample_animation() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim = players[0]
	_anim.animation_finished.connect(_on_animation_finished)
	var merged := Animation.new()
	var used := {}
	for src_name in SAMPLE_SOURCE_ANIMATIONS:
		if not _anim.has_animation(src_name):
			continue
		var a: Animation = _anim.get_animation(src_name)
		merged.length = maxf(merged.length, a.length)
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			if used.has(path) or not _track_moves(a, t):
				continue
			used[path] = true
			a.copy_track(t, merged)
	if merged.get_track_count() == 0:
		push_warning("Perseverance: no arm animation found - F does nothing.")
		return
	var lib: AnimationLibrary = _anim.get_animation_library(&"")
	lib.add_animation(SAMPLE_ANIM, merged)


func _track_moves(a: Animation, t: int) -> bool:
	var n := a.track_get_key_count(t)
	if n < 2:
		return false
	var first = a.track_get_key_value(t, 0)
	for k in range(1, n):
		var v = a.track_get_key_value(t, k)
		if typeof(v) != typeof(first) or not is_equal_approx_any(v, first):
			return true
	return false


static func is_equal_approx_any(a, b) -> bool:
	if a is float:
		return is_equal_approx(a, b)
	if a is Vector3 or a is Quaternion:
		return a.is_equal_approx(b)
	return a == b
