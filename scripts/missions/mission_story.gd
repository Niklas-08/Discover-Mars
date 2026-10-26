extends Node3D
## Nebenwirkungen einzelner Missionsziele.
##
## Die Weltknoten melden nur Fortschritt (MissionManager.report). Was danach
## passiert -- Fracht setzen/verbrauchen, Meldung zeigen, Satellitenbild oder
## Analyse im Info-Fenster oeffnen -- steht gesammelt hier, damit die
## wiederverwendbaren Bausteine (Wegpunkt, Interaktion, Roverzone) keine
## Missionsinhalte kennen muessen.

const MARS_MAP := "res://assets/ui/pictures/Mars-Satellite-picture.png"


func _ready() -> void:
	MissionManager.objective_completed.connect(_on_objective_completed)
	MissionManager.objective_activated.connect(_on_objective_activated)


func _overlay() -> Node:
	return get_tree().get_first_node_in_group(&"info_overlay")


func _hud() -> Node:
	return get_tree().get_first_node_in_group(&"mission_hud")


# --- Ziel aktiviert -------------------------------------------------------

## Ist die Bedingung beim Freischalten schon erfuellt (Spieler sitzt bereits
## im Fahrzeug / steuert Perseverance bereits), feuert das ausloesende Signal
## nicht mehr -- dann hier direkt melden.
func _on_objective_activated(objective: MissionObjective) -> void:
	match objective.id:
		&"board_vehicle":
			var player := get_tree().get_first_node_in_group(&"player")
			if player and player.get(&"in_rover"):
				MissionManager.report(objective.id)
		&"control_rover":
			var rover := get_tree().get_first_node_in_group(&"perseverance")
			if rover and rover.get(&"controlled"):
				MissionManager.report(objective.id)


# --- Ziel erfuellt --------------------------------------------------------

func _on_objective_completed(objective: MissionObjective) -> void:
	match objective.id:
		&"retrieve_card":
			MissionManager.set_flag(&"has_memory_card", true)
			var hud := _hud()
			if hud and hud.has_method("show_toast"):
				hud.show_toast("Speicherkarte geborgen.")
		&"view_picture":
			MissionManager.set_flag(&"has_memory_card", false)
			_show_satellite_picture()
		&"take_rock_sample":
			MissionManager.set_flag(&"has_rock_sample", true)
		&"analyze_rock":
			MissionManager.set_flag(&"has_rock_sample", false)
			_show_rock_analysis()
		&"take_soil_sample":
			MissionManager.set_flag(&"has_soil_sample", true)
		&"analyze_soil":
			MissionManager.set_flag(&"has_soil_sample", false)
			_show_soil_analysis()


# --- Inhalte --------------------------------------------------------------

func _show_satellite_picture() -> void:
	var overlay := _overlay()
	if overlay == null:
		return
	var tex: Texture2D = load(MARS_MAP) if ResourceLoader.exists(MARS_MAP) else null
	overlay.show_text("MSN-01  ·  Speicherkarte", "MAVEN – Satellitenaufnahme",
		"Die Aufnahme zeigt einen großen Einschlagskrater: den Gale-Krater. Spuren an seinem Boden deuten darauf hin, dass hier vor Milliarden Jahren Wasser floss und ein See existierte. Wenn es auf dem frühen Mars Leben gab, wäre dies ein vielversprechender Ort, um danach zu suchen.",
		tex)


static func _list(items: Array) -> String:
	var lines := PackedStringArray()
	for item in items:
		lines.append("[color=#7DD3FA]–[/color]  " + item)
	return "\n".join(lines)


