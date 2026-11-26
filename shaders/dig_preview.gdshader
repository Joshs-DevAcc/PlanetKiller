shader_type spatial;
// See-through bubble showing the size of the next dig: clear in the middle,
// glowing at the edges.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.92, 0.6, 1.0);

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb;
	ALPHA = pow(rim, 3.0) * 0.55 + 0.03;
}
