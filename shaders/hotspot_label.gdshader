shader_type canvas_item;
// Smokifies a Label's text so the hotspot "+N" looks made of drifting smoke instead of pasted on.
// Animated fBm erodes the glyph alpha unevenly over time, with a floor so it never fully vanishes
// (stays readable). Keeps the real font shape + outline, just makes the fill breathe and wisp.
// Sample coordinate comes from VERTEX (control-local pixels), independent of the font atlas.

uniform float speed       : hint_range(0.0, 2.0) = 0.5;
uniform float density     : hint_range(0.0, 1.0) = 0.4;   // higher = more eroded / wispier
uniform float coord_scale : hint_range(0.005, 0.3) = 0.08; // noise frequency over the label
uniform float alpha_floor : hint_range(0.0, 1.0) = 0.55;  // minimum alpha so the number stays legible

varying vec2 v_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
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
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float t = TIME * speed;
	vec2 nc = v_pos * coord_scale;
	vec2 q = vec2(fbm(nc + vec2(0.0, t)), fbm(nc + vec2(3.1, -t)));
	float n = fbm(nc + q * 1.5 + vec2(t * 0.5, 0.0));
	float erode = smoothstep(density, density + 0.5, n);
	// Erode the glyph alpha unevenly, but never below alpha_floor so it stays readable.
	COLOR.a *= mix(alpha_floor, 1.0, erode);
}
