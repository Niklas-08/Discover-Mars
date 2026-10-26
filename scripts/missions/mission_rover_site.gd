extends Node3D
## Missionszone fuer den ferngesteuerten Rover Perseverance.
##
## Aktiv, wenn das Ziel aktiv ist, der Spieler Perseverance gerade fernsteuert
## und der Rover innerhalb von `radius` steht. Dann erscheint der Hinweis mit
## Missionsprioritaet und [F] wird HIER verarbeitet -- in _input(), also vor
## dem eigenen _unhandled_input() des Rovers, der sonst ueberall eine
## beliebige Probe nehmen wuerde.
##
## Modi:
##   SAMPLE   -- [F] startet perseverance.take_sample(). Gemeldet wird erst bei
##               sample_finished und nur, wenn die Probe in der Zone genommen
##               wurde.
##   INTERACT -- [F] meldet das Ziel sofort (z. B. Analyse an der Habitat).
##
## Nebenwirkungen (Fracht setzen, Analyse einblenden) erledigt mission_story.gd
## beim Abschluss des Ziels -- diese Zone meldet nur.

enum Mode { SAMPLE, INTERACT }

@export var objective_id: StringName = &""
@export var mode: Mode = Mode.SAMPLE
@export var prompt_text: String = "[F]  Probe entnehmen"
## Radius (Meter) um diesen Knoten, in dem der Rover stehen muss.
@export var radius: float = 12.0
## Nur aktiv, wenn diese Fracht mitgefuehrt wird. Leer = keine Bedingung.
@export var required_flag: StringName = &""

const PRIORITY := 10

var _rover: Node3D = null
var _hud: Node = null
var _source: StringName = &""
var _waiting_for_sample: bool = false
var _shown: bool = false


func _ready() -> void:
	_source = StringName("rover_site_%d" % get_instance_id())
	call_deferred("_connect_rover")


func _connect_rover() -> void:
	_rover = get_tree().get_first_node_in_group(&"perseverance")
	if _rover == null:
		push_warning("MissionRoverSite '%s': Perseverance nicht gefunden." % name)
		return
	if _rover.has_signal(&"sample_finished"):
		_rover.sample_finished.connect(_on_sample_finished)


func _exit_tree() -> void:
	_set_prompt(false)


## Steht der ferngesteuerte Rover jetzt in einer aktiven Zone?
func is_available() -> bool:
	if _rover == null or not is_instance_valid(_rover):
		return false
	if not bool(_rover.get(&"controlled")) or bool(_rover.get(&"sampling")):
		return false
	if not MissionManager.is_objective_active(objective_id):
		return false
	if not required_flag.is_empty() and not MissionManager.has_flag(required_flag):
		return false
	return _horizontal_distance(_rover.global_position) <= radius


func _horizontal_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _process(_delta: float) -> void:
	_set_prompt(is_available())


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not is_available():
		return
	get_viewport().set_input_as_handled()
	match mode:
		Mode.SAMPLE:
			if _rover.take_sample():
				_waiting_for_sample = true
		Mode.INTERACT:
			MissionManager.report(objective_id)


func _on_sample_finished(world_position: Vector3, _time_s: float) -> void:
	if not _waiting_for_sample:
		return
	_waiting_for_sample = false
	# Die Probe zaehlt nur, wenn der Arm innerhalb der Zone den Boden erreicht
	# hat (kleiner Spielraum fuer die Armreichweite).
	if _horizontal_distance(world_position) <= radius + 3.0:
		MissionManager.report(objective_id)


func _set_prompt(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group(&"interaction_hud")
	if _hud == null:
		return
	if value:
		_hud.request_prompt(_source, prompt_text, PRIORITY)
	else:
		_hud.clear_prompt(_source)
