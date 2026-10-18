extends Node2D

## 单颗炸弹的绘制节点：参与与角色相同的 y 深度排序。

var bomb: Bomb = null
var anim_time := 0.0

func _draw() -> void:
	if bomb != null:
		MapArt.draw_bomb(self, bomb, anim_time)
