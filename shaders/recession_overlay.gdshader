shader_type canvas_item;

// Rough, gritty overlay for recession-affected wedge segments.
// Creates a worn/scuffed look with directional noise stretching.
// Subtler and slower than the shop/void swirl shader.

// Drift speed of the scuff pattern (very slow — looks near-static).
uniform float speed : hint_range(0.0, 0.5) = 0.1;

// Base frequency of the noise. Higher = finer grit.
uniform float noise_scale : hint_range(5.0, 40.0) = 20.0;

// How pronounced the dark scuff patches are.
uniform float roughness : hint_range(0.0, 1.0) = 0.65;

// Overall strength of the darkening effect.
uniform float intensity : hint_range(0.0, 1.0) = 0.5;

// Board radius for normalizing UV coordinates.
uniform float board_radius : hint_range(50.0, 1000.0) = 300.0;

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

// Fewer octaves + sharper falloff than the shop shader = grittier texture.
float rough_fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amp * noise(p);
		p *= 2.8;
		amp *= 0.35;
	}
	return value;
}

void fragment() {
	vec2 uv = local_pos / board_radius;
	float t = TIME * speed;

	// Stretch one axis for a directional scratch feel
	vec2 scratch_uv = uv * vec2(noise_scale, noise_scale * 0.4);

	float n1 = rough_fbm(scratch_uv + vec2(t * 0.15, t * 0.05));
	float n2 = rough_fbm(scratch_uv * 1.8 + vec2(5.1, t * 0.1));

	float pattern = n1 * 0.55 + n2 * 0.45;

	// Sharp threshold for distinct scuff patches
	float scuff = smoothstep(0.32, 0.52, pattern) * roughness;

	// Darken based on scuff pattern, slight reddish tint in damaged areas
	COLOR.rgb *= (1.0 - scuff * intensity);
	COLOR.r += scuff * intensity * 0.06;
}
