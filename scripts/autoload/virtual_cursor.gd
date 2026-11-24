extends Control
# 虚拟光标的绘制（配 pad_adapter.gd）

var pos_to_draw := Vector2.ZERO
var is_hot := false

func _draw() -> void:
	var ring: Color = Color(1.0, 0.85, 0.2, 0.95) if is_hot else Color(0.2, 0.95, 1.0, 0.9)
	draw_circle(pos_to_draw, 9.0, Color(0, 0, 0, 0.35))
	draw_arc(pos_to_draw, 9.0, 0.0, TAU, 32, ring, 2.5, true)
	draw_line(pos_to_draw + Vector2(-15, 0), pos_to_draw + Vector2(-5, 0), ring, 2.0)
	draw_line(pos_to_draw + Vector2(5, 0), pos_to_draw + Vector2(15, 0), ring, 2.0)
	draw_line(pos_to_draw + Vector2(0, -15), pos_to_draw + Vector2(0, -5), ring, 2.0)
	draw_line(pos_to_draw + Vector2(0, 5), pos_to_draw + Vector2(0, 15), ring, 2.0)
