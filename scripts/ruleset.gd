class_name Ruleset extends Resource
## 难度四档：每一档是一个文件（resources/rulesets/），标题页的"难度"里选，选了的记在存档里。
## 文件名开头的数字是它在选择页里排第几（由易到难）；新加一档就接着往下编号。
##
## 难度 = 每上一档多几条规矩。所以这里不是一个一个的加减数，而是一条一条的"规矩"：
## 每条规矩有自己的开关，开关后面跟着这条规矩自己的数。想调数值，只改 .tres，不用改代码。
##   想试新的一档：在编辑器里复制一份 .tres、改几个数就行，标题页里会自己多出来。
##
## 四档各自打开了哪些规矩（细节见各 .tres）：
##   简单      步数宽、每一跳多跳 0.7 格、无限重来、补给格多、手里的灯多
##   中等      步数刚够、无限重来、手里有两盏灯
##   困难      + 步数少一步且带过关（每关补一步、最多补到上限）、重来每关限 3 次、风向、多一道沟、手里的灯少
##   非常困难  + 不能重来、水车开了走回去还要扣步、夜巡（蜡烛烧完灯会灭）、补给格和道具都少、没有手里的灯
##
## 哪些数真的管用（拿"随手玩"的机器人一档一档量出来的，见 tools/tier_rates.gd 和 tools/playtest/rates.md）：
##   步数的宽紧（moves_add、moves_bonus、moves_cap_add）和带沟的道具有几件（lamp_gate_add、lamp_items_add）最管用；
##   贴极限（lamp_gap_add）、绕路（lamp_detour_add）、灯数比例（lamp_scale）几乎量不出差别；
##   想让某一档更好过，优先加"每一跳多跳多远"（reach_add），别减道具：道具和沟少了，长夜的随机棋盘反而容易摆不出
##   保证有解的局（简单档原先道具减两件，长夜后几更有 6% 摆不出来）；
##   夜巡只对"想得久"的玩家起作用，机器人是不想的（tools/tier_rates.gd 的 think 是按真人每步想多久代入的）

## 河灯怎么来
enum LampMode {
	DEALT,      ## 开局摆好，保证有一条一步不错就能收齐的路（能不能过看会不会找路）
	FLOW,       ## 边收边刷：新灯多半挨着灯刷，开局保证起点旁边有一盏
	RANDOM,     ## 边收边刷，纯随机（最早的玩法，运气成分大）
}

@export var id := ""                    ## 存档里记的是它，别和别的档重名
@export var title := ""                 ## 标题页里显示的名字
@export_multiline var summary := ""     ## 一段说明
@export_range(1, 9) var tier := 2       ## 第几档难度（1 简单、2 中等、3 困难、4 非常困难）：只用来在选择页里排出先后

@export_group("河灯", "lamp_")
@export var lamp_mode: LampMode = LampMode.DEALT
@export_range(0.0, 1.0) var lamp_flow_chain := 0.8    ## 边收边刷：新灯有多大概率刷在挨着灯的格子上
@export var lamp_scale := 1.0                       ## 每关收几盏灯，乘以它
@export_range(-0.5, 0.5) var lamp_gap_add := 0.0     ## 摆棋时"贴着极限跳"的比例，加减（越大越难）
@export_range(-0.5, 0.5) var lamp_detour_add := 0.0  ## 摆棋时绕路的程度，加减（越大岔路越多）
@export var lamp_items_add := 0                     ## 每关多摆（少摆）几件道具
@export var lamp_gate_add := 0                       ## 每关多摆（少摆）几件带沟的道具（后面紧跟着一道只有靠它才过得了的沟）

@export_group("跳得多远", "reach_")
@export var reach_add := 0.0              ## 【便利】每一跳多跳这么远（格）。0 是角色原本能跳多远
										##     简单档是 0.7：连击 2 就跳得过一道两格宽的墙（比如第 11 关"城垛"正中那一列，原先是连击 5），
										##     随手玩也不容易被困在半边棋盘上。每一关每一档都量过：0.5 时第 10 关反而变难，0.7 最好（见 rates.md）
@export_group("规矩：步数", "moves_")
@export var moves_add := 0              ## 每关的步数在角色的基础上加几步
@export var moves_carry := false        ## 【规矩】过关以后步数不清零，带过去
@export var moves_bonus := 0            ##   带过去的时侯，每过一关补几步
@export var moves_cap_add := 2          ##   带过去的步数最多比步数上限多出几步。0 是一关开头最多也就上限那几步

@export_group("规矩：没过一关", "retry_")
@export var retry_level := true         ## 【规矩】一关没过可以原地再来（灯还是原来那一局）
@export var retry_max := 0              ##   每关最多重来几次；0 是不限

@export_group("规矩：水车", "portal_")
@export var portal_free := true         ## 水车开了以后踩空格不扣步、不清连击。关掉就是【规矩】收齐灯以后走回水车还要花步数

