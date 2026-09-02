@tool
class_name MissionObjective
extends Resource
## Ein einzelnes Missionsziel.
##
## Reine Datenklasse. Enthaelt keine Laufzeitlogik und keinen Fortschritt --
## der Fortschritt liegt ausschliesslich im MissionManager (Autoload), damit
## dieselbe Resource gefahrlos von mehreren Stellen gelesen werden kann.

## Art des Ziels. Bestimmt nur das Icon und die Standardformulierung;
## ausgeloest wird jedes Ziel ueber MissionManager.report(id).
enum Kind {
	TRAVEL,   ## Einen Ort erreichen (MissionWaypoint mit Area3D).
	INTERACT, ## Mit etwas interagieren (z. B. Rover besteigen).
	COLLECT,  ## Eine Probe entnehmen.
	PHOTO,    ## Eine Formation fotografieren.
	SCAN,     ## Ein Instrument einsetzen / Messung durchfuehren.
}

@export_category("Identitaet")
## Eindeutige ID. Wird von der Welt an MissionManager.report() uebergeben.
@export var id: StringName = &""
## Kurzer Imperativ fuer die HUD-Zeile, z. B. "Gesteinsprobe entnehmen".
@export var title: String = ""
## Optionaler laengerer Text (Briefing, Tooltip). Aktuell nicht im HUD.
@export_multiline var description: String = ""

@export_category("Verhalten")
@export var kind: Kind = Kind.TRAVEL
## Wie oft report() aufgerufen werden muss, bis das Ziel erfuellt ist.
@export_range(1, 99, 1) var required_count: int = 1
## Optionale Ziele blockieren den Missionsfortschritt nicht.
@export var optional: bool = false

@export_category("Zielort")
## Gruppe des Weltknotens, der dieses Ziel erfuellt (z. B. &"rover").
## Ein MissionWaypoint mit follow_group heftet sich daran und folgt ihm live.
@export var target_group: StringName = &""
## Alternativ: fester Pfad innerhalb der Szene.
@export var target_path: NodePath = NodePath()
## Versatz auf den Zielpunkt, z. B. um den Marker ueber das Objekt zu heben.
@export var waypoint_offset: Vector3 = Vector3.ZERO
## Radius (Meter), in dem ein TRAVEL-Ziel als erreicht gilt.
@export var arrival_radius: float = 12.0
## Ob fuer dieses Ziel ein Wegpunkt-Marker angezeigt wird.
@export var show_waypoint: bool = true


## Symbolischer Icon-Name fuer dieses Ziel, aufgeloest vom HUD.
func get_type_icon_name() -> String:
	match kind:
		Kind.TRAVEL: return "type_travel"
		Kind.INTERACT: return "type_board"
		Kind.COLLECT: return "type_sample"
		Kind.PHOTO: return "type_photo"
		Kind.SCAN: return "type_scan"
	return "type_travel"


## True, wenn das Ziel einen Zaehler im HUD anzeigen soll ("2/3").
func has_counter() -> bool:
	return required_count > 1
