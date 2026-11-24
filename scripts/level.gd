class_name Level extends Node3D
## 一关棋盘的容器节点：里面装着所有格子和终点传送门。运行时由 Grid.build() 搭出来，不放场景文件。

@onready var tiles_container: Node3D = $TilesContainer
@onready var end_portal: Fish = $EndPortal
