@tool
extends Node3D
## Ortsmarke fuer ein Missionsziel: 3D-Leuchtfeuer plus optionale Ankunftszone.
##
## Der Knoten wird an die Zielposition gesetzt und mit einer objective_id
## verknuepft. Er zeigt das Leuchtfeuer nur, solange das Ziel aktiv ist, und
## meldet bei TRAVEL-Zielen selbstaendig die Ankunft von Spieler oder Rover.
##
## snap_to_ground loest ein praktisches Problem: die Hoehe des Marsgelaendes an
## einer bestimmten X/Z-Stelle ist beim Bauen der Szene unbekannt. Statt sie zu
## erraten, wird der Knoten beim Start per Strahl von oben auf die Oberflaeche
## fallen gelassen.

## ID des Ziels, zu dem dieser Wegpunkt gehoert.
@export var objective_id: StringName = &""

@export_group("Zielverfolgung")
## Wenn gesetzt, folgt der Wegpunkt live dem ersten Knoten dieser Gruppe
## (z. B. &"rover"). Sonst bleibt er an seiner eigenen Position.
@export var follow_group: StringName = &""
## Versatz auf die verfolgte oder eigene Position.
@export var offset: Vector3 = Vector3.ZERO

@export_group("Bodenausrichtung")
## Beim Start per Strahl von oben auf das Gelaende absetzen.
@export var snap_to_ground: bool = true
## Hoehe ueber der aktuellen Position, ab der nach unten gestrahlt wird.
@export var snap_ray_height: float = 300.0
## Maximale Strahllaenge nach unten.
@export var snap_ray_depth: float = 600.0
## Restabstand ueber dem Boden nach dem Absetzen.
@export var ground_clearance: float = 0.0

@export_group("Ankunftszone")
## Eigene Area3D erzeugen, die die Ankunft von Spieler oder Rover meldet.
@export var create_arrival_area: bool = true
## Radius der Ankunftszone. <= 0 uebernimmt arrival_radius aus dem Ziel.
@export var arrival_radius_override: float = 0.0

@export_group("Leuchtfeuer")
@export var show_beacon: bool = true
## Hoehe der Lichtsaeule in Metern.
@export var beacon_height: float = 60.0
@export var beacon_radius: float = 1.1
@export var beacon_color: Color = Color(0.42, 0.80, 0.92)
## Radius des rotierenden Rings am Boden.
@export var ring_radius: float = 3.2
## Unterhalb dieser Entfernung ist die Saeule vollstaendig ausgeblendet.
## Sonst umhuellt sie am Ziel die Kamera und ueberdeckt das halbe Bild.
@export var fade_near: float = 6.0
## Ab dieser Entfernung ist die Saeule voll sichtbar.
@export var fade_far: float = 14.0

const BEACON_SHADER_PATH := "res://assets/materials/mission_beacon.gdshader"

var _follow_target: Node3D = null
var _area: Area3D = null
var _arrival_shape: SphereShape3D = null
var _beacon_root: Node3D = null
var _beacon_material: ShaderMaterial = null
var _ring: MeshInstance3D = null
var _is_active: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group(&"mission_waypoint")
	_build_beacon()

	if Engine.is_editor_hint():
		# Im Editor nur die Vorschau bauen, keine Spiellogik.
		set_process(false)
		return

	_set_beacon_visible(false)

	# Erst nach dem Physikframe absetzen: die Trimesh-Collider des Gelaendes
	# werden von terrain_collision.gd ebenfalls erst in _ready() erzeugt.
	call_deferred("_deferred_setup")

	MissionManager.objective_activated.connect(_on_objective_activated)
	MissionManager.objective_completed.connect(_on_objective_completed)
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.mission_completed.connect(_on_mission_completed)


func _deferred_setup() -> void:
	await get_tree().physics_frame
	if snap_to_ground:
		_snap_to_ground()
	_resolve_follow_target()
	if create_arrival_area:
		_build_arrival_area()
		# Lief die Mission schon, bevor die Zone stand, Radius nachziehen.
		_apply_arrival_radius()
	_sync_active_state()


# --- Position -------------------------------------------------------------

## Weltposition, auf die der Marker zeigen soll.
func get_target_position() -> Vector3:
	if _follow_target != null and is_instance_valid(_follow_target):
		return _follow_target.global_position + offset
	return global_position + offset


func _resolve_follow_target() -> void:
	if follow_group.is_empty():
		return
	var node := get_tree().get_first_node_in_group(follow_group)
	if node is Node3D:
		_follow_target = node
	else:
		push_warning("MissionWaypoint '%s': Gruppe '%s' enthaelt keinen Node3D." % [name, follow_group])


## Setzt den Knoten per Strahl von oben auf das Gelaende.
func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := global_position + Vector3(0.0, snap_ray_height, 0.0)
	var to := from + Vector3(0.0, -(snap_ray_height + snap_ray_depth), 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Eigene Kindkoerper ausschliessen: Haengt ein Probenfelsen unter dem
	# Wegpunkt, wuerde der Strahl sonst auf dessen Oberseite landen und den
	# Wegpunkt samt Fels ueber dem Gelaende schweben lassen.
	query.exclude = _collect_own_body_rids()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_warning("MissionWaypoint '%s': kein Boden unter der Position gefunden." % name)
		return
	global_position = (hit["position"] as Vector3) + Vector3(0.0, ground_clearance, 0.0)


func _collect_own_body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for node in find_children("*", "CollisionObject3D", true, false):
		rids.append((node as CollisionObject3D).get_rid())
	return rids


# --- Ankunftszone ---------------------------------------------------------

func _build_arrival_area() -> void:
	_area = Area3D.new()
	_area.name = "ArrivalArea"
	# Layer 0, damit die Zone selbst nichts blockiert; Maske 1 = Spieler + Rover.
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true

	var shape := CollisionShape3D.new()
	shape.name = "ArrivalShape"
	_arrival_shape = SphereShape3D.new()
	_arrival_shape.radius = _resolve_arrival_radius()
	shape.shape = _arrival_shape
	_area.add_child(shape)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)


