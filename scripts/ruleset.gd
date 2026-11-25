class_name Ruleset extends Resource
## 一套玩法方案的全部可调项。resources/rulesets/ 下每个文件是一套，标题页的"方案"里选，选了的记在存档里。
## 文件名开头的数字是它在选择页里排第几（由易到难）；新加一套就接着往下编号。
## 想试新方案：在编辑器里复制一份 .tres、改几个数就行，不用改代码，标题页里会自己多出来。

## 河灯怎么来
enum LampMode {
	DEALT,      ## 开局摆好，保证有一条一步不错就能收齐的路（能不能过看会不会找路）
	FLOW,       ## 边收边刷：新灯多半挨着灯刷，开局保证起点旁边有一盏
	RANDOM,     ## 边收边刷，纯随机（最早的玩法，运气成分大）
}

@export var id := ""                    ## 存档里记的是它，别和别的方案重名
@export var title := ""                 ## 标题页里显示的名字
@export_multiline var summary := ""     ## 一段说明

@export_group("河灯")
@export var lamp_mode: LampMode = LampMode.DEALT
@export_range(0.0, 1.0) var flow_chain := 0.8    ## FLOW：新灯有多大概率刷在挨着灯的格子上
@export var lamps_scale := 1.0                  ## 每关收几盏灯，乘以它
@export_range(-0.5, 0.5) var gap_add := 0.0      ## 摆棋时"贴着极限跳"的比例，加减（越大越难）
@export_range(-0.5, 0.5) var detour_add := 0.0   ## 摆棋时绕路的程度，加减（越大岔路越多）

@export_group("道具")
@export var items_add := 0              ## 每关多摆（少摆）几件道具

@export_group("步数")
@export var moves_add := 0              ## 步数在角色的基础上加几步
@export var moves_carry := false        ## 巡夜里过关以后步数不清零，带过去
@export var moves_bonus := 0            ## 带过去的方案里，每过一关补几步
@export var portal_free := true         ## 水车开了以后踩空格不扣步、不清连击
@export var retry_level := true         ## 巡夜里一关没过，可以原地再来这一关

@export_group("长夜")
@export var endless_carry := true       ## 长夜里步数带过去，每更补一步（生存压力）
