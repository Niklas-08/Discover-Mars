shader_type sky;
render_mode use_debanding;

// ============================================================================
//  Martian sky
// ============================================================================
//  Mars' atmosphere is ~1% of Earth's but loaded with suspended iron-oxide
//  dust, which inverts the colours we are used to:
//    * Daytime  -> butterscotch / tan, brightest near the horizon.
//    * Twilight -> a BLUE halo around the Sun. Dust forward-scatters blue
//                  light, so sunrise/sunset glows blue instead of red.
//    * Night    -> extremely dark with very sharp stars (thin air, almost no
//                  moonlight; Phobos and Deimos are tiny).
//  The Sun is also smaller (~0.35 deg vs 0.53 deg) and dimmer than on Earth.
// ============================================================================

// --- Sun -------------------------------------------------------------------
/// Direction pointing TOWARD the sun. Driven by DayNightCycle.
uniform vec3 sun_direction = vec3(0.0, 0.4, -1.0);
uniform float sun_angular_radius : hint_range(0.001, 0.05) = 0.0032;
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.97, 0.90);
uniform vec3 sun_disk_color_low : source_color = vec3(0.82, 0.90, 1.0);
uniform float sun_intensity : hint_range(0.0, 60.0) = 14.0;

// --- Daytime dust atmosphere ----------------------------------------------
uniform vec3 day_zenith_color : source_color = vec3(0.34, 0.25, 0.21);
uniform vec3 day_horizon_color : source_color = vec3(0.80, 0.58, 0.40);
uniform float horizon_falloff : hint_range(0.5, 12.0) = 3.0;
uniform float day_exposure : hint_range(0.0, 3.0) = 1.0;
uniform float dust_forward_scatter : hint_range(0.0, 2.0) = 0.35;

// --- Twilight (the blue Mie halo) -----------------------------------------
uniform vec3 twilight_halo_color : source_color = vec3(0.26, 0.45, 0.72);
uniform float twilight_halo_tightness : hint_range(1.0, 200.0) = 22.0;
uniform float twilight_strength : hint_range(0.0, 4.0) = 1.6;
uniform float twilight_width : hint_range(0.02, 0.6) = 0.17;

// --- Night -----------------------------------------------------------------
uniform vec3 night_zenith_color : source_color = vec3(0.008, 0.010, 0.020);
uniform vec3 night_horizon_color : source_color = vec3(0.028, 0.024, 0.030);

