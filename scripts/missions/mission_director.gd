extends Node
## Startet die Mission fuer die aktuelle Szene.
##
## Der MissionManager ist ein Autoload und laeuft daher, bevor die Hauptszene
## existiert. Er darf sich deshalb nicht selbst starten. Dieser Knoten sitzt in
## der Szene und uebergibt dem Manager die passende Mission, sobald der
## Szenenbaum vollstaendig aufgebaut ist.

## Zu startende Mission. Leer = erste Mission der Kampagne.
@export var mission_id: StringName = &""
## Ob die Mission beim Szenenstart automatisch beginnt.
@export var autostart: bool = true
## Verzoegerung in Sekunden, damit HUD und Wegpunkte den Start sicher hoeren.
@export var start_delay: float = 0.1


func _ready() -> void:
	if not autostart:
		return
	# Erst nach einem Frame starten: Alle Hoerer (HUD, Wegpunkte) haben dann
	# ihre eigenen _ready() durchlaufen und sind mit den Signalen verbunden.
	await get_tree().process_frame
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	start()


## Startet die konfigurierte Mission.
func start() -> void:
	var mission: Mission = null
	if mission_id.is_empty():
		mission = MissionLibrary.get_first()
	else:
		mission = MissionLibrary.get_by_id(mission_id)

	if mission == null:
		push_warning("MissionDirector: Mission '%s' nicht gefunden." % mission_id)
		return

	MissionManager.start_mission(mission)
