shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Grounded daylight facade shader for Aurora Vigil buildings.
// Divides UV into a grid of windows; most panes stay dark/reflective and only a
// sparse subset gets a low warm interior glow. No cyan neon frame emission.
// Falls back to procedural albedo when texture uniforms are not set.

group_uniforms albedo;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D albedo_tex_2 : source_color, hint_default_white; // second material for detail blending
uniform vec4 albedo_tint : source_color = vec4(0.92, 0.90, 0.84, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0); // per-building UV offset to break grid tiling
uniform float uv_scale_2 = 1.0;          // second detail layer scale
// Capture-distance tiling break: detail_blend raises how much the second layer shows
// (default 0.3 = legacy), and capture_detail_frequency_boost multiplies the *effective*
// detail frequency above the tested uv_scale_2 ratio without changing that public value.
uniform float detail_blend = 0.3;
uniform float capture_detail_frequency_boost = 1.0;
// Colour-group modulation: nudge the whole facade toward an assigned group hue
// (teal glass / warm concrete / dark metal). Default strength 0.0 = no shift.
uniform vec3 group_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float group_tint_strength = 0.0;
uniform float group_tint_lift = 0.0;

group_uniforms pbr;
uniform float roughness_base = 0.42;
uniform float roughness_tex_weight = 0.8; // How much the real roughness map drives the final value
uniform float metallic_val = 0.14;
uniform sampler2D roughness_tex : source_color, hint_default_white;
uniform bool use_normal_map = false;
uniform sampler2D normal_tex;
uniform float normal_map_scale = 1.0; // NORMAL_MAP_SCALE for real textures

group_uniforms emission_map;
uniform sampler2D emission_tex : source_color, hint_default_black;

group_uniforms window_grid;
uniform int floors = 8;
uniform int windows_per_floor = 4;
uniform float frame_thickness = 0.08;
uniform float lit_probability = 0.08;
uniform float flicker_probability = 0.03;
uniform float flicker_speed = 3.0;
uniform int building_seed = 0;
uniform float emission_energy = 0.08;
uniform float uv_scale = 1.0;
// High-rise "crown": lit windows in the top crown_frac of the facade get their
// emission multiplied by crown_boost so upper floors read brighter than the base.
// Default crown_boost 1.0 = no effect (used by non-capture callers).
uniform float crown_boost = 1.0;
uniform float crown_frac = 0.25;
uniform float crown_window_fill = 0.0;

group_uniforms colors;
uniform vec3 warm_white = vec3(1.0, 0.92, 0.78);
uniform vec3 cool_office_white = vec3(0.88, 0.88, 0.84);
uniform vec3 warm_amber = vec3(1.0, 0.72, 0.35);
uniform vec3 frame_color = vec3(0.02, 0.04, 0.06);
uniform vec3 dark_window = vec3(0.015, 0.03, 0.045);

group_uniforms glass;
uniform float window_depth = 0.0;        // how recessed dark windows appear
uniform float glass_reflectivity = 0.15; // base reflectivity for unlit glass
// Capture-distance multipliers scale the *effective* recess/reflection so windows
// read at play distance, while window_depth/glass_reflectivity keep their tested
// public values. Defaults of 1.0 preserve the legacy close-up look.
uniform float capture_depth_multiplier = 1.0;
uniform float capture_reflectivity_multiplier = 1.0;
uniform vec3 glass_sky_tint : source_color = vec3(0.15, 0.12, 0.10); // pane reflection tint

// ---- Hash function: integer → [0, 1) ----
float hash21(int x, int y) {
	int h = x * 374761393 + y * 668265263 + building_seed * 1442695040;
	h = (h ^ (h >> 13)) * 1274126177;
	h = h ^ (h >> 16);
	return float(h & 0x7FFFFFFF) / float(0x7FFFFFFF);
}