## Radius der Ankunftszone. Override schlaegt den Wert aus dem Missionsziel.
func _resolve_arrival_radius() -> float:
	if arrival_radius_override > 0.0:
		return arrival_radius_override
	var objective := _get_objective()
	return objective.arrival_radius if objective != null else 12.0


## Der Wegpunkt baut seine Zone eine Physikframe nach dem Start, der
## MissionDirector startet die Mission erst danach. Ohne dieses Nachziehen
## bliebe der im Ziel hinterlegte arrival_radius wirkungslos.
func _apply_arrival_radius() -> void:
	if _arrival_shape == null:
		return
	_arrival_shape.radius = _resolve_arrival_radius()


func _on_body_entered(body: Node3D) -> void:
	if not _is_active:
		return
	if _is_mission_actor(body):
		MissionManager.report(objective_id)


## Spieler oder Rover? Der Spieler wird beim Einsteigen an den Rover geheftet,
## daher genuegt eine der beiden Erkennungen, beide sind aber guenstig.
func _is_mission_actor(body: Node) -> bool:
	return body.is_in_group(&"rover") or body is CharacterBody3D


## Nachtraegliche Pruefung: Wird das Ziel erst aktiv, waehrend der Spieler
## bereits in der Zone steht, feuert body_entered nicht mehr.
func _check_already_inside() -> void:
	if _area == null or not _is_active:
		return
	for body in _area.get_overlapping_bodies():
		if _is_mission_actor(body):
			MissionManager.report(objective_id)
			return


# --- Leuchtfeuer ----------------------------------------------------------

func _build_beacon() -> void:
	if not show_beacon:
		return
	if _beacon_root != null and is_instance_valid(_beacon_root):
		_beacon_root.queue_free()

	_beacon_root = Node3D.new()
	_beacon_root.name = "Beacon"
	add_child(_beacon_root)

	var material := _make_beacon_material()

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = beacon_radius
	cylinder.bottom_radius = beacon_radius
	cylinder.height = beacon_height
	cylinder.radial_segments = 12
	cylinder.rings = 1
	shaft.mesh = cylinder
	shaft.material_override = material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(0.0, beacon_height * 0.5, 0.0)
	_beacon_root.add_child(shaft)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius * 0.82
	torus.outer_radius = ring_radius
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.35, 0.0)
	_beacon_root.add_child(_ring)


func _make_beacon_material() -> Material:
	var shader: Shader = load(BEACON_SHADER_PATH) if ResourceLoader.exists(BEACON_SHADER_PATH) else null
	if shader != null:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		shader_material.set_shader_parameter("beacon_color", beacon_color)
		shader_material.set_shader_parameter("fade_height", beacon_height)
		shader_material.set_shader_parameter("proximity_fade", 1.0)
		_beacon_material = shader_material
		return shader_material

	# Rueckfall, falls der Shader fehlt: unbeleuchtet + additiv.
	var fallback := StandardMaterial3D.new()
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	fallback.albedo_color = Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.35)
	return fallback


func _set_beacon_visible(value: bool) -> void:
	if _beacon_root != null and is_instance_valid(_beacon_root):
		_beacon_root.visible = value and show_beacon


func _process(delta: float) -> void:
	if not _is_active:
		return

	# Dem verfolgten Ziel folgen (z. B. Wegpunkt am Rover).
	if _follow_target != null and is_instance_valid(_follow_target):
		global_position = _follow_target.global_position

	if _ring != null and is_instance_valid(_ring):
		_pulse_time += delta
		_ring.rotate_y(delta * 0.9)
		var scale_pulse := 1.0 + sin(_pulse_time * 2.0) * 0.06
		_ring.scale = Vector3(scale_pulse, 1.0, scale_pulse)

	_update_proximity_fade()


## Blendet das Leuchtfeuer aus, wenn die Kamera nah am Ziel ist.
func _update_proximity_fade() -> void:
	if _beacon_material == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	var fade: float = clampf(
		inverse_lerp(fade_near, maxf(fade_far, fade_near + 0.01), distance), 0.0, 1.0
	)
	_beacon_material.set_shader_parameter("proximity_fade", fade)
	if _ring != null and is_instance_valid(_ring):
		# Der Bodenring liegt genau dort, wo der Spieler steht -- frueher ausblenden.
		_ring.visible = fade > 0.05


# --- Missions-Signale -----------------------------------------------------

func _on_mission_started(_mission: Mission) -> void:
	# Erst jetzt sind die Zieldaten bekannt -- Radius nachziehen.
	_apply_arrival_radius()
	_sync_active_state()


func _on_objective_activated(_objective: MissionObjective) -> void:
	_sync_active_state()


func _on_objective_completed(_objective: MissionObjective) -> void:
	_sync_active_state()


func _on_mission_completed(_mission: Mission) -> void:
	_is_active = false
	_set_beacon_visible(false)


func _sync_active_state() -> void:
	var was_active := _is_active
	_is_active = MissionManager.is_objective_active(objective_id) \
		and not MissionManager.is_objective_complete(objective_id)
	_set_beacon_visible(_is_active)

	if _is_active and not was_active:
		_resolve_follow_target()
		# Spieler koennte schon in der Zone stehen.
		call_deferred("_check_already_inside")


func _get_objective() -> MissionObjective:
	if MissionManager.active_mission == null:
		return null
	return MissionManager.active_mission.get_objective(objective_id)
