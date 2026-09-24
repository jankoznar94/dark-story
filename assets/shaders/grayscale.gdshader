shader_type canvas_item;
// The CSS `filter: grayscale(1)` a locked `.stop-card` carries. Godot has no equivalent
// built-in, and a `modulate` is NOT it — modulate SCALES the channels, so a locked card
// stayed fully coloured and just went dim. Jan's report on the locked map cards ("they
// should be dark") needs the desaturation the reference actually applies.
//
// Luminance weights are the CSS ones (Rec. 601), so the result matches `filter:grayscale(1)`
// and not a naive channel average.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb * COLOR.rgb;
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(rgb, vec3(grey), amount), tex.a * COLOR.a);
}
