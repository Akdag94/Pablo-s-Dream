shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Water surface.
//
// Depth is read from the depth buffer rather than baked into the mesh, so the
// same shader handles a shallow river and open ocean: shallow water shows the
// ground through it and grows a foam line at the shore, deep water goes dark
// and reflective. That contrast is most of what sells it as water.

uniform vec3 shallow_color : source_color = vec3(0.32, 0.66, 0.68);
uniform vec3 deep_color : source_color = vec3(0.05, 0.18, 0.31);
uniform float depth_fade_distance : hint_range(0.1, 20.0) = 3.2;

uniform float wave_scale : hint_range(0.1, 20.0) = 3.5;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.28;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.55;

uniform float foam_distance : hint_range(0.0, 4.0) = 0.55;
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.97);

uniform float refraction_strength : hint_range(0.0, 0.3) = 0.045;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.45;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world_pos;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Two noise layers drifting against each other read as moving water without
// needing a flow map.
float waves(vec2 p, float t) {
	float a = value_noise(p * wave_scale + vec2(t, t * 0.6));
	float b = value_noise(p * wave_scale * 1.9 - vec2(t * 0.7, t * 1.1));
	return (a * 0.65 + b * 0.35);
}


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world_pos.xz;

	// Surface normal from the wave gradient.
	float e = 0.06;
	float h = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t) - h;
	float hz = waves(p + vec2(0.0, e), t) - h;
	vec3 wave_normal = normalize(vec3(-hx * wave_strength, 1.0, -hz * wave_strength));
	NORMAL_MAP = wave_normal * 0.5 + 0.5;

	// How much water sits between this pixel and the ground behind it.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_distance = -view.z;
	float surface_distance = -VERTEX.z;
	float water_depth = max(scene_distance - surface_distance, 0.0);

	float depth_mix = clamp(water_depth / depth_fade_distance, 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, depth_mix);

	// Refract what is behind the water by pushing the sample along the waves.
	vec2 offset = wave_normal.xz * refraction_strength;
	vec3 behind = texture(screen_texture, SCREEN_UV + offset).rgb;

	// Shallow water lets the ground through; deep water hides it.
	vec3 color = mix(behind * water * 1.6, water, depth_mix);

	// Foam where the water meets land.
	float foam = 1.0 - smoothstep(0.0, foam_distance, water_depth);
	foam *= 0.6 + 0.4 * waves(p * 2.2, t * 1.6);
	color = mix(color, foam_color, clamp(foam, 0.0, 1.0) * 0.85);

	ALBEDO = color;
	ALPHA = mix(transparency_min, 1.0, depth_mix) + foam * 0.4;
	ROUGHNESS = mix(0.02, 0.14, depth_mix);
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
