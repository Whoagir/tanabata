shader_type canvas_item;

// Параметры metaballs
uniform int max_balls = 100;
uniform vec2 ball_positions[100];
uniform float ball_radius = 30.0;
uniform float threshold = 1.0;

// Цвета
uniform vec4 wall_color : source_color = vec4(0.51, 0.55, 0.57, 0.85);
uniform vec4 edge_color : source_color = vec4(0.57, 0.59, 0.6, 1.0);
uniform float edge_width = 2.0;

void fragment() {
	vec2 pos = FRAGCOORD.xy;
	
	// Вычисляем metaball field
	float field = 0.0;
	for (int i = 0; i < max_balls; i++) {
		vec2 ball_pos = ball_positions[i];
		if (ball_pos.x == 0.0 && ball_pos.y == 0.0) {
			break; // Пустая позиция
		}
		
		float dist = distance(pos, ball_pos);
		if (dist < ball_radius * 2.0) {
			// Inverse square falloff для smooth blend
			field += (ball_radius * ball_radius) / (dist * dist);
		}
	}
	
	// Применяем threshold
	if (field >= threshold) {
		// Внутри metaball
		float edge_factor = smoothstep(threshold, threshold + 0.3, field);
		vec4 color = mix(wall_color, edge_color, edge_factor);
		COLOR = color;
	} else {
		// Снаружи - прозрачно
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
