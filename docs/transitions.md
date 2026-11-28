# 换关的过渡

过关换关、长夜的下一更、"再守这一关"、"重来"、玩到一半换难度、对战的轮战换棋盘，还有标题页和游戏之间换场景，
都要先把画面盖住、再掀开。这一段叫"过渡"。

平时用的是原来那一套（`tiles`）：一层石砖贴图的着色器淡入淡出，盖住、掀开各 0.5 秒。
别的样式在 `scripts/uis/transitions/` 里，每种一个文件。怎么加一种、怎么测、怎么录片子，都在这份文档里。

## 在哪儿

- `scripts/uis/scene_transition_control.gd`（`SceneTransitionControl`）：入口。`open(ctx)` 盖住，`close(ctx)` 掀开，
  都做完才返回。调它的是 `main.load_level`（换关）和 `SceneManager.load_scene_progress`（标题页和游戏之间）；
  开机的时侯标题页会 `close({"mode": "boot"})` 掀一次幕。它还量每一趟的时长和最长的一帧（`report()`）。
- `scripts/uis/transition_style.gd`（`TransitionStyle`）：样式的接口和公共工具。
- `scripts/uis/transitions/transition_<样式>.gd`：每一种样式。第一行写 `extends TransitionStyle`，**不写 `class_name`**
  （调度按样式名到这个目录里找文件，`load` 了直接 `new`）。着色器放 `shaders/transition_<样式>.gdshader`。
- 平时固定用 `ink` 墨迹晕开（`DEFAULT`，`scene_transition_control.gd`）。别的几种都还在，只是平时不用。
- 换一种：环境变量 `SW_TRANSITION=<样式>`（启动时读，不写存档）；或者在游戏里 `call pad_adapter.gd debug_transition <样式>`
  （不带参数是看最近一趟的数，再带一个数是往回数第几趟；`debug_transition random` 改成随机）。
- 写 `random` 是随机的：每一趟从 `RANDOM_POOL`（`lanterns` 河灯涌来、`steps` 石阶沉浮、`wheel` 镜头钻进水车、`ink` 墨迹晕开）里
  抽一种，不连着两趟一样。想增减就改那一个常量。`tiles`（原来的石砖墙）和 `ripple` 涟漪开合不在池里。
- 开机的时候要用的样式在黑幕底下建好、预热好（随机的话一池都建好），换关途中不现建（现建要加载、编译，会卡一下）。
- 有哪几种：`tiles`（原来的），`ripple` 涟漪开合，`lanterns` 河灯涌来，`steps` 石阶沉浮，`wheel` 镜头钻进水车，`ink` 墨迹晕开。

## 接口

```gdscript
extends TransitionStyle

func build() -> void:                 # 装上这个样式的时侯调一次：把要用的节点建出来（先藏着）
func cover(ctx: Dictionary) -> void:  # 盖住。做完再返回（里面可以 await）
func reveal(ctx: Dictionary) -> void: # 掀开。做完再返回
func dispose() -> void:               # 换样式的时侯调：收走自己加的节点、还回去借来的东西（默认已经做了这两件）
```

`ctx` 里是这一趟的事（`Dictionary`）：

| 键 | 是什么 |
|---|---|
| `mode` | `"level"` 换关（上面列的都算）；`"scene"` 标题页和游戏之间换场景；`"boot"` 开机掀幕（没盖过，直接掀） |
| `fast` | `true` = 换关换得快的局（长夜、轮战）：过渡要短 |
| `from` | 谁触发的，世界坐标（`Vector3`）。平时是主角这会儿站的地方；换场景、掀幕时没有（`null`） |
| `to` | 掀开以后主角站在哪儿，世界坐标。掀开的时侯有；盖住的时侯可能还没有 |
| `title` | 关卡名那一行（`"第 3 关 · 断桥"`）；`name` 关卡自己的名字（`"断桥"`）；`index` 第几关（从 1 数起）。换场景、掀幕的时侯没有 |
| `color` | 要去的这一关的底色（`LevelResource.base_color`）；`color_from` 离开的那一关的底色 |
| `level` | 要去的这一关（`LevelResource`）。换场景、掀幕的时侯没有；`main` 是 `Main` 节点（换场景的时侯可能还没有） |

`TransitionStyle` 上现成的工具：