// --- Stars -----------------------------------------------------------------
uniform float star_density : hint_range(20.0, 400.0) = 160.0;
uniform float star_coverage : hint_range(0.0, 0.1) = 0.005;
uniform float star_size : hint_range(0.002, 0.2) = 0.020;
uniform float star_brightness : hint_range(0.0, 6.0) = 2.0;
uniform float star_twinkle_speed : hint_range(0.0, 10.0) = 2.2;
/// Minimum on-screen star radius in pixels. Stars smaller than roughly one
/// pixel alias badly and appear to "swim" or jitter when the camera turns,
/// so they are widened to at least this size and faded instead.
uniform float star_min_pixels : hint_range(0.2, 4.0) = 0.55;
uniform vec3 milky_way_axis = vec3(0.25, 0.30, 0.92);
uniform float milky_way_strength : hint_range(0.0, 3.0) = 0.55;
uniform float milky_way_width : hint_range(0.05, 0.6) = 0.16;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise, used to break the galactic band into clumps and rifts
// instead of a featureless gaussian smear.
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// Sparse procedural star field.
//
// Stars live on a 2D grid laid over the cube-face projection of the view
// direction. Two details matter for stability:
//
//  * The 3x3 neighbourhood is sampled, so a star whose disc spills past its
//    own cell is still drawn by the neighbouring cell. Sampling only the
//    owning cell clips discs against cell borders and yields square stars.
//  * Star radius is clamped to at least ~1 screen pixel using fwidth().
//    Sub-pixel stars land on different pixels from frame to frame as the
//    camera turns, which reads as stars "swimming" faster than the world.
//    Widened stars are dimmed by the area ratio so faint ones fade instead
//    of popping.
vec3 star_field(vec3 dir, float band_boost) {
	// --- Cube-face projection: direction -> stable 2D grid coordinates ---
	vec3 a = abs(dir);
	vec2 face_uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		face_uv = dir.zy / a.x;
		face = dir.x > 0.0 ? 0.0 : 1.0;
	} else if (a.y >= a.z) {
		face_uv = dir.xz / a.y;
		face = dir.y > 0.0 ? 2.0 : 3.0;
	} else {
		face_uv = dir.xy / a.z;
		face = dir.z > 0.0 ? 4.0 : 5.0;
	}

	vec2 uv = face_uv * star_density;
	// Size of one screen pixel in grid units. Clamped so the cube-face seams
	// (where uv jumps) cannot produce a huge value.
	vec2 duv = fwidth(uv);
	float pixel_size = clamp(max(duv.x, duv.y), 1e-5, 1.0);

	vec2 gid = floor(uv);
	vec2 gf = uv - gid;

	float threshold = 1.0 - star_coverage * (1.0 + band_boost);
	float radius = max(star_size, pixel_size * star_min_pixels);
	float area_comp = clamp((star_size * star_size) / (radius * radius), 0.10, 1.0);

	vec3 acc = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbour = vec2(float(x), float(y));
			vec2 cell = gid + neighbour;

			float rnd = hash13(vec3(cell, face));
			if (rnd < threshold) {
				continue;
			}

			// Jitter the star inside its cell so the grid is not visible.
			vec2 offset = vec2(
				hash13(vec3(cell, face + 17.0)),
				hash13(vec3(cell, face + 31.0)));
			float d = length(gf - (neighbour + offset));

			float core = smoothstep(radius, radius * 0.2, d);
			float glow = smoothstep(radius * 3.0, 0.0, d) * 0.18;

			// Magnitude + colour spread (hot blue-white through cool orange).
			float mag = hash13(vec3(cell, face + 7.0));
			float brightness = mix(0.10, 1.0, pow(mag, 2.5));
			float temp = hash13(vec3(cell, face + 11.0));
			vec3 tint = mix(vec3(1.0, 0.82, 0.68), vec3(0.78, 0.86, 1.0), temp);

			// Scintillation - brightness only, so nothing appears to move.
			float twinkle = 0.85 + 0.15 * sin(TIME * star_twinkle_speed + rnd * 100.0);

			acc += tint * (core * area_comp + glow) * brightness * twinkle;
		}
	}
	return acc * star_brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);

	float sun_height = sun_dir.y;                       // 1 zenith, 0 horizon, -1 nadir
	float cos_sun = clamp(dot(dir, sun_dir), -1.0, 1.0);

	// How much daylight there is, and how close we are to sunrise/sunset.
	float day = smoothstep(-0.20, 0.10, sun_height);
	float twilight = exp(-(sun_height * sun_height) / (twilight_width * twilight_width));

	// --- Vertical gradient -------------------------------------------------
	float horizon_blend = pow(1.0 - clamp(dir.y, 0.0, 1.0), horizon_falloff);
	vec3 day_sky = mix(day_zenith_color, day_horizon_color, horizon_blend);
	vec3 night_sky = mix(night_zenith_color, night_horizon_color, horizon_blend);
	vec3 col = mix(night_sky, day_sky, day) * day_exposure;

	// --- Dust forward scattering (broad warm glow around the sun by day) ---
	float wide_scatter = pow(max(cos_sun, 0.0), 3.5);
	col += day_horizon_color * wide_scatter * dust_forward_scatter * day;

	// --- The signature blue twilight halo ----------------------------------
	// Tight Mie lobe around the sun, strongest when the sun sits near the
	// horizon. This is what makes a Martian sunset blue.
	float mie = pow(max(cos_sun, 0.0), twilight_halo_tightness);
	float halo_amount = twilight_strength * (twilight * 1.0 + day * 0.25);
	col += twilight_halo_color * mie * halo_amount;

	// A soft blue wash spread along the horizon on the sun's side.
	vec3 sun_azimuth = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(1e-5));
	float azimuth_align = max(dot(normalize(vec3(dir.x, 0.0, dir.z) + vec3(1e-5)), sun_azimuth), 0.0);
	float horizon_hug = exp(-abs(dir.y) / 0.10);
	col += twilight_halo_color * pow(azimuth_align, 3.0) * horizon_hug * twilight * 0.45;

	// --- Stars --------------------------------------------------------------
	float night_amount = 1.0 - day;
	if (night_amount > 0.001) {
		// Faint galactic band: raises star density along one great circle.
		float band = exp(-pow(dot(dir, normalize(milky_way_axis)) / milky_way_width, 2.0));
		vec3 stars = star_field(dir, band * milky_way_strength * 2.0);
		// Clumpy structure + dark dust rifts, so it reads as a galaxy rather
		// than a smooth beam of light.
		float clump = fbm(dir * 5.5);
		float rift = smoothstep(0.30, 0.62, fbm(dir * 3.1 + vec3(19.4)));
		float structure = mix(0.25, 1.35, clump) * mix(0.35, 1.0, rift);
		vec3 band_glow = vec3(0.020, 0.019, 0.028) * band * milky_way_strength * structure;
		// Stars only above the horizon line, and only once it is dark.
		float above = smoothstep(-0.04, 0.03, dir.y);
		col += (stars + band_glow) * night_amount * above;
	}

	// --- Sun disk -----------------------------------------------------------
	// Pale blue-white when low (dust scatters the warm end away), neutral high up.
	float elevation_mix = smoothstep(-0.02, 0.30, sun_height);
	vec3 disk_color = mix(sun_disk_color_low, sun_disk_color, elevation_mix);
	float cos_inner = cos(sun_angular_radius);
	float cos_outer = cos(sun_angular_radius * 2.4);
	float disk = smoothstep(cos_outer, cos_inner, cos_sun);
	// Extinction as it sets below the horizon.
	float visible = smoothstep(-0.06, 0.02, sun_height);
	col += disk_color * disk * sun_intensity * visible;

	COLOR = max(col, vec3(0.0));
}
