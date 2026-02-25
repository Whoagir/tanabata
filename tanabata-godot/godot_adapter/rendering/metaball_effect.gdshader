shader_type canvas_item;

// Массив позиций стен (мировые координаты)
uniform vec2 wall_positions[100];
uniform int wall_count = 0;
uniform vec2 preview_position = vec2(0.0, 0.0);  // Preview курсора
uniform bool has_preview = false;
uniform float ball_radius = 25.0;
uniform float threshold = 1.2;

// Цвета стен (приглушенные для плавного слияния)
uniform vec4 liquid_color : source_color = vec4(0.51, 0.55, 0.57, 0.3);
uniform vec4 edge_glow : source_color = vec4(0.57, 0.59, 0.6, 0.4);

void fragment() {
	// Мировые координаты
	vec2 canvas_size = vec2(3000.0, 3000.0);
	vec2 world_pos = UV * canvas_size - vec2(1500.0, 1500.0);
	
	// Вычисляем metaball field
	float field = 0.0;
	
	// Существующие стены
	for (int i = 0; i < wall_count && i < 100; i++) {
		vec2 ball_pos = wall_positions[i];
		float dist = distance(world_pos, ball_pos);
		
		if (dist < ball_radius * 3.0) {
			float r2 = ball_radius * ball_radius;
			float d2 = max(dist * dist, 1.0);
			field += r2 / d2;
		}
	}
	
	// Preview позиция
	if (has_preview) {
		float dist = distance(world_pos, preview_position);
		if (dist < ball_radius * 3.0) {
			float r2 = ball_radius * ball_radius;
			float d2 = max(dist * dist, 1.0);
			field += r2 / d2;
		}
	}
	
	// Рендерим если field больше threshold
	if (field >= threshold) {
		float edge_strength = smoothstep(threshold, threshold + 0.5, field);
		vec4 color = mix(liquid_color, edge_glow, edge_strength * 0.3);
		COLOR = color;
	} else if (field >= threshold * 0.7) {
		float edge_alpha = smoothstep(threshold * 0.7, threshold, field);
		COLOR = vec4(liquid_color.rgb, liquid_color.a * edge_alpha);
	} else {
		discard;
	}
}