| 工具 | 干什么 |
|---|---|
| `add(node, warm := false)` | 把节点加到 `ctl`（一个编号 10 的 `CanvasLayer`，压在所有界面上面）下面，记在账上，换样式时一起收走 |
| `screen_uv(world, fallback)` | 世界坐标的一点在画面上的位置（0 到 1，左上角是 0, 0） |
| `duration(ctx, normal, fast)` | 这一段该多长：平时的局用 `normal` 秒，`ctx.fast` 的局用 `fast` 秒 |
| `hold_camera(on)` | 按住镜头不跟主角（要自己摆弄镜头的样式用） |
| `full_rect(shader)` | 一张铺满画面的贴图节点，套着给的着色器 |
| `shader(id)` | `res://shaders/transition_<id>.gdshader` |

样式自己不是节点（是个普通的对象）：补间和定时器借 `ctl` 的——`ctl.create_tween()`、`ctl.get_tree().create_timer()`、
`ctl.get_tree().process_frame`。

节点用 `add(node, true)` 加上去的，装上样式以后会先"白画两帧"：着色器头一回画要编译，那一帧很长，
趁着开机的黑幕还在先花掉。所以这些节点在"还没开始"的状态下画出来必须什么都看不见——着色器整张透明。
别靠藏节点或者 `modulate`：藏着的节点不会画，着色器也就不编译。

## 最小的样子

底下是一个能跑的最简样式（从触发点扩散的一个圆盖住，再朝落点收回），照着这个架子往里填。
在服务器上验过：盖住、掀开各 0.5 秒，最长一帧 9 毫秒以内，盖住时四个角和正中都是同一层颜色，过渡前后画面逐像素一样。

```gdscript
extends TransitionStyle

var rect: TextureRect

func build() -> void:
	rect = add(full_rect(shader("probe")), true)      # shader("probe") 是 shaders/transition_probe.gdshader
	rect.visible = false                               # 预热是外面帮着做的；平时藏着，盖的时候自己设回可见

func cover(ctx: Dictionary) -> void:
	await _animate(screen_uv(ctx.from), Vector2(0.5, 0.5), 0.0, 1.0, duration(ctx, 0.5, 0.25))

func reveal(ctx: Dictionary) -> void:
	await _animate(Vector2(0.5, 0.5), screen_uv(ctx.get("to")), 1.0, 0.0, duration(ctx, 0.5, 0.25))
	rect.visible = false

func _animate(from: Vector2, to: Vector2, p_from: float, p_to: float, secs: float) -> void:
	rect.visible = true
	var m := rect.material as ShaderMaterial
	var size := ctl.get_viewport().get_visible_rect().size
	m.set_shader_parameter("aspect", size.x / size.y)
	var t := ctl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float) -> void:
		m.set_shader_parameter("centre", from.lerp(to, v))
		m.set_shader_parameter("progress", lerpf(p_from, p_to, v)), 0.0, 1.0, secs)
	await t.finished
```

```glsl
shader_type canvas_item;
uniform float progress = 0.0;                                 // 0 什么都看不见，1 盖满
uniform vec2 centre = vec2(0.5, 0.5);
uniform float aspect = 1.6;
uniform vec3 tint: source_color = vec3(0.42, 0.78, 0.70);
void fragment() {
	vec2 d = UV - centre;
	d.x *= aspect;
	float r = progress * 1.2;
	float a = 1.0 - smoothstep(r - 0.08, r + 0.08, length(d));
	COLOR = vec4(tint, a);
}
```

## 每一种样式都要守的

1. **盖住做完的那一刻，屏幕必须已经完全看不见后面的东西**（贴一层的样式）。调用的人紧接着就换棋盘。
2. **掀开做完的时候不留痕迹**：自己加的节点看不见了；借走的东西都还回去（`hold_camera(false)`、`modulate`、
   `visible`、改过的材质参数……）。连续换二十次关，画面和第一次进游戏的时侯一样，节点数不涨。
   节点在 `build()` 里建一次、反复用；别每次换关新建再释放。
3. **三种场合都要对**：换关（`from`、`to` 都有）；换场景（`mode == "scene"`，`from` 没有）；开机掀幕
   （`mode == "boot"`，没盖过就直接掀，`from` 也没有）。重来、换难度、轮战都走换关这一种，但 `to` 可能和上一关一样。
