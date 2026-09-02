class_name MissionLibrary
extends RefCounted
## Sammlung aller im Spiel verfuegbaren Missionen.
##
## Missionen werden hier im Code gebaut statt als .tres-Dateien: das haelt sie
## in Git lesbar und diffbar. Da Mission und MissionObjective echte Resource-
## Klassen sind, koennen spaetere Missionen bei Bedarf trotzdem als .tres im
## Inspector angelegt und hier nur noch geladen werden.


## Alle Missionen in Kampagnenreihenfolge.
static func get_all() -> Array[Mission]:
	return [msl_01_pahrump_hills()]


## Liefert die Mission mit dieser ID oder null.
static func get_by_id(mission_id: StringName) -> Mission:
	for mission in get_all():
		if mission.id == mission_id:
			return mission
	return null


## Die erste Mission der Kampagne.
static func get_first() -> Mission:
	return msl_01_pahrump_hills()


## MSL-01 -- Pahrump Hills.
##
## Nachempfunden dem realen "Pahrump Hills Walkabout" des Rovers Curiosity
## (Mars Science Laboratory). Curiosity erreichte den Aufschluss um Sol 753
## (September 2014) am Fuss des Mount Sharp (Aeolis Mons) und bohrte dort das
## Ziel "Confidence Hills" an. Das Gestein gehoert zur Murray-Formation und
## wird als feinkoerniger Schlammstein gedeutet -- abgelagert in einem
## langlebigen See im Gale-Krater.
##
## Quellen:
##   Grotzinger et al. (2015), "Deposition, exhumation, and paleoclimate of an
##   ancient lake deposit, Gale crater, Mars", Science 350 (6257).
##   NASA/JPL-Caltech, MSL Mission Updates, Sol 753-800.
static func msl_01_pahrump_hills() -> Mission:
	var mission := Mission.new()
	mission.id = &"msl_01"
	mission.codename = "MSL-01"
	mission.title = "Pahrump Hills"
	mission.briefing = "Erreiche mit dem Erkundungsfahrzeug den Aufschluss der Pahrump Hills am Fuss des Mount Sharp und entnimm eine Gesteinsprobe der untersten Schicht (Confidence Hills)."
	mission.debrief = "Curiosity fand hier feinkoernigen Schlammstein - Ablagerungen eines antiken Sees im Gale-Krater."
	mission.sequential = true

	var board := MissionObjective.new()
	board.id = &"board_rover"
	board.title = "Erkundungsfahrzeug besteigen"
	board.description = "Naehere dich dem Rover und steige mit [F] ein."
	board.kind = MissionObjective.Kind.INTERACT
	board.target_group = &"rover"
	board.waypoint_offset = Vector3(0.0, 2.6, 0.0)
	board.arrival_radius = 6.0
	board.show_waypoint = true

	var drive := MissionObjective.new()
	drive.id = &"drive_to_pahrump"
	drive.title = "Zum Aufschluss Pahrump Hills fahren"
	drive.description = "Der Aufschluss liegt rund 300 Meter noerdlich der Landestelle."
	drive.kind = MissionObjective.Kind.TRAVEL
	drive.arrival_radius = 25.0
	drive.show_waypoint = true

	var sample := MissionObjective.new()
	sample.id = &"collect_sample"
	sample.title = "Gesteinsprobe entnehmen"
	sample.description = "Steige aus und entnimm mit [F] eine Probe des markierten Gesteins."
	sample.kind = MissionObjective.Kind.COLLECT
	sample.arrival_radius = 4.0
	sample.show_waypoint = true

	mission.objectives = [board, drive, sample]
	return mission
