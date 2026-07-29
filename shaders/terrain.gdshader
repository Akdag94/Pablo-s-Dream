shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain surface for the hex tiles.
//
// The biome colour arrives per-instance from the MultiMesh; everything that
// makes it read as ground rather than plastic is generated here — grain,
// clumping, normal detail and a roughness break-up. No texture files, so the
// look is identical on every device and costs nothing to download.

uniform float detail_scale : hint_range(0.5, 20.0) = 6.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.30;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float macro_scale : hint_range(0.05, 4.0) = 0.55;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.22;

uniform float roughness_base : hint_range(0.0, 1.0) = 0.90;
uniform float roughness_variation : hint_range(0.0, 1.0) = 0.18;

// Parallax occlusion. Ray-marches the same noise the albedo uses, so pits and
// clumps actually shift as the camera orbits instead of sliding with it. This
// is what stops the ground reading as a printed texture on a flat plane.
uniform bool parallax_enabled = true;
uniform float parallax_depth : hint_range(0.0, 0.2) = 0.045;
uniform int parallax_steps : hint_range(4, 32) = 16;

// Slope darkening: the sides of each prism read as exposed earth.
uniform vec3 side_tint : source_color = vec3(0.42, 0.34, 0.26);
uniform float side_blend : hint_range(0.0, 1.0) = 0.65;

// Real photoscanned ground. When these are not supplied the shader falls back
// to its own procedural surface, so the game still runs with no assets.
uniform bool use_textures = false;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_array : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// World units per texture repeat. Tiling in world space rather than per hex
// keeps the ground continuous across tile borders.
uniform float texture_tiling : hint_range(0.05, 4.0) = 0.55;
// How much of the biome colour is tinted back over the photo.
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_instance_color;
varying float v_layer;


// -- noise ------------------------------------------------------------------

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123) * 2.0 - 1.0;
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// Quintic fade keeps the second derivative continuous, so no visible
	// grid creases where cells meet.
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float n000 = dot(hash3(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(hash3(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash3(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash3(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash3(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash3(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash3(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash3(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z) * 0.5 + 0.5;
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}


// -- passes -----------------------------------------------------------------

void vertex() {
	v_instance_color = COLOR;
	// x carries which texture layer this tile draws with.
	v_layer = INSTANCE_CUSTOM.x;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Walk the view ray down through the height field and stop at the first step
// that is below the surface. Everything after that point is occluded.
vec3 apply_parallax(vec3 world_pos, vec3 view_dir, float upness) {
	if (!parallax_enabled || parallax_depth <= 0.0) {
		return world_pos;
	}

	// Grazing angles need more steps; head-on needs almost none.
	float steps = mix(float(parallax_steps), 6.0, upness);
	float step_count = max(steps, 4.0);
	float layer_depth = 1.0 / step_count;

	// Only the horizontal component displaces a mostly-flat top surface.
	vec2 max_offset = view_dir.xz * parallax_depth;
	vec2 step_offset = max_offset * layer_depth;

	float current_layer = 0.0;
	vec2 offset = vec2(0.0);
	float height = 1.0 - fbm((world_pos + vec3(offset.x, 0.0, offset.y)) * detail_scale);

	for (int i = 0; i < 32; i++) {
		if (float(i) >= step_count || current_layer >= height) {
			break;
		}
		offset += step_offset;
		height = 1.0 - fbm((world_pos + vec3(offset.x, 0.0, offset.y)) * detail_scale);
		current_layer += layer_depth;
	}

	// One linear refinement between the last two samples hides the stepping.
	vec2 previous = offset - step_offset;
	float after = height - current_layer;
	float before = (1.0 - fbm((world_pos + vec3(previous.x, 0.0, previous.y)) * detail_scale))
		- current_layer + layer_depth;
	float weight = after / max(after - before, 0.0001);
	offset = mix(offset, previous, clamp(weight, 0.0, 1.0));

	return world_pos + vec3(offset.x, 0.0, offset.y);
}

void fragment() {
	vec3 base = v_instance_color.rgb;

	float upness = clamp(v_world_normal.y, 0.0, 1.0);

	// Displace the sampling position before anything reads from it, so albedo,
	// normals and roughness all agree on where the surface actually is.
	vec3 view_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
	vec3 sample_pos = apply_parallax(v_world_pos, view_dir, upness);

	// Two scales of variation: fine grain plus slow drifting patches, so the
	// ground does not tile visibly across a large island.
	float grain = fbm(sample_pos * detail_scale);
	float macro = fbm(sample_pos * macro_scale + 17.3);

	vec3 albedo;
	float texture_roughness = roughness_base;
	float occlusion = 1.0;
	vec3 texture_normal = vec3(0.5, 0.5, 1.0);

	if (use_textures) {
		// Tile in world space so the ground runs continuously between hexes.
		vec2 uv = sample_pos.xz * texture_tiling;
		vec3 coord = vec3(uv, v_layer);

		vec3 photo = texture(albedo_array, coord).rgb;
		vec3 packed = texture(orm_array, coord).rgb;
		texture_normal = texture(normal_array, coord).rgb;

		texture_roughness = packed.r;
		occlusion = packed.g;

		// Break up the repeat with the same noise, and tint toward the biome
		// colour so a green tile still reads as green.
		photo *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);
		albedo = mix(photo, photo * base * 2.0, tint_strength);
	} else {
		albedo = base;
		albedo *= mix(1.0 - detail_strength, 1.0 + detail_strength, grain);
		albedo *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);
	}

	// Anything facing sideways is a cut edge of earth, not a top surface.
	float side = 1.0 - smoothstep(0.25, 0.75, upness);
	albedo = mix(albedo, albedo * side_tint * 2.0, side * side_blend);

	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// Perturb the normal from the noise gradient. Sampling three offsets is
	// cheaper here than carrying a normal map and looks the same at this scale.
	if (use_textures) {
		NORMAL_MAP = texture_normal;
		NORMAL_MAP_DEPTH = mix(0.5, 1.0, upness);
		ROUGHNESS = clamp(texture_roughness, 0.05, 1.0);
		AO = occlusion;
		AO_LIGHT_AFFECT = 0.65;
	} else {
		float e = 0.06;
		float nx = fbm((sample_pos + vec3(e, 0.0, 0.0)) * detail_scale) - grain;
		float nz = fbm((sample_pos + vec3(0.0, 0.0, e)) * detail_scale) - grain;
		NORMAL_MAP = normalize(vec3(-nx * normal_strength, -nz * normal_strength, 1.0)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = mix(0.4, 1.0, upness);
		ROUGHNESS = clamp(roughness_base + (grain - 0.5) * roughness_variation, 0.05, 1.0);
	}

	METALLIC = 0.0;
	SPECULAR = 0.35;
}
