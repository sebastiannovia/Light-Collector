shader_type canvas_item;

uniform float saturation : hint_range(1.0, 1.5, 0.01) = 1.15;

void fragment() {
	vec4 sampled_color = COLOR;
	float luminance = dot(sampled_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 saturated_color = mix(vec3(luminance), sampled_color.rgb, saturation);
	COLOR = vec4(saturated_color, sampled_color.a);
}