4. **时长**：平时的局盖住 0.35 到 0.7 秒、掀开 0.4 到 0.9 秒，两段加起来别超过 1.3 秒；`fast` 的局各 0.2 到 0.35 秒。
   量出来盖住或掀开不到 0.25 秒、或者超过 1.6 秒（`fast` 是 0.9 秒），检查就报没过。
5. **流畅**：盖住、掀开期间最长的一帧不超过 25 毫秒（服务器上量，见下面"怎么量"）。
   过渡途中别 `load` 资源、别新建带新着色器的节点——这些放在 `build()` 里。
6. **画面是 1152×720 的逻辑分辨率，掌机的窗口是 2560×1600**：着色器按 `UV` 写，宽高比从
   `ctl.get_viewport().get_visible_rect().size` 算，别写死像素。
7. **和游戏是一套观感**：墨色、石绿、朱砂、玉色、烛火色；不要蓝紫色调；字体是 `Tutorial.FONT`（手写体）；
   `Tutorial.make_label(字号, 颜色)` 能直接建一行字。不要新画大图：用现成的贴图、程序化的图形和着色器。
8. **别动公共文件**（别的样式也在同一份底座上做，动了合并时要打架）：`main.gd`、`scene_transition_control.gd`、
   `transition_style.gd`、`pad_adapter.gd`、`scene_manager.gd`、`tools/playtest/` 里的脚本和步骤文件、别人正在用的
   着色器和脚本（`lobby_*`、`stage_*`、`river_lamps.gd`、`opening*.gd*`）。要现成着色器的变体，复制一份改名再改。
   实在缺一个钩子：改最小的量，改动处写上注释"过渡样式 <样式> 需要"，并在最后的报告里逐条列出来。
9. 注释、命名和周围的代码一个样子（中文注释，讲清楚"为什么"）。

## 怎么量、怎么录

```bash
export SW_HOST=V100_222_TS                       # 外部那台 V100。标签用分给你的那一个（下面写成 aN）
tools/playtest/agent.sh aN setup                 # 第一次
tools/playtest/agent.sh aN sync                  # 每次改完代码
tools/playtest/agent.sh aN check                 # 只检查脚本解析不解析得过（快，先过这一道）
tools/playtest/agent.sh aN import                # 导入；加了着色器、贴图以后要跑

# 量两趟换关（第二趟才判）：盖住、掀开各多久，最长的一帧多长。不录片子，量出来才是真的帧时间
SW_TRANSITION=<样式> SW_OPENING=off SW_BOOT_WAIT=2 tools/playtest/agent.sh aN drive tools/playtest/steps_transition.txt trans_<样式>

# 录片子：第 1 关踩上水车 → 过渡 → 进第 2 关，机器人打的，难度固定用中等；帧回到 builds/transition/<样式>/
tools/playtest/agent.sh aN transition <样式>
tools/playtest/assemble_transition.sh <样式>     # 本机拼（要 ffmpeg）：<样式>.mp4、<样式>_slow.mp4、<样式>_sheet.jpg
```

- **看片子**：`builds/transition/<样式>_sheet.jpg` 是每 4 帧抽 1 张的拼图，先用它过一遍全过程；
  再看单帧 `builds/transition/<样式>/transition_NNNN.jpg`（全分辨率）。`marks.txt` 里三个数是录像开始、过渡开始、
  过渡结束的时刻（微秒）：`(过渡开始 − 录像开始) / 1000000 × 30` 就是过渡开始那一帧的帧号。`_slow.mp4` 是放慢 2.5 倍的。
- **就地放一遍**（不换关，调样式最快）：步骤文件里写 `call pad_adapter.gd debug_transition_test 0.5`（盖住、停 0.5 秒、掀开）。
  停多久是从盖住做完以后算的。要看盖严的样子就用 `debug_transition_test 3`，停着的时侯截图。
- **新标签第一次**：`setup` → `sync` → `import`，然后 `check` 才有意义（没导入过的时侯 `check` 会报一大串"找不到类型"，不是错）。
- **读量出来的数**：任何时侯 `call pad_adapter.gd debug_transition 0`。
- 录片的时侯游戏每帧要存一张图，那一趟的帧时间是 25 毫秒上下，不算数；判断卡没卡只看 `steps_transition.txt` 那一次。
- 本机不编译任何东西（也不装工具链）。本机只做：改代码、拼片子（ffmpeg、Pillow）、看图。

