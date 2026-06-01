shader_type canvas_item;

// Shop spot with radial dissolve from a hit point.
// Reuses the same swirl/marble animation as shop_spot.gdshader,
// but fades pixels to transparent as a radial wave expands outward.

uniform float speed : hint_range(0.1, 3.0) = 0.6;
uniform float noise_scale : hint_range(1.0, 30.0) = 8.0;
uniform float distortion : hint_range(0.0, 2.0) = 0.8;
uniform float contrast : hint_range(0.0, 1.0) = 0.5;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.8;
uniform float board_radius : hint_range(50.0, 1000.0) = 300.0;

// Dissolve uniforms
uniform vec2 dissolve_center = vec2(0.0, 0.0);
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_reach : hint_range(0.05, 1.0) = 0.35;
uniform float dissolve_edge_width : hint_range(0.01, 0.15) = 0.04;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = local_pos / board_radius;
	float t = TIME * speed;

	// Two-layer domain warping for the marble/swirl effect
	vec2 q = vec2(
		fbm(uv * noise_scale + vec2(0.0, t * 0.3)),
		fbm(uv * noise_scale + vec2(5.2, t * 0.4))
	);

	vec2 r = vec2(
		fbm(uv * noise_scale + q * distortion * 4.0 + vec2(1.7, t * 0.2)),
		fbm(uv * noise_scale + q * distortion * 4.0 + vec2(8.3, t * 0.5))
	);

	float pattern = fbm(uv * noise_scale + r * distortion * 4.0);

	// Brightness variation from the swirl pattern
	float brightness = 1.0 + (pattern - 0.5) * contrast * 2.0;
	COLOR.rgb *= brightness;

	// Glow at the bright spots
	float glow = max(pattern - 0.55, 0.0) * glow_strength * 3.0;
	COLOR.rgb += COLOR.rgb * glow;

	// Radial dissolve: fade out pixels within the expanding radius
	float dist = distance(uv, dissolve_center);
	float dissolve_radius = dissolve_progress * dissolve_reach;
	float dissolve_alpha = smoothstep(dissolve_radius - dissolve_edge_width, dissolve_radius, dist);
	COLOR.a *= dissolve_alpha;
}
