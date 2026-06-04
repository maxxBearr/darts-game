shader_type canvas_item;
// Hotspot smoke — "value lives on the board" headline flair.
//
// Multi-tone smoke in the wedge's OWN color family: it mixes between a darker and a lighter shade
// of the ring color (passed as color_a / color_b) using a second noise field, so a green ring gets
// several greens, a red ring several reds, black gets greys-into-black, white gets shades of cream.
// That internal variation is what makes it legible on every wedge.
//
// Normal alpha blend (NOT additive) so it reads on light wedges too, with noise-driven negative
// space so the ring still shows through the gaps (enhances rather than fully overrides). Sits on a
// Polygon2D shaped to the ring slice, sampling noise from the vertex position (Polygon2D has no
// useful UV by default). The "+N" value rides on top as a separate (smokified) Label.

// ---- Shades of the wedge color (passed in from dartboard._rebuild_hotspot_shader_layer) ----
uniform vec4  color_a : source_color = vec4(0.4, 0.05, 0.05, 1.0); // darker shade
uniform vec4  color_b : source_color = vec4(1.0, 0.4, 0.4, 1.0);   // lighter shade
uniform float opacity     : hint_range(0.0, 1.0) = 0.9;  // max smoke opacity (gaps show the ring)
uniform float density     : hint_range(0.0, 1.0) = 0.20; // coverage threshold (higher = sparser)
uniform float speed       : hint_range(0.0, 2.0) = 0.35; // drift speed
uniform float warp_amount : hint_range(0.0, 1.0) = 0.8; // domain-warp strength (wispiness)
uniform float coord_scale : hint_range(0.001, 0.1) = 0.064;// noise frequency over board-local pixels

// ---- Optional baked value glyph (needs poly.uv set; off by default) ----
uniform bool      use_glyph = false;
uniform sampler2D glyph_tex : hint_default_transparent;
uniform float     glyph_core : hint_range(0.0, 1.0) = 0.6;

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
	for (int i = 0; i < 5; i++) {
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
	vec2 nc = v_pos * coord_scale;
	float t = TIME * speed;

	// Domain warp so puffs curl and drift like smoke.
	vec2 q = vec2(fbm(nc + vec2(0.0, t)), fbm(nc + vec2(5.2, 1.3 - t)));
	float smoke = fbm(nc + q * (warp_amount * 4.0) + vec2(t * 0.5, 0.0));
	smoke = smoothstep(density, 1.0, smoke); // shape into puffs with negative space

	// Second, slower noise field selects the shade so the smoke has many tones of the wedge color.
	float tone = fbm(nc * 0.7 + q * 2.0 + vec2(-t * 0.3, t * 0.2));
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(tone, 0.0, 1.0));

	float alpha = smoke * opacity;
	if (use_glyph) {
		float g = texture(glyph_tex, UV).a;
		alpha = max(g * glyph_core, g * smoke) * opacity;
	}

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0) * COLOR.a);
}
