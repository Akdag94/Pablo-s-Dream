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

// Slope darkening: the sides of each prism read as exposed earth.
uniform vec3 side_tint : source_color = vec3(0.42, 0.34, 0.26);
uniform float side_blend : hint_range(0.0, 1.0) = 0.65;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_instance_color;


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
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = v_instance_color.rgb;

	// Two scales of variation: fine grain plus slow drifting patches, so the
	// ground does not tile visibly across a large island.
	float grain = fbm(v_world_pos * detail_scale);
	float macro = fbm(v_world_pos * macro_scale + 17.3);

	vec3 albedo = base;
	albedo *= mix(1.0 - detail_strength, 1.0 + detail_strength, grain);
	albedo *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);

	// Anything facing sideways is a cut edge of earth, not a top surface.
	float upness = clamp(v_world_normal.y, 0.0, 1.0);
	float side = 1.0 - smoothstep(0.25, 0.75, upness);
	albedo = mix(albedo, albedo * side_tint * 2.0, side * side_blend);

	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// Perturb the normal from the noise gradient. Sampling three offsets is
	// cheaper here than carrying a normal map and looks the same at this scale.
	float e = 0.06;
	float nx = fbm((v_world_pos + vec3(e, 0.0, 0.0)) * detail_scale) - grain;
	float nz = fbm((v_world_pos + vec3(0.0, 0.0, e)) * detail_scale) - grain;
	NORMAL_MAP = normalize(vec3(-nx * normal_strength, -nz * normal_strength, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.4, 1.0, upness);

	ROUGHNESS = clamp(roughness_base + (grain - 0.5) * roughness_variation, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
