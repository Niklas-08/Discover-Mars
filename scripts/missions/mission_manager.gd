extends Node
## Globaler Missions-Zustand. Als Autoload "MissionManager" registriert.
##
## Haelt ausschliesslich Zustand und sendet Signale. Kennt weder UI noch
## Weltknoten. Weltknoten melden Fortschritt ueber report(); die UI hoert
## ausschliesslich auf die Signale. Damit bleibt die Kopplung einseitig.

## Anzeigezustand eines Ziels.
enum State {
	PENDING, ## Noch nicht freigeschaltet (nur bei sequentiellen Missionen).
	ACTIVE,  ## Aktuell zu erfuellen.
	DONE,    ## Erfuellt.
}

signal mission_started(mission: Mission)
signal mission_completed(mission: Mission)
signal objective_activated(objective: MissionObjective)
signal objective_progress_changed(objective: MissionObjective, current: int, required: int)
signal objective_completed(objective: MissionObjective)
## Das Ziel, auf das der Wegpunkt-Marker zeigen soll. null = kein Marker.
signal tracked_objective_changed(objective: MissionObjective)

var active_mission: Mission = null

## objective_id -> int
var _progress: Dictionary = {}
## objective_id -> bool
var _completed: Dictionary = {}
var _finished: bool = false


# --- Missionssteuerung ----------------------------------------------------

## Startet eine Mission und verwirft jeden vorherigen Fortschritt.
func start_mission(mission: Mission) -> void:
	if mission == null:
		push_warning("MissionManager: start_mission() mit null aufgerufen.")
		return

	active_mission = mission
	_progress.clear()
	_completed.clear()
	_finished = false

	for objective in mission.objectives:
		if objective == null:
			continue
		_progress[objective.id] = 0
		_completed[objective.id] = false

	mission_started.emit(mission)

	var first := get_active_objective()
	if first != null:
		objective_activated.emit(first)
	tracked_objective_changed.emit(_resolve_tracked_objective())


## Setzt den gesamten Missionszustand zurueck.
func reset() -> void:
	active_mission = null
	_progress.clear()
	_completed.clear()
	_finished = false
	tracked_objective_changed.emit(null)


# --- Fortschrittsmeldung --------------------------------------------------

## Einziger Eingang fuer Fortschritt aus der Welt.
## Meldungen fuer noch gesperrte oder bereits erfuellte Ziele werden ignoriert.
func report(objective_id: StringName, amount: int = 1) -> void:
	if active_mission == null or _finished or amount <= 0:
		return

	var objective := active_mission.get_objective(objective_id)
	if objective == null:
		push_warning("MissionManager: unbekanntes Ziel '%s'." % objective_id)
		return
	if _completed.get(objective_id, false):
		return
	if not _accepts_report(objective):
		return

	var current: int = int(_progress.get(objective_id, 0)) + amount
	current = mini(current, objective.required_count)
	_progress[objective_id] = current
	objective_progress_changed.emit(objective, current, objective.required_count)

	if current < objective.required_count:
		return

	_completed[objective_id] = true
	objective_completed.emit(objective)

	if _all_required_complete():
		_finished = true
		tracked_objective_changed.emit(null)
		mission_completed.emit(active_mission)
		return

	var next := get_active_objective()
	if next != null:
		objective_activated.emit(next)
	tracked_objective_changed.emit(_resolve_tracked_objective())


# --- Abfragen -------------------------------------------------------------

## Das aktuell zu erfuellende Ziel, oder null wenn die Mission fertig ist.
func get_active_objective() -> MissionObjective:
	if active_mission == null or _finished:
		return null
	for objective in active_mission.objectives:
		if objective != null and not _completed.get(objective.id, false):
			return objective
	return null


## Alle Ziele der laufenden Mission in Anzeigereihenfolge.
func get_objectives() -> Array[MissionObjective]:
	if active_mission == null:
		return []
	return active_mission.objectives


func get_objective_state(objective_id: StringName) -> State:
	if _completed.get(objective_id, false):
		return State.DONE
	var active := get_active_objective()
	if active != null and active.id == objective_id:
		return State.ACTIVE
	if active_mission != null and not active_mission.sequential:
		return State.ACTIVE
	return State.PENDING


func get_progress(objective_id: StringName) -> int:
	return int(_progress.get(objective_id, 0))


func is_objective_active(objective_id: StringName) -> bool:
	return get_objective_state(objective_id) == State.ACTIVE


func is_objective_complete(objective_id: StringName) -> bool:
	return bool(_completed.get(objective_id, false))


func is_mission_finished() -> bool:
	return _finished


# --- Intern ---------------------------------------------------------------

## Nimmt dieses Ziel gerade Meldungen an? Bei sequentiellen Missionen nur das
## aktive Ziel, sonst jedes noch offene.
func _accepts_report(objective: MissionObjective) -> bool:
	if not active_mission.sequential:
		return true
	var active := get_active_objective()
	return active != null and active.id == objective.id


func _all_required_complete() -> bool:
	for objective in active_mission.objectives:
		if objective == null or objective.optional:
			continue
		if not _completed.get(objective.id, false):
			return false
	return true


## Das Ziel, auf das der Wegpunkt zeigt -- nur wenn es einen Marker will.
func _resolve_tracked_objective() -> MissionObjective:
	var objective := get_active_objective()
	if objective != null and objective.show_waypoint:
		return objective
	return null
