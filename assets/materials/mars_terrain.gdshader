shader_type spatial;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Visualize world Z as brightness: range -30 to +30
    float t = clamp((world_pos.z + 30.0) / 60.0, 0.0, 1.0);
    ALBEDO = vec3(t);
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}
