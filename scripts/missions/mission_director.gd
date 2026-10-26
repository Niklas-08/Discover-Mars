extends Node
## Startet die Kampagne und fuehrt durch die Missionen.
##
## Der MissionManager ist ein Autoload und laeuft daher, bevor die Hauptszene
## existiert. Er darf sich deshalb nicht selbst starten. Dieser Knoten sitzt in
## der Szene und uebergibt dem Manager die passende Mission, sobald der
## Szenenbaum vollstaendig aufgebaut ist.
##
## Ablauf:
##   Missionsstart       -> Briefing im Info-Fenster
##   Missionsabschluss   -> Debriefing im Info-Fenster; nach dem Schliessen
##                          startet automatisch die naechste Mission
##   letzte Mission      -> Abschlussbildschirm (Spiel beenden / frei spielen)
##
## Das Info-Fenster arbeitet eine Warteschlange ab. Dadurch erscheinen z. B.
## Analyse -> Debriefing -> naechstes Briefing sauber nacheinander.

## Zu startende Mission. Leer = erste Mission der Kampagne.
@export var mission_id: StringName = &""
## Ob die Mission beim Szenenstart automatisch beginnt.
@export var autostart: bool = true
## Verzoegerung in Sekunden, damit HUD und Wegpunkte den Start sicher hoeren.
@export var start_delay: float = 0.1
## Nach Abschluss automatisch die naechste Mission starten.
@export var chain_missions: bool = true

const END_TITLE := "Alle Missionen abgeschlossen"
const END_TEXT := "Herzlichen Glückwunsch! Du hast alle drei Missionen erfolgreich abgeschlossen.\nDeine Untersuchungen zeigen: Der frühe Mars bot zumindest zeitweise lebensfreundliche Bedingungen – Wasser, die chemischen Bausteine des Lebens und Energiequellen. Ob dort tatsächlich Leben existierte, ist bis heute nicht bewiesen. Die Suche geht weiter."

var _overlay: Node = null
## Debriefing-Tag -> naechste Mission (oder null), wartet auf das Schliessen.
var _pending: Dictionary = {}


func _ready() -> void:
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.mission_completed.connect(_on_mission_completed)
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


func _get_overlay() -> Node:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = get_tree().get_first_node_in_group(&"info_overlay")
		if _overlay and not _overlay.entry_closed.is_connected(_on_overlay_entry_closed):
			_overlay.entry_closed.connect(_on_overlay_entry_closed)
	return _overlay


# --- Briefing / Debriefing ------------------------------------------------

func _on_mission_started(mission: Mission) -> void:
	var overlay := _get_overlay()
	if overlay == null or mission.briefing.is_empty():
		return
	overlay.show_text("%s  ·  Missionsbriefing" % mission.codename, mission.title, mission.briefing)


func _on_mission_completed(mission: Mission) -> void:
	var overlay := _get_overlay()
	var next := MissionLibrary.get_next(mission.id) if chain_missions else null

	if mission.debrief.is_empty():
		_after_debrief(mission, next)
		return
	if overlay == null:
		_after_debrief(mission, next)
		return

	var tag := StringName("debrief_%s" % mission.id)
	# Erst nach dem Schliessen des Debriefings geht es weiter.
	_pending[tag] = next
	overlay.show_text("%s  ·  Mission abgeschlossen" % mission.codename, mission.title, mission.debrief, null, tag)


func _on_overlay_entry_closed(tag: StringName) -> void:
	if not _pending.has(tag):
		return
	var next: Mission = _pending[tag]
	_pending.erase(tag)
	_after_debrief(null, next)


func _after_debrief(_mission: Mission, next: Mission) -> void:
	if next != null:
		MissionManager.start_mission(next)
	elif chain_missions:
		_show_end_screen()


# --- Abschluss ------------------------------------------------------------

func _show_end_screen() -> void:
	var overlay := _get_overlay()
	if overlay == null:
		return
	overlay.show_choice("", END_TITLE, END_TEXT, [
		["Spiel beenden", func() -> void: get_tree().quit()],
		["Frei weiterspielen", _free_play],
	])


## Freies Spiel: keine aktive Mission, Missionspanel ausgeblendet.
func _free_play() -> void:
	MissionManager.reset()
	var hud := get_tree().get_first_node_in_group(&"mission_hud")
	if hud and hud.has_method("hide_panel"):
		hud.hide_panel()
