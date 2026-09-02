extends Area3D
## Ein Objekt in der Welt, das per [F] ein Missionsziel erfuellt.
##
## Meldet seinen Hinweis mit hoher Prioritaet beim InteractionHUD an, damit er
## einen gleichzeitig sichtbaren Rover-Hinweis verdraengt. Der Spieler-
## Controller fragt get_top_source() ab und ueberlaesst [F] dann diesem Knoten.

## ID des Ziels, das erfuellt wird.
@export var objective_id: StringName = &""
## Text des Interaktionshinweises.
@export var prompt_text: String = "[F]  Probe entnehmen"
## Nur einmal ausloesbar.
@export var one_shot: bool = true
## Sichtbares Objekt, das nach der Interaktion verschwindet. Leer = Elternknoten.
@export var visual_path: NodePath = NodePath()
## Objekt nach der Interaktion ausblenden.
@export var hide_visual_on_use: bool = true
## Nur ausloesbar, wenn das Ziel gerade aktiv ist.
@export var require_active_objective: bool = true

@onready var _hud: CanvasLayer = get_tree().get_first_node_in_group(&"interaction_hud")

var _player_inside: bool = false
var _used: bool = false
var _prompt_source: StringName = &""


func _ready() -> void:
	add_to_group(&"mission_interactable")
	# Eindeutige Quelle pro Instanz, damit sich mehrere Objekte nicht gegenseitig
	# aus der HUD-Registry werfen.
	_prompt_source = StringName("mission_interactable_%d" % get_instance_id())

	collision_layer = 0
	collision_mask = 1
	monitoring = true

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	MissionManager.objective_activated.connect(_on_mission_state_changed)
	MissionManager.objective_completed.connect(_on_mission_state_changed)


func _exit_tree() -> void:
	_clear_prompt()


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = true
		_refresh_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = false
		_clear_prompt()


func _on_mission_state_changed(_objective: MissionObjective) -> void:
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _can_use():
		return
	_use()
	get_viewport().set_input_as_handled()


## Kann gerade interagiert werden?
func _can_use() -> bool:
	if _used and one_shot:
		return false
	if not _player_inside:
		return false
	if require_active_objective and not MissionManager.is_objective_active(objective_id):
		return false
	return true


func _use() -> void:
	_used = true
	MissionManager.report(objective_id)
	_clear_prompt()

	if hide_visual_on_use:
		var visual := _resolve_visual()
		if visual != null:
			visual.visible = false
			# Kollision mit deaktivieren, damit nichts Unsichtbares im Weg steht.
			for child in visual.find_children("*", "CollisionShape3D", true, false):
				(child as CollisionShape3D).set_deferred("disabled", true)


func _resolve_visual() -> Node3D:
	if not visual_path.is_empty():
		var node := get_node_or_null(visual_path)
		if node is Node3D:
			return node
	var parent := get_parent()
	return parent if parent is Node3D else null


func _refresh_prompt() -> void:
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group(&"interaction_hud")
	if _hud == null:
		return
	if _can_use():
		_hud.request_prompt(_prompt_source, prompt_text, 10)
	else:
		_clear_prompt()


func _clear_prompt() -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("clear_prompt"):
		_hud.clear_prompt(_prompt_source)
