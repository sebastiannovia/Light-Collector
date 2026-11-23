shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D player_texture : filter_linear, repeat_disable;
uniform vec3 player_uv_x;
uniform vec3 player_uv_y;
uniform bool player_flip_h = false;
uniform bool player_flip_v = false;
uniform float occluded_opacity : hint_range(0.0, 1.0, 0.01) = 0.2;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 point = vec3(world_position, 1.0);
	vec2 player_uv = vec2(dot(player_uv_x, point), dot(player_uv_y, point));
	if (all(greaterThanEqual(player_uv, vec2(0.0))) && all(lessThanEqual(player_uv, vec2(1.0)))) {
		if (player_flip_h) {
			player_uv.x = 1.0 - player_uv.x;
		}
		if (player_flip_v) {
			player_uv.y = 1.0 - player_uv.y;
		}
		float coverage = texture(player_texture, player_uv).a;
		COLOR.a *= mix(1.0, occluded_opacity, smoothstep(0.06, 0.65, coverage));
	}
}