## 交什么

1. 样式的文件（`scripts/uis/transitions/transition_<样式>.gd`，着色器 `shaders/transition_<样式>*.gdshader`，导入生成的 `.uid` 一起提交）。
2. README 里"换关的过渡"那一节底下、自己这个样式的小节：一段话讲画面是什么、有哪些讲究、数都在哪儿调。
3. 测试结果：`steps_transition.txt` 的那一行 `RESULT 过渡：…`；另外跑一遍这几样，确认没把别的弄坏：
   `SW_OPENING=off SW_BOOT_WAIT=2 tools/playtest/agent.sh aN drive tools/playtest/steps_hud_back.txt hud_back`、
   同样地带上 `steps_aim.txt`、`steps_versus_play.txt`，以及 `SW_RULESET=normal tools/playtest/agent.sh aN drive tools/playtest/steps_rules.txt rules_normal`。
4. 片子留在 `builds/transition/` 里（`builds/` 不进仓库），最后的报告里写清观感、量出来的数、没做到的地方。

## 做头五种时踩过的坑

- **标题页河面着色器里的 `hash21` 数值不稳**（`lobby_river.gdshader`，`vnoise` 用它）。它头一步取 `p × 123.34` 的小数部分，
  输入到十几以上时小数只剩十几个比特；`vnoise` 又是拿格子角上的整数坐标算哈希的，相邻两个像素落在格子两边、算同一个角却得到不同的值，
  噪声就沿着格子边裂开——直缝、四角星、带直边的暗三角。拿方向向量或者带 `seed × 17` 这种大偏移当输入的地方一定中招。
  抄那份着色器的时侯把函数体换成下面这个（头一步取 `p × 0.1031` 的小数部分），调用不用动；标题页那一份没换，它只拿噪声调一点亮度，看不出来：

  ```glsl
  float hash21(vec2 p) {
  	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  	p3 += dot(p3, p3.yzx + 33.33);
  	return fract((p3.x + p3.y) * p3.z);
  }
  ```

- **没画过的材质上去补间 `shader_parameter/…` 会报错**（"does not exist in object"，那一段不动）：着色器是在显卡那头编译的，
  这一层头一回画过以后，材质上才有这些属性。所以样式要登记预热（`add(node, true)`）；底座的预热做完以前会先确认
  每种材质的参数都登记好了。平时是几种样式随机的，哪一种不预热，就要等到头一回抽到它才头一回画——镜头样式就这么错过一回
- **`FlowMap.png` 不是噪声图**：它是逐像素的随机色，拿它当噪声采样画出来是雪花点。要噪声就用现算的值噪声，或者 `voronoi.png`。
- **二维着色器吃到的是 sRGB 的数**：照抄三维水面着色器里"底色怎么变"的算式，画出来会暗十倍。同一个算式算完要再变回 sRGB。
- **录像存的 JPG 颜色可信**：同一帧和无损比，平均差 1.7 个色阶、最大 2.1。存 PNG 在服务器上每帧要两三百毫秒，帧率掉到每秒三四帧，别拿它录。
- **开机**：不播开场的时侯，黑幕撤得很快。标题页自己会 `close({"mode": "boot"})` 掀幕；底座让黑幕等样式预热完、掀幕开始了才撤，
  样式不用再为这个绕。要看开机的头几帧，用 `tools/playtest/agent.sh aN opening off 4 30`（它会报"没录对"，帧照样取回来）。
- **进游戏头一趟，掀开以前有两帧很长**（一百多毫秒）：是游戏自己释放标题页、第一次搭 Main 的开销，原来的样式也一样，藏在盖严的那一层底下。
- 服务器上几个标签同时录的时侯，存帧的目录是按标签分开的（`/tmp/sw_transition_<标签>_<样式>/`）；网络慢的时侯取帧会断，
  `agent.sh transition` 会接着传并核对本机和服务器上的帧数，不够就报"帧没取全"，再跑一遍就接着传。

## 现成能用的

