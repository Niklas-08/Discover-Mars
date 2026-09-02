extends Node
## Verbindet ein beliebiges Signal aus der Welt mit einem Missionsziel.
##
## Damit muessen Spieler und Rover das Missionssystem nicht kennen: Der Rover
## meldet nur "driver_boarded", dieser Knoten uebersetzt das in einen
## Fortschrittsbericht. Rein datengetrieben und fuer spaetere Missionen
## wiederverwendbar.

## ID des Ziels, das gemeldet wird.
@export var objective_id: StringName = &""

@export_group("Signalquelle")
## Gruppe, deren erster Knoten das Signal sendet (z. B. &"rover").
@export var source_group: StringName = &""
## Alternativ ein fester Pfad. Hat Vorrang vor source_group.
@export var source_path: NodePath = NodePath()
## Name des Signals, z. B. &"driver_boarded".
@export var signal_name: StringName = &""

## Fortschritt pro Signalauslesung.
@export var amount: int = 1
## Nach der ersten Meldung trennen.
@export var one_shot: bool = false

var _source: Node = null
var _fired: bool = false


func _ready() -> void:
	# Deferred: Die Quelle muss ihren eigenen _ready() durchlaufen haben
	# (rover.gd traegt sich dort erst in die Gruppe "rover" ein).
	call_deferred("_connect_source")


func _connect_source() -> void:
	if objective_id.is_empty() or signal_name.is_empty():
		push_warning("MissionSignalTrigger '%s': objective_id oder signal_name fehlt." % name)
		return

	_source = _resolve_source()
	if _source == null:
		push_warning("MissionSignalTrigger '%s': Signalquelle nicht gefunden." % name)
		return

	if not _source.has_signal(signal_name):
		push_warning("MissionSignalTrigger '%s': '%s' hat kein Signal '%s'." % [name, _source.name, signal_name])
		return

	if not _source.is_connected(signal_name, _on_source_signal):
		_source.connect(signal_name, _on_source_signal)


func _resolve_source() -> Node:
	if not source_path.is_empty():
		return get_node_or_null(source_path)
	if not source_group.is_empty():
		return get_tree().get_first_node_in_group(source_group)
	return null


## Signale koennen Argumente tragen; die werden hier bewusst verworfen.
func _on_source_signal(_a = null, _b = null, _c = null, _d = null) -> void:
	if one_shot and _fired:
		return
	_fired = true
	MissionManager.report(objective_id, amount)
	if one_shot and _source != null and _source.is_connected(signal_name, _on_source_signal):
		_source.disconnect(signal_name, _on_source_signal)
