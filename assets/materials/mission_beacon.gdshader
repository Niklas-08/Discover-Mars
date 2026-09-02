shader_type spatial;
// Lichtsaeule fuer Missions-Wegpunkte.
//
// Unbeleuchtet und additiv, damit die Saeule auch bei Marsdunst und bei Nacht
// lesbar bleibt. Sie blendet nach oben aus und wird an den Silhouettenraendern
// heller (Fresnel), was ihr das typische Volumenlicht-Aussehen gibt.

render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beacon_color : source_color = vec4(0.42, 0.80, 0.92, 1.0);
// Hoehe der Saeule in Metern; steuert das Ausblenden nach oben.
uniform float fade_height = 60.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.25;
// Staerke des Randleuchtens.
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.2;
// Geschwindigkeit der nach oben laufenden Energiebaender.
uniform float scroll_speed = 0.65;
uniform float band_density = 3.0;
// Wird vom MissionWaypoint gesetzt: blendet die Saeule aus, sobald der Spieler
// nah genug ist. Ohne das umhuellt die Saeule am Ziel die Kamera und legt sich
// als grosse helle Flaeche ueber das Bild.
uniform float proximity_fade : hint_range(0.0, 1.0) = 1.0;

varying float v_local_height;

void vertex() {
	v_local_height = VERTEX.y;
}

void fragment() {
	// 0 am Fuss der Saeule, 1 an der Spitze.
	float h = clamp(v_local_height / max(fade_height, 0.001) + 0.5, 0.0, 1.0);

	// Nach oben ausblenden, unten kraeftig.
	float vertical_fade = pow(1.0 - h, 1.6);

	// Zu den Silhouettenraendern hin heller.
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Langsam nach oben wandernde Baender.
	float bands = 0.75 + 0.25 * sin((h * band_density - TIME * scroll_speed) * TAU);

	float alpha = vertical_fade * (0.25 + fresnel * 0.9) * bands * proximity_fade;

	ALBEDO = beacon_color.rgb * intensity * alpha;
	ALPHA = alpha;
}
