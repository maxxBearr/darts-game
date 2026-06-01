shader_type canvas_item;

// Radial shockwave that expands outward from a dart hit point.
// Geometry is clipped to the hit segment polygon, so the wave
// naturally stops at ring boundaries.

// Normalized hit position (board-local pixels / board_radius).
uniform vec2 hit_point = vec2(0.0, 0.0);

// 0..1 progress of the wave (driven by tween or manual tick).
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// How far the wave travels in normalized board units at progress=1.
uniform float wave_reach : hint_range(0.05, 1.0) = 0.35;

// Width of the bright leading edge band (normalized).
uniform float edge_width : hint_range(0.01, 0.2) = 0.06;

// Width of the softer glow trail behind the edge.
uniform float trail_width : hint_range(0.01, 0.4) = 0.12;

// Peak brightness of the leading edge (additive).
uniform float edge_intensity : hint_range(0.0, 3.0) = 1.8;

// Brightness of the trail glow.
uniform float trail_intensity : hint_range(0.0, 2.0) = 0.6;

// Tint color for the shockwave (white = neutral flash, gold = warm).
uniform vec4 wave_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

// Board radius for converting vertex coords to normalized space.
uniform float board_radius : hint_range(50.0, 1000.0) = 340.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 uv = local_pos / board_radius;
	float dist = distance(uv, hit_point);

	float wave_radius = progress * wave_reach;

	// Leading edge: narrow bright band at the wavefront
	float edge_band = 1.0 - smoothstep(0.0, edge_width, abs(dist - wave_radius));

	// Trail: softer glow behind the edge
	float trail_band = smoothstep(0.0, trail_width, wave_radius - dist);
	trail_band *= 1.0 - smoothstep(0.0, edge_width * 0.5, dist - wave_radius);

	// Fade everything out as progress advances
	float fade = 1.0 - smoothstep(0.3, 1.0, progress);

	float intensity = edge_band * edge_intensity + trail_band * trail_intensity;
	intensity *= fade;

	// Additive blend: boost the underlying segment color
	COLOR.rgb += wave_color.rgb * intensity;
	COLOR.a *= intensity * wave_color.a;
}