// Choose one of three emission colors based on hash
vec3 pick_emission_color(float r) {
	if (r < 0.55) return warm_white;
	if (r < 0.75) return cool_office_white;
	return warm_amber;
}

void fragment() {
	// Base layer plus a second detail layer at a different scale/offset so large facades
	// no longer show an obvious repeating grid. The offset is unique per building.
	vec2 base_uv = UV * uv_scale + uv_offset;
	vec2 detail_uv = UV * uv_scale_2 * capture_detail_frequency_boost + uv_offset * 1.3;

	// Sample PBR textures (defaults when not set: white albedo, white roughness)
	vec4 albedo_sample = texture(albedo_tex, base_uv);
	vec4 albedo_detail = texture(albedo_tex_2, detail_uv);
	vec3 albedo = mix(albedo_sample.rgb, albedo_detail.rgb, detail_blend) * albedo_tint.rgb;
	// Coarse secondary variation interrupts large repeated PBR tiles in wide shots.
	// Boosted for capture-distance readability: broader amplitude + third octave so
	// adjacent facades read as different tones, not a uniform repeat.
	float broad_variation = texture(albedo_tex_2, detail_uv * 0.37 + vec2(0.17, 0.29)).r;
	float broad_variation2 = texture(albedo_tex_2, detail_uv * 0.21 + vec2(0.41, 0.13)).g;
	float broad_amt = clamp(detail_blend * 0.55, 0.0, 0.52);
	albedo *= mix(vec3(1.0), vec3(0.68 + broad_variation * 0.62 + broad_variation2 * 0.18), broad_amt);
	// Colour-group modulation: shift the whole facade toward its assigned group hue so
	// the skyline reads as distinct teal/concrete/metal bands instead of one brown mass.
	vec3 lifted = mix(albedo, vec3(0.34, 0.36, 0.34), clamp(group_tint_lift, 0.0, 1.0));
	albedo = mix(lifted, group_tint, group_tint_strength);

	float rough_sample = texture(roughness_tex, base_uv).r;
	float rough_detail = texture(roughness_tex, detail_uv).r;
	float rough_blend = mix(rough_sample, rough_detail, detail_blend);
	float roughness = mix(roughness_base, rough_blend, roughness_tex_weight);

	// Normal map — only applied when use_normal_map is true
	if (use_normal_map) {
		vec3 nmap = texture(normal_tex, base_uv).rgb;
		vec3 nmap_detail = texture(normal_tex, detail_uv).rgb;
		nmap = mix(nmap, nmap_detail, detail_blend);
		// Scale normal map intensity: blend toward flat normal (0.5, 0.5, 1.0)
		vec3 flat_normal = vec3(0.5, 0.5, 1.0);
		NORMAL_MAP = mix(flat_normal, nmap, normal_map_scale);
	}

	// ---- Window grid computation ----
	vec2 grid_uv = UV;
	float cell_w = 1.0 / float(windows_per_floor);
	float cell_h = 1.0 / float(floors);

	int cell_x = int(grid_uv.x / cell_w);
	int cell_y = int(grid_uv.y / cell_h);

	vec2 local = vec2(
		(grid_uv.x - float(cell_x) * cell_w) / cell_w,
		(grid_uv.y - float(cell_y) * cell_h) / cell_h
	);

	// Frame lines: darken border region of each cell
	bool is_frame = local.x < frame_thickness || local.x > (1.0 - frame_thickness) ||
		local.y < frame_thickness || local.y > (1.0 - frame_thickness);

	// Per-window hash: is this window lit?
	float lit_r = hash21(cell_x, cell_y);
	bool is_lit = lit_r < lit_probability;

	// Color variation per lit window
	float color_r = hash21(cell_x + 100, cell_y + 200);
	vec3 window_emission = pick_emission_color(color_r);

	// Flicker: some lit windows flicker on/off over time
	float flicker_r = hash21(cell_x + 300, cell_y + 400);
	bool flickers = flicker_r < flicker_probability;
	float flicker_factor = 1.0;
	if (flickers) {
		float t = TIME * flicker_speed + lit_r * 6.2831;
		flicker_factor = step(0.3, 0.5 + 0.5 * sin(t));
	}

	float window_intensity = 0.0;
	if (is_lit) {
		// Crown effect: lit windows in the top crown_frac of the facade burn brighter so
		// high-rises read as lit upper floors. grid_uv.y == 0 is the top of the face.
		float crown_factor = (grid_uv.y < crown_frac) ? crown_boost : 1.0;
		window_intensity = emission_energy * flicker_factor * crown_factor;
	}

	// Combine: frame line → dark frame; lit window → very low warm interior glow;
	// dark window → dim reflective glass. Frames/dark panes do not emit.
	vec3 final_emission = vec3(0.0);
	if (is_frame) {
		albedo = mix(albedo, frame_color, 0.25);
		window_intensity = 0.0;
	} else if (is_lit) {
		// Lit window: soft glow falloff from the pane centre fakes interior depth.
		float window_glow = smoothstep(0.0, 0.5, 1.0 - length(local - vec2(0.5)) * 1.5);
		final_emission = window_emission * window_intensity * window_glow;
		albedo = mix(albedo, window_emission, 0.06 * window_glow);
	} else {
		// Dark window: recessed glass. The *_multiplier uniforms exaggerate the effective
		// recess/reflection at capture distance so panes read as visibly dark centres with
		// a subtle teal sky reflection — without changing the tested public uniform values.
		float recess = smoothstep(frame_thickness, 0.5, local.x) * smoothstep(frame_thickness, 0.5, 1.0 - local.x)
			* smoothstep(frame_thickness, 0.5, local.y) * smoothstep(frame_thickness, 0.5, 1.0 - local.y);
		float eff_depth = window_depth * capture_depth_multiplier;
		float eff_refl = glass_reflectivity * capture_reflectivity_multiplier;
		// Darken the pane centre so the recessed glass reads as a dark rectangle at distance.
		// Deeper baseline darkening + stronger recess curve so the dark-to-frame gradient
		// survives at 60+ unit capture distance.
		float dark_amount = clamp(0.30 + recess * eff_depth * 0.72, 0.0, 0.94);
		albedo = mix(albedo, dark_window, dark_amount);
		// Sky reflection pooling toward the pane centre (teal-tinted for the capture pass).
		// Boosted: deeper sky-tint mix toward pane center + extra brightness lift so glass
		// catches and reflects light at capture distance rather than reading as flat sticker.
		float sky_mix = clamp(recess * eff_refl * 1.25, 0.0, 0.90);
		albedo = mix(albedo, glass_sky_tint + vec3(0.06, 0.12, 0.08), sky_mix);
		float glint = smoothstep(0.92, 1.0, 1.0 - abs((local.x + local.y * 0.55) - 0.82) * 6.5) * recess;
		albedo = mix(albedo, glass_sky_tint + vec3(0.08, 0.14, 0.10), clamp(glint * eff_refl * 0.55, 0.0, 0.50));
		if (grid_uv.y < crown_frac && crown_boost > 1.0) {
			float crown_fill = crown_window_fill * (crown_boost - 1.0) * recess;
			final_emission += warm_amber * crown_fill;
			albedo = mix(albedo, warm_amber, clamp(crown_fill * 0.20, 0.0, 0.18));
		}
		// Lower roughness further in pane centres so glass catches specular light at distance.
		roughness = mix(roughness, 0.04, clamp(recess * eff_refl * 1.15, 0.0, 0.85)); // glass is smoother
	}

	// Add only a tiny amount of any emission texture contribution so legacy maps no
	// longer turn facades into glowing grids.
	vec3 em_sample = texture(emission_tex, base_uv).rgb;
	final_emission += em_sample * emission_energy * 0.12;

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic_val;
	EMISSION = final_emission;
}