- `shaders/lobby_river.gdshader`：标题页那条河——水纹、月亮和月光、六圈涟漪（`ripple0` 到 `ripple5`）。`scripts/uis/lobby_river.gd` 是怎么驱动它的。
- `shaders/stage_water.gdshader`：游戏里的水面。底色、水纹颜色、`ripple0` 到 `ripple5`（世界坐标）都是参数；`scripts/stage_backdrop.gd` 的 `ripple(xz, amp)` 能在河面上荡开一圈。
- `scripts/uis/river_lamps.gd`：标题页和游戏里背景那些漂着的河灯（一盏灯是精灵、光晕、倒影，带远近和前后遮盖）；`shaders/lobby_reflection.gdshader`。
- `shaders/opening_ink.gdshader`：开场动画里墨晕开的算法（`progress`、`origin`、`soft`）。
- `shaders/opening_cover.gdshader`：开场的底幕，能让开画面的四种方式。
- `shaders/scene_transition.gdshader`：原来那一种过渡。
- 印章：`scripts/uis/opening.gd` 的 `_seal()`（朱砂底、米色边、"守望"两个字，落下的动画在 542 行附近）。它是私有的：照着写，别改那个文件。
- 贴图：`assets/sprites/FlowMap.png`、`voronoi.png`、`tilesarray.png`、`tile.png`、`rect.png`。
- 音效只有现成的那些（`assets/audio/sfx/`：落地的水声、收灯、水车）；服务器上没有声音，加了也验不了，要加就在报告里说明。

## 五种样式的任务书

每一种的目标画面、必须做到的、要小心的地方。做完的标准都一样：片子读得出下面写的那个意思，上面"都要守的"九条都过。

### 1. `ripple` 涟漪开合

**画面。** 踩上水车，脚下那圈涟漪不消失，一圈一圈继续往外荡，把整个棋盘淹了——圈里是夜里的河面，
和标题页是同一条河（水纹、月亮、月光）。然后河面上题字：要去的这一关的名字。再然后河面以主角落脚的那一格为中心
破开一圈，圈外露出新的关卡，圈收到主角脚下为止。

**必须做到。**
- 盖住：主圈从 `from` 在画面上的位置荡到盖住最远的一角，后面跟着一到两圈淡一些的拖尾；圈边是一道亮的水纹
  （比河面亮，随扩散变淡）。用缓出（先快后慢）。
- 掀开：反过来，圈从"盖住全屏"收到 `to`，圈外是新关卡；圈边同样有亮边和拖尾。用缓入。
- 河面的底色从离开的那一关的底色（`color_from`）走到要去的这一关的底色（`color`）。
- 题字：圈里河面的正中，先淡入一行小字（巡夜是"第 N 关"，长夜是"第 N 更"），底下一个大字是关卡名
  （`ctx.name`；长夜是"长夜"），名字的右下角落一方印章。题字跟着掀开的那一圈一起走，不要为了它多等。
  只在真的过了上一关的时侯题（`index` 比上一趟大）；重来、换难度、长夜、对战都不题。印章落下不要声音。
- `fast` 的局：不题字，两段各 0.25 秒上下。

**要小心的。** 河面必须真的盖严：主圈盖到最远的一角以后，四角都不能漏出棋盘。
着色器复制 `lobby_river.gdshader` 改名再改，标题页那一份别动。宽高比按实际画面算。

### 2. `lanterns` 河灯涌来

**画面。** 远处（画面上方）涌来一大片河灯，越涌越近、越密，暖光把画面照亮、盖满，像一条灯的河从上游压过来。
然后灯继续朝近处涌出去、散开，新的关卡从灯底下露出来——像这一关是河灯送来的。

**必须做到。**
- 盖住：灯从远处涌来，由疏到密，同时一层暖色的光海跟着涨起来，最后一瞬整屏盖严（取那一帧的四个角和正中看，
  不能漏出棋盘）。
- 掀开：灯散开或者涌出画面，新关卡露出来；可以从 `to` 那儿先露（主角落脚的地方最先见天）。
- 灯有远近：远处的小而密、暗一些，近处的大、亮，前后有遮盖；左右轻轻晃。
- 暖光是烛火色，底下的夜色跟着 `color` 走。

**要小心的。** 这是五种里最容易乱、也最吃性能的一种。满屏叠几百个带光晕的大精灵，帧时间很容易上去：
近处只放几十盏真的精灵，密度靠一张全屏的"光海"着色器撑（程序化的光斑，`voronoi.png` 能当噪声用）。
`river_lamps.gd` 那套是按标题页那条河的慢速度漂的，样式要自己驱动灯的位置和速度——别改那个文件，
需要的话把要的部分抄成样式文件里的内部类。不要让画面闪：亮度是连续涨上去的，不是一瞬间的白。

