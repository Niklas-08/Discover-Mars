extends Node3D

var lights_enabled: bool = false

@onready var rover: VehicleBody3D = get_parent()

# Pro Leuchtkörper-Material: Material, eigene Emissionsfarbe und -stärke
var bulb_materials: Array[Dictionary] = []

# Ursprüngliche Lichtstärke der Spotlights
var lamp_energies: Dictionary = {}

# Kleine Punktlichter, die die Umgebung der Leuchtkörper beleuchten
var bulb_lights: Array[OmniLight3D] = []

@export var bulb_light_energy: float = 1.0
# Hintere Punktlichter (RL/RR) dunkler: ein Drittel der normalen Helligkeit
@export var rear_bulb_light_energy: float = 1.0 / 3.0
@export var bulb_light_range: float = 1.5


func _ready() -> void:
	for lamp in get_children():
		if lamp is SpotLight3D:
			lamp_energies[lamp] = lamp.light_energy

	# rover.gd setzt in seinem _ready() (läuft nach diesem) das Hüllenmaterial
	# als material_override auf alle Meshes – auch auf die Leuchtkörper.
	# Deshalb erst danach einrichten.
	_setup_bulbs.call_deferred()


func _setup_bulbs() -> void:
	for lamp in lamp_energies:
		for bulb in lamp.get_children():
			if not bulb is MeshInstance3D:
				continue

			if bulb.mesh == null:
				continue

			# Hüllenmaterial vom Rover entfernen, damit das eigene Material greift
			bulb.material_override = null

			for surface in range(bulb.mesh.get_surface_count()):
				var material: Material = bulb.get_surface_override_material(surface)
				if material == null:
					material = bulb.mesh.surface_get_material(surface)

				if material is StandardMaterial3D:
					# Eigene Kopie, damit sich nicht alle Bulbs ein Material teilen
					var unique_material: StandardMaterial3D = material.duplicate()
					bulb.set_surface_override_material(surface, unique_material)

					# Die im Material eingestellte Farbe und Stärke merken
					var color: Color = unique_material.emission

					bulb_materials.append({
						"material": unique_material,
						"emission": color,
						"energy": unique_material.emission_energy_multiplier
					})

					_add_bulb_light(lamp, bulb, color)

	update_lights()


func _add_bulb_light(lamp: Node3D, bulb: MeshInstance3D, color: Color) -> void:
	# Als Geschwister des Bulbs, da dessen Skalierung (0.1) sonst die Lichtreichweite verfälscht
	var light := OmniLight3D.new()
	light.name = bulb.name + "_glow"
	light.position = bulb.position

	# Vorne (FL/FR) nach +Z, hinten (RL/RR) nach -Z versetzen
	if lamp.name.begins_with("front"):
		light.position.z -= 1.5
	elif lamp.name.begins_with("rear"):
		light.position.y += 0.5
		light.position.z -= 1
	light.light_color = color
	light.light_energy = bulb_light_energy
	if lamp.name.begins_with("rear"):
		light.light_energy = rear_bulb_light_energy
	light.omni_range = bulb_light_range
	light.shadow_enabled = false
	lamp.add_child(light)
	bulb_lights.append(light)


func _process(_delta: float) -> void:
	# Lichtzustand beim Aussteigen beibehalten
	if not rover.driver_aboard:
		return

	if Input.is_action_just_pressed("flashlight_switch"):
		lights_enabled = not lights_enabled
		update_lights()


func update_lights() -> void:
	# Spotlights per Lichtstärke schalten. Die Sichtbarkeit bleibt unverändert,
	# da die Leuchtkörper Kinder der Spotlights sind und sonst mit verschwinden würden.
	for lamp in lamp_energies:
		lamp.light_energy = lamp_energies[lamp] if lights_enabled else 0.0

	for light in bulb_lights:
		light.visible = lights_enabled

	# Leuchtkörper bleiben sichtbar, nur die Emission wird geschaltet
	for entry in bulb_materials:
		var material: StandardMaterial3D = entry["material"]
		var color: Color = entry["emission"]
		material.emission_enabled = lights_enabled

		# Ausgeschaltet: abgedunkelte Eigenfarbe statt des weißen Standard-Albedos
		material.albedo_color = color if lights_enabled else color.darkened(0.7)

		if lights_enabled:
			material.emission = color
			material.emission_energy_multiplier = entry["energy"]
