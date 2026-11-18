shader_type canvas_item;
render_mode blend_mix;

uniform bool fade_enabled = false;
uniform vec2 player_screen_uv = vec2(-2.0, -2.0);
uniform float fade_radius_px : hint_range(16.0, 180.0, 1.0) = 82.0;
uniform float edge_softness_px : hint_range(1.0, 80.0, 1.0) = 26.0;
uniform float occluded_opacity : hint_range(0.0, 1.0, 0.01) = 0.2;

void fragment() {
	vec4 pixel_color = texture(TEXTURE, UV) * COLOR;
	if (fade_enabled) {
		vec2 pixel_delta = (SCREEN_UV - player_screen_uv) / SCREEN_PIXEL_SIZE;
		float distance_to_player = length(pixel_delta);
		float visible_alpha = smoothstep(fade_radius_px - edge_softness_px, fade_radius_px + edge_softness_px, distance_to_player);
		pixel_color.a *= mix(occluded_opacity, 1.0, visible_alpha);
	}
	COLOR = pixel_color;
}
