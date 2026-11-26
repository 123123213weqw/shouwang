class_name VersusRules extends Resource
## 一套对战玩法的数：时间、对手多快、目标多少、棋盘多大……改 .tres 就行，不用动代码。
## resources/versus/<玩法 id>.tres 一份；文件不在（或者某一项没写）就用这里给每个玩法定的默认值。

const FIELDS := {
	"rush": {
		"board_index": 5, "lamps": 11, "items": 0, "gap": 0.05, "detour": 0.3,
		"time_limit": 60.0, "foe_pace": 1.05, "my_pace": 1.2, "foe_edge": 0,
		"lead_lose": 3, "share_goal": 0.7, "foe_reach": 1.7, "bonus_time": 15.0, "foe_think": 0.7,
	},
	"shadow": {
		"board_index": 3, "lamps": 6, "items": -1, "gap": -1.0, "detour": -1.0,
		"time_limit": 0.0, "foe_pace": 1.5, "my_pace": 0.9, "foe_edge": 0,
		"lead_lose": 3, "share_goal": 0.7, "foe_reach": 1.7, "bonus_time": 15.0, "foe_think": 0.7,
	},
	"territory": {
		"board_index": 6, "lamps": 0, "items": 0, "gap": 0.0, "detour": 0.0,
		"time_limit": 60.0, "foe_pace": 2.4, "my_pace": 1.0, "foe_edge": 0,
		"lead_lose": 3, "share_goal": 0.7, "foe_reach": 1.7, "bonus_time": 15.0, "foe_think": 0.7,
	},
	"blitz": {
		"board_index": 0, "lamps": 5, "items": 1, "gap": 0.0, "detour": 0.3,
		"time_limit": 45.0, "foe_pace": 1.0, "my_pace": 0.85, "foe_edge": 0,
		"lead_lose": 3, "share_goal": 0.7, "foe_reach": 1.7, "bonus_time": 15.0, "foe_think": 0.7,
	},
	"duel": {
		"board_index": 7, "lamps": 10, "items": 0, "gap": 0.05, "detour": 0.3,
		"time_limit": 0.0, "foe_pace": 0.7, "my_pace": 0.9, "foe_edge": 2,
		"lead_lose": 3, "share_goal": 0.7, "foe_reach": 1.7, "bonus_time": 15.0, "foe_think": 0.7,
	},
}

@export var board_index := 0        ## 用巡夜第几张棋盘（从 0 数：0 是第 1 关"石步"）
@export var lamps := 10             ## 摆几盏灯
@export var items := 0              ## 摆几件道具（-1 = 这种玩法不改，照关卡本来那样）
@export_range(-1.0, 1.0) var gap := -1.0      ## 摆棋的"贴极限"（-1 = 不改）
@export_range(-1.0, 1.0) var detour := -1.0   ## 摆棋的绕路程度（-1 = 不改）
@export var time_limit := 60.0      ## 一局限时几秒（0 = 不限时）
@export var bonus_time := 15.0      ## 轮战：过一张棋盘接几秒
@export var foe_pace := 1.2         ## 对手几秒走一步（对弈里是"想几秒"）
@export var my_pace := 1.0          ## 演示和自动试玩时，主角几秒走一步
@export var foe_edge := 0           ## 对弈：对手的跳跃距离按"多收了几盏"算
@export var lead_lose := 3          ## 追影：被甩开几盏就输
@export_range(0.1, 1.0) var share_goal := 0.7   ## 夺岸：要让几成格子同时亮着
@export var foe_reach := 1.7        ## 夺岸：熄灯人一步够多远（格）
@export var foe_think := 0.7        ## （留给以后：对手想事的时间）

## 某个玩法用哪一套数：有 .tres 就读它（它说什么就是什么），没有就用上面 FIELDS 里的默认值
static func load_for(id: String) -> VersusRules:
	var path := "res://resources/versus/%s.tres" % id
	if ResourceLoader.exists(path):
		var r := load(path) as VersusRules
		if r != null: return r
	var d := VersusRules.new()
	if FIELDS.has(id):
		for k in FIELDS[id]: d.set(k, FIELDS[id][k])
	return d
