shader_type canvas_item;
render_mode unshaded;

uniform vec4 eye_color : source_color = vec4(0.9255, 0.5843, 0.3216, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.34, 1.0);
uniform vec4 sword_color : source_color = vec4(1.0, 0.94, 0.69, 1.0);
uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec2 sprite_pixel_size = vec2(0.00909, 0.00541);
uniform float color_tolerance = 0.16;
uniform float night_strength = 0.0;
uniform float sword_strength = 0.0;
uniform float sword_radius = 4.0;
uniform float body_pulse = 0.0;

float eye_mask_at(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec4 texel = texture(sprite_texture, uv);
	float color_distance = distance(texel.rgb, eye_color.rgb);
	float color_match = 1.0 - smoothstep(color_tolerance * 0.45, color_tolerance, color_distance);
	return color_match * smoothstep(0.1, 0.8, texel.a);
}

float sword_mask_at(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec4 texel = texture(sprite_texture, uv);
	float color_distance = distance(texel.rgb, vec3(0.996, 0.863, 0.518));
	float color_match = 1.0 - smoothstep(0.035, 0.09, color_distance);
	return color_match * smoothstep(0.25, 0.8, texel.a);
}

void fragment() {
	vec4 texel = texture(sprite_texture, UV);
	float eye_core = eye_mask_at(UV);
	float inner_halo = 0.0;
	float outer_halo = 0.0;
	float sword_core = sword_mask_at(UV);
	float sword_inner = 0.0;
	float sword_outer = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		vec2 direction = vec2(cos(angle), sin(angle));
		inner_halo = max(inner_halo, eye_mask_at(UV + direction * sprite_pixel_size * 2.0));
		outer_halo = max(outer_halo, eye_mask_at(UV + direction * sprite_pixel_size * 5.0));
		sword_inner = max(sword_inner, sword_mask_at(UV + direction * sprite_pixel_size * 2.0));
		sword_outer = max(sword_outer, sword_mask_at(UV + direction * sprite_pixel_size * sword_radius));
	}
	float halo = max(inner_halo * 0.48, outer_halo * 0.22) * (1.0 - eye_core);
	float sword_halo = max(sword_inner * 0.5, sword_outer * 0.28) * (1.0 - sword_core);
	vec4 result = texel * COLOR;
	result.rgb *= 1.0 + max(body_pulse, 0.0);
	float strength = max(night_strength, 0.0);
	result.rgb += glow_color.rgb * strength * (eye_core * 0.8 + halo * 0.72);
	result.a = max(result.a, halo * strength * 0.52 * COLOR.a);
	float blade_strength = max(sword_strength, 0.0);
	result.rgb += sword_color.rgb * blade_strength * (sword_core * 0.8 + sword_halo * 0.9);
	result.a = max(result.a, sword_halo * blade_strength * 0.45 * COLOR.a);
	COLOR = result;
}