@export_group("规矩：补给格", "spring_")
@export var spring_add := 0             ## 【规矩】每关在棋盘本来就有的基础上，再放（或拿掉）几个补给格

@export_group("规矩：手里的灯", "hold_")
@export var hold_lamps := 0             ## 【规矩】开局手里有几盏自己的灯，可以放到够得着的空格上（放一盏花一步）。0 是没有这条
@export var hold_cost := 1              ##   放一盏花几步
@export var hold_per_coin := 1          ##   捡到铜钱多几盏

@export_group("规矩：风向", "wind_")
@export var wind := false               ## 【规矩】每关有风向：顺风跳得远、逆风跳得近
@export_range(0.0, 1.0) var wind_bonus := 0.5         ##   顺风多跳多远（格）
@export_range(0.0, 1.0) var wind_penalty := 0.5       ##   逆风少跳多远（格）
@export var wind_floor := 1.0              ##   逆着风最近也还能跳这么远（格）。1.0 是一格总跳得动，风只管远跳；
										##     写 0 就是逆风连一格都跳不动（连击低的时候会被困住，河灯也常摆不出来）

@export_group("规矩：夜巡", "night_")
@export var night_watch := false        ## 【规矩】左上角有一支蜡烛在烧：蜡烧完，离你最远的那盏河灯就灭。
										##     摆好的一局里灯少了一盏就收不齐，所以这一关就守不住了
@export var night_seconds := 30.0       ##   一支蜡烧多久（秒）：一关开头看棋盘的时间，也是蜡最长能长回多少
@export var night_every := 6.0          ##   灭了一盏以后，蜡重新长回这么长（秒）
@export var night_gain := 3.0           ##   每跳一下，蜡长回几秒。想一步比它久，蜡就净短一截；一路都这么慢就烧完了

@export_group("长夜", "endless_")
@export var endless_carry := true       ## 长夜里步数带过去，每更补一步（生存压力）

## 选择页上"最多几步"那句要用的步数上限：默认角色（守夜人）的 5 步加上这一档的加减。
## 只用在选择页的一句话里；别的角色自己的步数不一样，游戏里真用的上限在 main.max_moves_left
func max_moves_hint() -> int:
	return 5 + moves_add

## 这一档一共有几条"加码的规矩"（越往后越多）：简单 0 条，中等 0 条，困难 3 条，非常困难 6 条。
## 手里的灯、多出来的补给格、少摆的道具是帮着过关的，不算。导出包自检拿它核对几档是由易到难排的
func rule_count() -> int:
	var n := 0
	if moves_carry: n += 1
	if not retry_level or retry_max > 0: n += 1
	if not portal_free: n += 1
	if wind: n += 1
	if night_watch: n += 1
	if spring_add < 0: n += 1
	return n

## 这一档打开了哪些规矩，一条一行（写在选择页上给玩家看的）。
## 步数、道具、补给格这几个加减是 小项，并成最后一行：不然非常困难那一档有九行，选择页的右栏放不下
func rule_lines() -> Array[String]:
	var lines: Array[String] = []
	if moves_carry: lines.append("步数带过关，每关补 %d 步%s" % [moves_bonus, "，最多 %d 步" % (max_moves_hint() + moves_cap_add) if moves_cap_add < 2 else ""])
	if not retry_level: lines.append("一关没过从头来")
	elif retry_max > 0: lines.append("每关最多重来 %d 次" % retry_max)
	else: lines.append("没过可以原地重来")
	if not portal_free: lines.append("水车开了以后，走回去还要花步数")
	if hold_lamps > 0: lines.append("手里有 %d 盏灯，可以放到空格上补救" % hold_lamps)
	if wind: lines.append("有风向：顺风跳得远、逆风跳得近")
	if night_watch: lines.append("夜巡：蜡烛烧完，最远的一盏河灯就灭")
	var small: Array[String] = []
	if reach_add > 0.0: small.append("每一跳多跳 %.1f 格" % reach_add)
	if moves_add > 0: small.append("每关步数多 %d 步" % moves_add)
	elif moves_add < 0: small.append("每关步数少 %d 步" % -moves_add)
	if lamp_gate_add > 0: small.append("多 %d 件带沟的道具" % lamp_gate_add)
	elif lamp_gate_add < 0: small.append("带沟的道具少 %d 件" % -lamp_gate_add)
	if lamp_items_add < 0: small.append("道具少 %d 件" % -lamp_items_add)
	elif lamp_items_add > 0: small.append("道具多 %d 件" % lamp_items_add)
	if spring_add > 0: small.append("补给格多 %d 个" % spring_add)
	elif spring_add < 0: small.append("补给格少 %d 个" % -spring_add)
	if not small.is_empty(): lines.append("，".join(small))
	return lines