func _show_rock_analysis() -> void:
	var overlay := _overlay()
	if overlay == null:
		return
	var source := "Datenquelle: NASA-Mission Curiosity (Mars Science Laboratory), Landung 2012 im Gale-Krater"
	overlay.show_pages([
		{
			"eyebrow": source,
			"title": "Messdaten – Gesteinsprobe (feinkörniger Tonstein)",
			"body": _list([
				"[b]Probe:[/b] Bohrpulver aus feinkörnigem Tonstein nahe einem ehemaligen Flussbett",
				"[b]Nachgewiesene Elemente:[/b] Schwefel (S), Stickstoff (N), Wasserstoff (H), Sauerstoff (O), Phosphor (P), Kohlenstoff (C)",
				"[b]Tonminerale:[/b] mindestens 20 % der Probe",
				"[b]Calciumsulfat:[/b] vorhanden → Milieu neutral bis leicht basisch",
				"[b]Oxidationsstufen:[/b] oxidierte, schwach oxidierte und nicht oxidierte Verbindungen (z. B. Sulfate und Sulfide)",
				"[b]Organische Moleküle[/b] (in ca. 3 Mrd. Jahre altem Tonstein vom Seegrund): Thiophene, Benzol, Toluol, kurze Kohlenstoffketten (z. B. Propan, Buten)",
				"[b]Gehalt an organischem Kohlenstoff:[/b] ca. 10 ppm oder mehr (rund 100-mal mehr als frühere Messungen an der Oberfläche)",
				"[b]Atmosphäre:[/b] Methan, das jahreszeitlich schwankt (Maximum im Sommer, Minimum im Winter)",
			]),
		},
		{
			"eyebrow": source,
			"title": "Auswertung – Bedeutung für mögliches früheres Leben",
			"body": "Die Probe enthält alle wichtigen chemischen Bausteine des Lebens. Die Tonminerale entstehen, wenn relativ süßes Wasser mit vulkanischen Mineralen reagiert. Das Calciumsulfat zeigt, dass das Wasser weder stark sauer noch stark salzig war. Die Mischung aus oxidierten und nicht oxidierten Stoffen bildet ein chemisches Energiegefälle, das viele Mikroorganismen auf der Erde zum Leben nutzen.\n\nDamit war der Gale-Krater früher eine habitable Umgebung: Wasser, Bioelemente und Energiequellen waren gleichzeitig vorhanden.\n\nDie organischen Moleküle zeigen, dass sich solche Stoffe über Milliarden Jahre im Gestein erhalten können. Sie sind aber kein Beweis für Leben, denn sie können auch ohne Leben entstehen, zum Beispiel durch Meteoriten. Auch das Methan könnte durch Reaktionen zwischen Wasser und Gestein entstanden sein; eine biologische Herkunft ist jedoch nicht ausgeschlossen.\n\n[color=#7DD3FA][b]Fazit:[/b][/color] Der Gale-Krater war lebensfreundlich – ob dort tatsächlich Leben existierte, bleibt offen.",
		},
	])


func _show_soil_analysis() -> void:
	var overlay := _overlay()
	if overlay == null:
		return
	var source := "Datenquelle: NASA-Mission Perseverance (Mars 2020), Landung 2021 im Jezero-Krater – Gestein „Cheyava Falls“"
	overlay.show_pages([
		{
			"eyebrow": source,
			"title": "Messdaten – Bodenprobe (Sedimentgestein)",
			"body": _list([
				"[b]Gestein:[/b] Ton und Schluff (Sedimentgestein eines ehemaligen Flusstals)",
				"[b]Enthalten:[/b] organischer Kohlenstoff, Schwefel, oxidiertes Eisen (Rost), Phosphor",
				"[b]Auffälligkeit:[/b] kleine helle Flecken mit dunklem Rand („Leopardenflecken“) = Reaktionsfronten",
				"[b]Mineral 1:[/b] Vivianit (wasserhaltiges Eisenphosphat)",
				"[b]Mineral 2:[/b] Greigit (Eisensulfid)",
				"Keine Hinweise auf hohe Temperaturen oder saure Bedingungen im Gestein",
				"[b]Alter:[/b] vergleichsweise junges Sedimentgestein",
			]),
		},
		{
			"eyebrow": source,
			"title": "Auswertung – Bedeutung für mögliches früheres Leben",
			"body": "Ton und Schluff sind auf der Erde besonders gut geeignet, um Spuren mikrobiellen Lebens zu erhalten. Vivianit kommt auf der Erde häufig in Sedimenten, Mooren und in der Nähe von zerfallender organischer Substanz vor. Greigit kann von bestimmten Mikroorganismen gebildet werden.\n\nDie Minerale sind vermutlich durch Reaktionen entstanden, bei denen Elektronen zwischen Sediment und organischer Substanz übertragen wurden – genau solche Reaktionen nutzen Mikroorganismen, um Energie zu gewinnen. Die NASA stuft den Fund deshalb als „potenzielle Biosignatur“ ein: ein Hinweis, der biologischen Ursprungs sein könnte, aber noch weitere Untersuchungen braucht.\n\nVivianit und Greigit können jedoch auch ohne Leben entstehen, etwa bei hohen Temperaturen oder unter sauren Bedingungen. Dafür gibt es hier zwar keine Hinweise, ganz ausschließen lässt sich eine nicht-biologische Entstehung aber nicht.\n\nDa das Gestein relativ jung ist, könnte der Mars außerdem länger habitabel gewesen sein als bisher angenommen.\n\n[color=#7DD3FA][b]Fazit:[/b][/color] Dies ist der bisher stärkste Hinweis auf mögliches früheres Leben – ein Beweis ist es nicht.",
		},
	])
