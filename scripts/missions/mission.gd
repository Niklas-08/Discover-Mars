@tool
class_name Mission
extends Resource
## Eine Mission: Kopfdaten plus eine geordnete Liste von Zielen.
##
## Reine Datenklasse ohne Laufzeitzustand. Missionen koennen im Code gebaut
## werden (siehe MissionLibrary) oder als .tres im Inspector angelegt werden.

@export_category("Identitaet")
## Eindeutige Missions-ID.
@export var id: StringName = &""
## Kurzkennung im HUD-Kopf, z. B. "MSL-01".
@export var codename: String = ""
## Anzeigename, z. B. "Pahrump Hills".
@export var title: String = ""

@export_category("Texte")
## Auftragsbeschreibung zu Missionsbeginn.
@export_multiline var briefing: String = ""
## Wissenschaftliche Auswertung nach Abschluss.
@export_multiline var debrief: String = ""

@export_category("Ablauf")
## True: Ziele werden nacheinander freigeschaltet. False: alle sofort aktiv.
@export var sequential: bool = true
@export var objectives: Array[MissionObjective] = []


## Liefert das Ziel mit dieser ID oder null.
func get_objective(objective_id: StringName) -> MissionObjective:
	for objective in objectives:
		if objective != null and objective.id == objective_id:
			return objective
	return null


## Anzahl der Ziele, die fuer den Missionsabschluss noetig sind.
func get_required_objective_count() -> int:
	var total := 0
	for objective in objectives:
		if objective != null and not objective.optional:
			total += 1
	return total
