class_name MissionLibrary
extends RefCounted
## Sammlung aller im Spiel verfuegbaren Missionen.
##
## Missionen werden hier im Code gebaut statt als .tres-Dateien: das haelt sie
## in Git lesbar und diffbar. Da Mission und MissionObjective echte Resource-
## Klassen sind, koennen spaetere Missionen bei Bedarf trotzdem als .tres im
## Inspector angelegt und hier nur noch geladen werden.
##
## Die Weltseite jeder Mission (Wegpunkte, Interaktionen, Probenzonen) liegt
## unter /MissionWorld in main.tscn und ist ueber die Ziel-IDs verknuepft.
## Nebenwirkungen einzelner Ziele (Fracht, Einblendungen) uebernimmt
## mission_story.gd, den Kampagnenablauf mission_director.gd.


## Alle Missionen in Kampagnenreihenfolge.
static func get_all() -> Array[Mission]:
	return [msn_01_signal_aus_dem_orbit(), msn_02_see_im_gale_krater(), msn_03_spuren_im_gestein()]


## Liefert die Mission mit dieser ID oder null.
static func get_by_id(mission_id: StringName) -> Mission:
	for mission in get_all():
		if mission.id == mission_id:
			return mission
	return null


## Die erste Mission der Kampagne.
static func get_first() -> Mission:
	return get_all()[0]


## Die Mission nach dieser, oder null nach der letzten.
static func get_next(mission_id: StringName) -> Mission:
	var all := get_all()
	for i in all.size() - 1:
		if all[i].id == mission_id:
			return all[i + 1]
	return null


# --- Bausteine ------------------------------------------------------------

static func _objective(id: StringName, title: String, kind: MissionObjective.Kind,
		description: String = "", arrival_radius: float = 12.0) -> MissionObjective:
	var o := MissionObjective.new()
	o.id = id
	o.title = title
	o.kind = kind
	o.description = description
	o.arrival_radius = arrival_radius
	o.show_waypoint = true
	return o


# --- MSN-01 ---------------------------------------------------------------

static func msn_01_signal_aus_dem_orbit() -> Mission:
	var m := Mission.new()
	m.id = &"msn_01"
	m.codename = "MSN-01"
	m.title = "Signal aus dem Orbit"
	m.sequential = true
	m.briefing = "Ein Orbiter ist auf dem Mars abgestürzt: MAVEN, eine Sonde, die untersucht hat, wie der Mars seine Atmosphäre verliert. Ihre Speicherkarte enthält möglicherweise wichtige Aufnahmen. Fahre mit dem Mars Exploration Vehicle zur Absturzstelle und birg die Speicherkarte."
	m.debrief = "Mission abgeschlossen. Das Satellitenbild zeigt den Gale-Krater – dein nächstes Ziel."

	var board := _objective(&"board_vehicle", "Steige in das Mars Exploration Vehicle",
		MissionObjective.Kind.INTERACT, "Nähere dich dem Fahrzeug und steige mit [F] ein.", 6.0)
	board.target_group = &"rover"

	var reach := _objective(&"reach_maven", "Fahre zum abgestürzten Satelliten MAVEN",
		MissionObjective.Kind.TRAVEL, "", 25.0)
	reach.target_path = ^"/root/main/MAVEN"

	var card := _objective(&"retrieve_card", "Entnimm die Speicherkarte",
		MissionObjective.Kind.INTERACT, "Steige aus und entnimm die Speicherkarte mit [F].")
	card.target_path = ^"/root/main/MAVEN"

	var back := _objective(&"return_to_habitat", "Bringe die Speicherkarte zur Habitat Demonstration Unit",
		MissionObjective.Kind.TRAVEL, "", 20.0)
	back.target_path = ^"/root/main/HabitatDemonstrationUnit"

	var view := _objective(&"view_picture", "Sieh dir das Satellitenbild an",
		MissionObjective.Kind.INTERACT, "Steige aus und öffne das Satellitenbild mit [F].")
	view.target_path = ^"/root/main/HabitatDemonstrationUnit"

	m.objectives = [board, reach, card, back, view]
	return m


# --- MSN-02 ---------------------------------------------------------------

static func msn_02_see_im_gale_krater() -> Mission:
	var m := Mission.new()
	m.id = &"msn_02"
	m.codename = "MSN-02"
	m.title = "Der See im Gale-Krater"
	m.sequential = true
	m.briefing = "Am Grund des Gale-Kraters lag vor Milliarden Jahren ein See. Steuere den Rover Perseverance (Taste R) in den Krater und entnimm eine Gesteinsprobe."
	m.debrief = "Mission abgeschlossen. Der Gale-Krater war einst habitabel. Doch für Spuren von Leben braucht es weitere Hinweise."

	var control := _objective(&"control_rover", "Übernimm die Steuerung von Perseverance [R]",
		MissionObjective.Kind.INTERACT)
	control.target_group = &"perseverance"

	var reach := _objective(&"reach_gale", "Fahre zum Gale-Krater",
		MissionObjective.Kind.TRAVEL, "", 20.0)
	reach.target_path = ^"/root/main/Surface/MarsGaleCrater"

	var sample := _objective(&"take_rock_sample", "Entnimm eine Gesteinsprobe",
		MissionObjective.Kind.COLLECT, "Fahre an die markierte Stelle und entnimm die Probe mit [F].")
	sample.target_group = &"perseverance"

	var back := _objective(&"return_rock", "Bringe die Probe zur Habitat Demonstration Unit",
		MissionObjective.Kind.TRAVEL, "", 20.0)
	back.target_path = ^"/root/main/HabitatDemonstrationUnit"

	var analyze := _objective(&"analyze_rock", "Analysiere die Gesteinsprobe",
		MissionObjective.Kind.SCAN, "Starte die Analyse mit [F].")
	analyze.target_path = ^"/root/main/HabitatDemonstrationUnit"

	m.objectives = [control, reach, sample, back, analyze]
	return m


# --- MSN-03 ---------------------------------------------------------------

static func msn_03_spuren_im_gestein() -> Mission:
	var m := Mission.new()
	m.id = &"msn_03"
	m.codename = "MSN-03"
	m.title = "Spuren im Gestein"
	m.sequential = true
	m.briefing = "Satelliten im Orbit haben in der Nähe ein Hügelgebiet entdeckt, in dem Sedimentgestein aus Ton und Schluff freiliegt. Steuere Perseverance zu den Pahrump Hills und nimm eine Bodenprobe."
	m.debrief = ""   # Kein Debrief: direkt zum Abschlussbildschirm.

	var reach := _objective(&"reach_pahrump", "Fahre zu den Pahrump Hills",
		MissionObjective.Kind.TRAVEL, "", 20.0)
	reach.target_path = ^"/root/main/Surface/PahrumpHills2"

	var sample := _objective(&"take_soil_sample", "Entnimm eine Bodenprobe",
		MissionObjective.Kind.COLLECT, "Fahre an die markierte Stelle und entnimm die Probe mit [F].")
	sample.target_group = &"perseverance"

	var back := _objective(&"return_soil", "Bringe die Probe zur Habitat Demonstration Unit",
		MissionObjective.Kind.TRAVEL, "", 20.0)
	back.target_path = ^"/root/main/HabitatDemonstrationUnit"

	var analyze := _objective(&"analyze_soil", "Analysiere die Bodenprobe",
		MissionObjective.Kind.SCAN, "Starte die Analyse mit [F].")
	analyze.target_path = ^"/root/main/HabitatDemonstrationUnit"

	m.objectives = [reach, sample, back, analyze]
	return m