### 3. `steps` 石阶沉浮

**画面。** 踩上水车，石砖从水车那一格往外一圈一圈沉进水里，河面合拢，只剩那条河。然后新的一关的石阶
从主角落脚的那一格往外一圈一圈浮出水面，河灯落定。

**必须做到。**
- 盖住：按到水车的格子距离排队，一圈一圈往下沉（每块沉下去用二三十毫秒，带一点下沉的加速），
  沉下去的地方河面上荡开一小圈涟漪。站在格子上的河灯、道具跟着走。主角最后沉（或者原地淡出）。
- 掀开：新棋盘的石阶从 `to` 往外一圈一圈浮上来，带一点过冲；河灯和主角跟着自己那一块一起上来，
  不能出现"灯悬在半空等石阶"或者"主角先站着、石阶后到"。
- 过渡做完，每一块石阶、每一盏灯、主角的位置和平时完全一样（`debug_state` 里棋盘的登记不能乱）。

**要小心的。** 这是唯一一种把换棋盘暴露在人眼前的样式：`cover()` 返回以后调用的人才换棋盘，
那一下的载入（几十毫秒的一帧）是看得见的。要把它藏好——比如那一瞬让镜头贴近水面、画面暗一下（潜进水里，
再浮上来），或者别的办法；总之不能看见棋盘"闪一下空了再冒出来"。动石阶有两条路：逐块挪 `Tile` 节点，
或者给石阶的材质加一个顶点位移的参数（所有石阶共用，每帧只改一个数）——先看 `scripts/tile.gd`、`scripts/grid.gd`
里材质是怎么用的再定。报告里要如实写出"中间"那一段最长的一帧是多少。

### 4. `wheel` 镜头钻进水车

**画面。** 踩上水车，镜头朝水车推过去，水车在眼前转；水面糊上来，画面进了水里。再出来时已经是新的一关：
水从画面上退掉，镜头从贴近水面的地方拉回平时的机位。

**必须做到。**
- 盖住：镜头从现在的位置推向水车（推到离水车还有一段就停，别贴上去），视角收窄一点；水层从四面涌到中间盖严，
  带水下的暗青色调和一点焦散的纹。
- 掀开：水层退去，镜头从低位拉回平时的机位（`main.fit_camera()` 定的那个高低远近、`main.camera_target_x()` 定的那个左右）。
- 过渡期间用 `hold_camera(true)` 按住镜头（平时它每一帧跟着主角走），做完放开，并把镜头的位置和视角完全还原。
  就算中途出错，镜头也不能留在奇怪的地方。
- 换场景、掀幕、重来的时侯没有水车可推：只做水层。
- `fast` 的局：不推镜头，只做水层，快进快出。

**要小心的。** 掌机离眼睛近，最容易晕的就是这一种：不转镜头，推进的距离不超过现在到水车的七成，
视角变化不超过 25 度，每一段不超过 0.45 秒。镜头的代码在 `main.gd`（`camera_3d`、`camera_hold`、`fit_camera`、
`camera_target_x`、`camera_dist` 那几个）；别改它们，只调用。

### 5. `ink` 墨迹晕开

**画面。** 一滴墨落在水车那儿，在纸上晕开——边是不规则的、带着毛刺，一路吞掉棋盘。满纸都是墨。
然后墨褪下去：从主角落脚的那儿先亮起来，往外化开，新的关卡从墨底下出来。

**必须做到。**
- 盖住：墨从 `from` 晕到盖住全屏；边缘是自然的不规则形状（不是圆），墨边上有一道更深的湿边和几缕渗开的须；
  用缓出。
- 墨不是纯黑：深墨里透一点要去的这一关的底色（一成上下），仔细看是一层有厚薄的墨，不是一块纯色。
- 掀开：墨从 `to` 那儿化开、褪净；化开的边和晕开的边是同一种质感。
- 可选：墨将退未退的时侯，用留白显一下关卡名。

**要小心的。** `opening_ink.gdshader` 里已经有晕开的算法，复制一份改名再改。
这一种做起来最省，所以更要在质感上下功夫：纸的纹、墨的厚薄、边的毛刺——做不到位就是一块黑色遮罩，
那就没有意思了。
