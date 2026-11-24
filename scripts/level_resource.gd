class_name LevelResource extends Resource

## 一关的参数。棋盘用字符画写出来（map，格式见 BoardGen.parse_map），主线关卡用它。
## 无尽模式不在这里定义，它的棋盘和参数由 BoardGen 按关数现算。

@export var level_name := ""
@export var chapter := 1
@export var map: Array[String]

@export var base_color: Color
@export var max_moves_left:= 10
@export var fish_before_end_portal:= 10
@export var starting_credits := 5
