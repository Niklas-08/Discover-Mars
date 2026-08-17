shader_type spatial;
// Matte Martian regolith: sand + stone + settled dust.
// Deliberately non-reflective - specular is forced to 0 and roughness to ~1,
// so direct sunlight never produces a highlight.
render_mode diffuse_burley, specular_disabled;

// --- Texture inputs -------------------------------------------------------
uniform sampler2D dust_fine_tex  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex      : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal  : hint_normal,        filter_linear_mipmap, repeat_enable;

// --- Palette --------------------------------------------------------------
uniform vec3 sand_color  : source_color = vec3(0.478, 0.271, 0.161); // basalt sand
uniform vec3 stone_color : source_color = vec3(0.325, 0.196, 0.145); // darker bedrock
uniform vec3 dust_color  : source_color = vec3(0.643, 0.435, 0.298); // pale settled dust

// --- Surface scales (world units, so nothing stretches with UVs) ----------
uniform float macro_scale  : hint_range(0.001, 0.1)  = 0.006; // big patches
uniform float meso_scale   : hint_range(0.005, 0.5)  = 0.035; // mid variation
uniform float micro_scale  : hint_range(0.02,  2.0)  = 0.220; // grain
uniform float normal_scale : hint_range(0.02,  2.0)  = 0.180;

// --- Look controls --------------------------------------------------------
uniform float normal_strength : hint_range(0.0, 2.0) = 0.55;
uniform float stone_amount    : hint_range(0.0, 1.0) = 0.45; // how much bedrock shows
uniform float dust_amount     : hint_range(0.0, 1.0) = 0.65; // dust settled on flats
uniform float slope_bias      : hint_range(0.5, 8.0) = 3.0;  // slope -> stone falloff
uniform float grain_strength  : hint_range(0.0, 0.5) = 0.13; // fine speckle contrast
uniform float powder_scatter  : hint_range(0.0, 0.6) = 0.22; // grazing-angle dust glow
uniform float roughness_floor : hint_range(0.85, 1.0) = 0.97;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // Sample on the world ground plane so texel density is uniform and the
    // pattern never stretches across the terrain's UV seams.
    vec2 p = world_pos.xz;

    float macro = texture(dust_fine_tex, p * macro_scale).r;
    float meso  = texture(dust_fine_tex, p * meso_scale + vec2(0.37, 0.71)).r;
    float micro = texture(dust_fine_tex, p * micro_scale + vec2(0.13, 0.59)).r;

    float stone_lo = texture(stone_tex, p * meso_scale * 0.6).r;
    float stone_hi = texture(stone_tex, p * micro_scale * 0.5 + vec2(0.81, 0.24)).r;
    float stone_n  = mix(stone_lo, stone_hi, 0.4);

    // Three octaves combined -> large patches, mid mottling, fine grain.
    float variation = macro * 0.55 + meso * 0.30 + micro * 0.15;

    // Steep faces expose bedrock; flats collect sand and dust.
    float flatness = clamp(world_normal.y, 0.0, 1.0);
    float slope    = 1.0 - pow(flatness, slope_bias);

    // --- Base: sand <-> stone --------------------------------------------
    float stone_mix = clamp(slope * 1.2 + (stone_n - 0.5) * 1.1, 0.0, 1.0) * stone_amount;
    vec3 albedo = mix(sand_color, stone_color, stone_mix);

    // Large-scale tonal drift so the ground never looks flat-coloured.
    albedo *= 0.80 + variation * 0.45;

    // --- Dust settling ----------------------------------------------------
    // Dust lies thickest on horizontal surfaces and in sheltered patches.
    float dust_mask = pow(flatness, 1.6) * dust_amount;
    dust_mask *= 0.55 + macro * 0.75;                 // patchy, not uniform
    dust_mask = clamp(dust_mask, 0.0, 1.0);
    albedo = mix(albedo, dust_color, dust_mask * 0.7);

    // Fine speckle: individual grains catching light.
    albedo *= 1.0 + (micro - 0.5) * grain_strength * 2.0;

    // Dust slightly washes out saturation, like a haze of powder on top.
    float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
    albedo = mix(albedo, vec3(luma), dust_mask * 0.18);

    ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

    // --- Surface relief ---------------------------------------------------
    NORMAL_MAP = texture(detail_normal, p * normal_scale).rgb;
    NORMAL_MAP_DEPTH = normal_strength * (0.6 + dust_mask * 0.8);

    // --- Fully matte ------------------------------------------------------
    // Rough almost everywhere; dust is the roughest of all. Never below the
    // floor, so there is no glossy response to the sun.
    ROUGHNESS = clamp(roughness_floor + dust_mask * 0.03 - micro * 0.02, roughness_floor, 1.0);
    METALLIC  = 0.0;
    SPECULAR  = 0.0;

    // Powdery backscatter: fine dust scatters light at grazing angles instead
    // of reflecting it, which reads as a soft chalky sheen rather than a
    // specular hotspot.
    float grazing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    RIM = powder_scatter * dust_mask;
    RIM_TINT = 0.6;
    ALBEDO += dust_color * pow(grazing, 3.0) * powder_scatter * dust_mask * 0.25;

    // Slight cavity darkening where the coarse pattern dips.
    AO = clamp(0.75 + stone_n * 0.35, 0.0, 1.0);
    AO_LIGHT_AFFECT = 0.5;
}
