@tool
extends Node
class_name DayNightCycle

## Mars day/night cycle.
##
## Drives the sun (DirectionalLight3D), the ambient light and the sky shader
## from a single normalised clock. Everything is exposed in the Inspector and
## updates live, both while playing and inside the editor.
##
## time_of_day is normalised:
##   0.00 = midnight   0.25 = sunrise   0.50 = noon   0.75 = sunset

# =============================================================================
#  Cycle
# =============================================================================
@export_category("Cycle")

## Seconds for one full day/night rotation. 120 = 2 minutes.
@export var cycle_duration: float = 120.0:
	set(value):
		cycle_duration = maxf(value, 0.1)

## Current time of day (0 = midnight, 0.5 = noon). Drag to scrub the sky.
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.30:
	set(value):
		time_of_day = fposmod(value, 1.0)
		_apply()

## Stop the clock (the sky stays wherever time_of_day points).
@export var paused: bool = false

## Let the cycle animate inside the editor viewport too.
@export var run_in_editor: bool = false

# =============================================================================
#  Sun
# =============================================================================
@export_category("Sun")

## Compass direction the sun rises from.
@export_range(0.0, 360.0, 0.1) var sun_azimuth_degrees: float = 35.0:
	set(value):
		sun_azimuth_degrees = value
		_apply()

## Peak brightness at noon. Mars receives ~43% of Earth's sunlight.
@export var max_sun_energy: float = 1.15

## Sun colour with the sun high in the sky.
@export var sun_color_noon: Color = Color(1.0, 0.95, 0.88)

## Sun colour near the horizon (reddened by the dust it shines through).
@export var sun_color_horizon: Color = Color(1.0, 0.58, 0.34)

# =============================================================================
#  Ambient
# =============================================================================
@export_category("Ambient")

## Scattered daylight. Mars' dust makes daytime shadows fairly filled-in.
@export var ambient_day_energy: float = 0.55

## Ambient at night - nearly nothing, there is no real moonlight on Mars.
@export var ambient_night_energy: float = 0.02

# =============================================================================
#  References
# =============================================================================
@export_category("References")
@export var sun_path: NodePath = ^"../DirectionalLight3D"
@export var environment_path: NodePath = ^"../WorldEnvironment"

const SKY_MATERIAL_PATH := "res://assets/materials/mars_sky.tres"

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _sky_material: ShaderMaterial


func _ready() -> void:
	_resolve_nodes()
	_apply()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not run_in_editor:
		return
	if paused:
		return
	# Setter re-applies everything.
	time_of_day = time_of_day + delta / cycle_duration


func _resolve_nodes() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_world_env = get_node_or_null(environment_path) as WorldEnvironment

	# Fall back to searching the scene, so a renamed node does not break things.
	if _sun == null:
		_sun = _find_first(get_tree().get_root() if is_inside_tree() else self, "DirectionalLight3D") as DirectionalLight3D
	if _world_env == null:
		_world_env = _find_first(get_tree().get_root() if is_inside_tree() else self, "WorldEnvironment") as WorldEnvironment

	_sky_material = null
	if _world_env and _world_env.environment and _world_env.environment.sky:
		var mat := _world_env.environment.sky.sky_material
		if mat is ShaderMaterial:
			_sky_material = mat
	# The scene may have lost the assignment (Godot drops some instanced-scene
	# overrides on autosave), so make sure our sky is actually installed.
	if _sky_material == null and _world_env and _world_env.environment:
		var loaded := load(SKY_MATERIAL_PATH)
		if loaded is ShaderMaterial:
			if _world_env.environment.sky == null:
				_world_env.environment.sky = Sky.new()
			_world_env.environment.sky.sky_material = loaded
			_sky_material = loaded


func _find_first(node: Node, type_name: String) -> Node:
	if node == null:
		return null
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var r := _find_first(c, type_name)
		if r:
			return r
	return null


## Direction pointing toward the sun (unit vector).
func get_sun_direction() -> Vector3:
	var elevation := (time_of_day - 0.25) * TAU
	var azimuth := deg_to_rad(sun_azimuth_degrees)
	# Sun travels a circle: up at noon, straight down at midnight.
	var dir := Vector3(0.0, sin(elevation), -cos(elevation))
	return dir.rotated(Vector3.UP, azimuth).normalized()


## Height of the sun: 1 = zenith, 0 = horizon, negative = below the horizon.
func get_sun_elevation() -> float:
	return get_sun_direction().y


## True while the sun is above the horizon.
func is_daytime() -> bool:
	return get_sun_elevation() > 0.0


func _apply() -> void:
	if _sun == null or _sky_material == null:
		_resolve_nodes()

	var sun_dir := get_sun_direction()
	var sun_height := sun_dir.y

	# 0 while fully night, 1 once the sun is properly up.
	var day := smoothstep(-0.20, 0.10, sun_height)
	# 0 at the horizon, 1 high in the sky - used for colour warming.
	var elevation_mix := smoothstep(0.0, 0.35, sun_height)

	# --- Sun ---------------------------------------------------------------
	if _sun:
		# DirectionalLight3D emits along -Z, so aim -Z away from the sun.
		_sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
		_sun.light_energy = max_sun_energy * day
		_sun.light_color = sun_color_horizon.lerp(sun_color_noon, elevation_mix)
		_sun.visible = day > 0.001

	# --- Ambient -----------------------------------------------------------
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = lerpf(ambient_night_energy, ambient_day_energy, day)

	# --- Sky shader --------------------------------------------------------
	if _sky_material:
		_sky_material.set_shader_parameter("sun_direction", sun_dir)
