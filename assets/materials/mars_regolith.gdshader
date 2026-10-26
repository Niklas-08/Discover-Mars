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

// --- Tile seam blending ---------------------------------------------------
// Per-tile height correction produced by tools/blend_seams.js and applied by
// terrain_collision.gd (which also applies the identical correction to the
// collision mesh). Off by default so the material is unchanged elsewhere.
uniform bool seam_enabled = false;
uniform sampler2D seam_delta : filter_linear, repeat_disable;
/// (min_x, min_z, size_x, size_z) of the correction grid in world space.
uniform vec4 seam_rect = vec4(0.0, 0.0, 1.0, 1.0);
/// Local edge expansion (scale_x, scale_y, centre_x, centre_y) in the mesh's
/// own plane - grows the tile a few metres so neighbours always overlap.
uniform vec4 seam_expand = vec4(1.0, 1.0, 0.0, 0.0);
/// Local box of the model (min_x, max_x, min_y, max_y). Its side walls and
/// underside are hidden: on tilted tiles they stick up as thin walls at seams.
uniform vec4 seam_bounds = vec4(-1e9, 1e9, -1e9, 1e9);

// 1.0 on side-wall / underside vertices; faces made only of these are discarded.
varying float box_wall;

void vertex() {
    box_wall = 0.0;
    if (seam_enabled) {
        // Model frame: Z is elevation. Side walls lie on the box planes with
        // horizontal normals; the underside points down.
        float eps = 0.001 * max(seam_bounds.y - seam_bounds.x, seam_bounds.w - seam_bounds.z);
        bool on_edge = VERTEX.x < seam_bounds.x + eps || VERTEX.x > seam_bounds.y - eps
                    || VERTEX.y < seam_bounds.z + eps || VERTEX.y > seam_bounds.w - eps;
        if ((on_edge && abs(NORMAL.z) < 0.5) || NORMAL.z < -0.5) {
            box_wall = 1.0;
        }
        VERTEX.xy = seam_expand.zw + (VERTEX.xy - seam_expand.zw) * seam_expand.xy;
    }
    world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

    if (seam_enabled) {
        vec2 uv = (world_pos.xz - seam_rect.xy) / seam_rect.zw;
        float d = textureLod(seam_delta, uv, 0.0).r;
        {
            // Move the vertex straight up/down in WORLD space, then express
            // that offset in the mesh's local space (handles the -90 deg
            // rotation, scale, tilt and mirroring of each tile).
            mat3 to_local = inverse(mat3(MODEL_MATRIX));
            VERTEX += to_local * vec3(0.0, d, 0.0);
            world_pos.y += d;

            // Tilt the normal by the slope of the correction so lighting and
            // the dust/stone slope logic follow the blended shape.
            // Slope sampled over +-2 cells: a 1-cell difference gives each 2 m
            // cell its own flat shade, which shows up as a blocky pattern.
            vec2 texel = 2.0 / vec2(textureSize(seam_delta, 0));
            float cell_x = seam_rect.z * texel.x;
            float cell_z = seam_rect.w * texel.y;
            float gx = (textureLod(seam_delta, uv + vec2(texel.x, 0.0), 0.0).r
                      - textureLod(seam_delta, uv - vec2(texel.x, 0.0), 0.0).r) / (2.0 * cell_x);
            float gz = (textureLod(seam_delta, uv + vec2(0.0, texel.y), 0.0).r
                      - textureLod(seam_delta, uv - vec2(0.0, texel.y), 0.0).r) / (2.0 * cell_z);
            vec3 n = world_normal;
            n = normalize(n + max(n.y, 0.0) * vec3(-gx, 0.0, -gz));
            world_normal = n;
            NORMAL = normalize(to_local * n);
        }
    }
}

void fragment() {
    if (box_wall > 0.999) {
        discard;
    }
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
