/*
Realistic Water Shader
Copyright (c) 2019 UnionBytes, Achim Menzel (alias AiYori)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

-- UnionBytes -- YouTube: www.youtube.com/user/UnionBytes
*/

// Ported to Godot 4 for Pablo's Dream, with three deviations from the original:
//
//  1. Godot 4 renames: WORLD_MATRIX -> MODEL_MATRIX, NORMALMAP -> NORMAL_MAP,
//     and SCREEN_TEXTURE / DEPTH_TEXTURE are now explicit hinted uniforms.
//     Depth reconstruction is rewritten for Godot 4's reversed-Z projection.
//
//  2. The original samples four noise textures and a 16-frame caustic texture
//     array. None of those files exist here, so the normal, foam and caustic
//     patterns are generated in-shader. That keeps the water working with no
//     external assets and costs arithmetic instead of texture bandwidth.
//
//  3. Gerstner displacement runs off world position rather than local vertex
//     position, so the wave crest is continuous across the separate tile
//     meshes the island is built from instead of breaking at every seam.

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, blend_mix;

// Wave settings — xy = direction, z = steepness, w = length.
uniform float wave_speed = 0.5;
uniform vec4 wave_a = vec4(1.0, 1.0, 0.14, 3.0);
uniform vec4 wave_b = vec4(1.0, 0.6, 0.10, 1.55);
uniform vec4 wave_c = vec4(1.0, 1.3, 0.08, 0.9);

// Surface settings.
uniform vec2 sampler_scale = vec2(0.25, 0.25);
uniform vec2 sampler_direction = vec2(0.05, 0.04);
uniform float uv_sampler_strength = 0.04;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.25;

// Foam distance from the shore.
uniform float foam_level : hint_range(0.0, 2.0) = 0.5;

// Volume settings.
uniform float refraction = 0.075;
uniform vec4 color_deep : source_color = vec4(0.05, 0.19, 0.30, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.28, 0.65, 0.66, 1.0);
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

// Caustics, generated rather than sampled.
uniform bool caustics_enabled = true;
uniform float caustics_strength : hint_range(0.0, 4.0) = 1.6;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying vec3 v_binormal;
varying vec3 v_tangent;


// -- procedural noise, replacing the original's sampler textures -------------

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

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += value_noise(p) * amp;
		p *= 2.07;
		amp *= 0.5;
	}
	return sum;
}

// Voronoi-ish cell pattern; the bright cell borders read as caustic lines.
float caustic_pattern(vec2 p, float t) {
	vec2 i = floor(p);
	float nearest = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 point = cell + vec2(hash(i + cell), hash(i + cell + 37.0));
			point = cell + 0.5 + 0.5 * sin(t + 6.2831 * point);
			nearest = min(nearest, length(point - fract(p)));
		}
	}
	return pow(1.0 - nearest, 6.0);
}


// -- Gerstner wave ----------------------------------------------------------

vec4 wave(vec4 parameter, vec2 position, float time, inout vec3 tangent, inout vec3 binormal) {
	float steepness = parameter.z;
	float length_ = parameter.w;

	float k = 2.0 * 3.14159265359 / length_;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(parameter.xy);
	float f = k * (dot(d, position) - c * time);
	float a = steepness / k;

	tangent += normalize(vec3(
		1.0 - d.x * d.x * (steepness * sin(f)),
		d.x * (steepness * cos(f)),
		-d.x * d.y * (steepness * sin(f))));
	binormal += normalize(vec3(
		-d.x * d.y * (steepness * sin(f)),
		d.y * (steepness * cos(f)),
		1.0 - d.y * d.y * (steepness * sin(f))));

	return vec4(d.x * (a * cos(f)), a * sin(f) * 0.25, d.y * (a * cos(f)), 0.0);
}


void vertex() {
	float time = TIME * wave_speed;

	// Displace against world position so neighbouring tiles agree on the
	// crest and no seam opens between them.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 tang = vec3(0.0);
	vec3 bin = vec3(0.0);

	vec4 offset = vec4(0.0);
	offset += wave(wave_a, world.xz, time, tang, bin);
	offset += wave(wave_b, world.xz, time, tang, bin);
	offset += wave(wave_c, world.xz, time, tang, bin);

	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset.xyz, 0.0)).xyz;

	v_tangent = tang;
	v_binormal = bin;
	v_normal = normalize(cross(bin, tang));

	TANGENT = tang;
	BINORMAL = bin;
	NORMAL = v_normal;

	v_world_pos = world + offset.xyz;
	UV = v_world_pos.xz * sampler_scale;
}


void fragment() {
	vec2 uv_offset = sampler_direction * TIME;
	vec2 uv = UV + (fbm(UV * 2.0 + uv_offset) * 2.0 - 1.0) * uv_sampler_strength;

	// Two drifting noise layers stand in for the original's two normal maps.
	float h = fbm(uv * 3.0 - uv_offset * 2.0) * 0.75 + fbm(uv * 6.5 + uv_offset) * 0.25;
	float e = 0.045;
	float hx = (fbm((uv + vec2(e, 0.0)) * 3.0 - uv_offset * 2.0) * 0.75
		+ fbm((uv + vec2(e, 0.0)) * 6.5 + uv_offset) * 0.25) - h;
	float hz = (fbm((uv + vec2(0.0, e)) * 3.0 - uv_offset * 2.0) * 0.75
		+ fbm((uv + vec2(0.0, e)) * 6.5 + uv_offset) * 0.25) - h;

	vec3 surface_normal = normalize(vec3(-hx * normal_strength, 1.0, -hz * normal_strength));
	NORMAL_MAP = surface_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.25;

	// Refracted screen coordinate.
	vec2 ref_uv = SCREEN_UV + surface_normal.xz * refraction;

	// Linear depth of whatever sits behind the water, in view space.
	float depth_raw = texture(depth_texture, ref_uv).r;
	vec3 ndc = vec3(ref_uv * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float surface_depth = -VERTEX.z;
	float water_depth = max(scene_depth - surface_depth, 0.0);

	float depth_blend = clamp(1.0 - exp((water_depth + depth_offset) * -beers_law), 0.0, 1.0);
	float depth_blend_pow = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	vec3 screen_color = textureLod(screen_texture, ref_uv, depth_blend_pow * 2.5).rgb;
	vec3 dye = mix(color_shallow.rgb, color_deep.rgb, depth_blend_pow);
	vec3 color = mix(screen_color * dye, dye * 0.25, depth_blend_pow * 0.5);

	// Caustics brighten the shallows, where light actually reaches the floor.
	if (caustics_enabled) {
		float caustic = caustic_pattern(v_world_pos.xz * 1.6, TIME * 0.7);
		color *= 1.0 + caustic * (1.0 - depth_blend) * caustics_strength;
	}

	// Foam along the shoreline.
	if (water_depth < foam_level) {
		float noise = clamp(pow(fbm(uv * 4.0 - uv_offset), 2.0) * 2.2, 0.0, 1.0);
		float foam_mix = clamp(pow(1.0 - water_depth / max(foam_level, 0.001), 3.0) * noise, 0.0, 1.0);
		color = mix(color, vec3(1.0), foam_mix);
	}

	ALBEDO = color;
	METALLIC = 0.1;
	ROUGHNESS = 0.2;
	SPECULAR = 0.2 + depth_blend_pow * 0.4;
	ALPHA = clamp(0.55 + depth_blend_pow * 0.45, 0.0, 1.0);
}
