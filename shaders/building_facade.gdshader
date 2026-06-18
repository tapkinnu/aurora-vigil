shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Grounded daylight facade shader for Aurora Vigil buildings.
// Divides UV into a grid of windows; most panes stay dark/reflective and only a
// sparse subset gets a low warm interior glow. No cyan neon frame emission.
// Falls back to procedural albedo when texture uniforms are not set.

group_uniforms albedo;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(0.92, 0.90, 0.84, 1.0);

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

group_uniforms colors;
uniform vec3 warm_white = vec3(1.0, 0.92, 0.78);
uniform vec3 cool_office_white = vec3(0.88, 0.88, 0.84);
uniform vec3 warm_amber = vec3(1.0, 0.72, 0.35);
uniform vec3 frame_color = vec3(0.02, 0.04, 0.06);
uniform vec3 dark_window = vec3(0.015, 0.03, 0.045);

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
	vec2 base_uv = UV * uv_scale;

	// Sample PBR textures (defaults when not set: white albedo, white roughness)
	vec4 albedo_sample = texture(albedo_tex, base_uv);
	vec3 albedo = albedo_sample.rgb * albedo_tint.rgb;

	float rough_sample = texture(roughness_tex, base_uv).r;
	float roughness = mix(roughness_base, rough_sample, roughness_tex_weight);

	// Normal map — only applied when use_normal_map is true
	if (use_normal_map) {
		vec3 nmap = texture(normal_tex, base_uv).rgb;
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
		window_intensity = emission_energy * flicker_factor;
	}

	// Combine: frame line → dark frame; lit window → very low warm interior glow;
	// dark window → dim reflective glass. Frames/dark panes do not emit.
	vec3 final_emission = vec3(0.0);
	if (is_frame) {
		albedo = mix(albedo, frame_color, 0.25);
		window_intensity = 0.0;
	} else if (is_lit) {
		final_emission = window_emission * window_intensity;
		albedo = mix(albedo, window_emission, 0.06);
	} else {
		albedo = mix(albedo, dark_window, 0.15);
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