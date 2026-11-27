# 守望

江南水乡题材的回合制跳棋小品，Godot 4 工程。守塘的人夜里提灯出门，在河面上一格一格地跳，把河灯收齐，水车就开，走进去过关。

![标题页](docs/screenshots/title.jpg)

![棋盘](docs/screenshots/board.jpg)

## 玩法

每局在一张浮在水面的棋盘上进行，河灯开局就摆好。从起点出发，沿着灯一盏一盏地收。

- 落在有灯的格子上不扣步数，连击 +1。连击越高，跳得越远。
- 踩到空格子扣一步，连击清零。主角头顶的数字是还能错几步。
- 收齐这一关的灯，水车就开。水车开了以后踩空格不再扣步，走进去过关。
- 有的沟只有靠道具才过得了，看准了再跳。
- 收灯给技能充能，充满了可以放一次技能。
- 一关没过可以原地再来，灯还是原来那一局（默认的方案下）。

格子有四种：普通格；脆格，离开后碎掉，过一会儿长回来；障碍，落不上去；补给格，踩上去不扣步数反而加两步，每格每关只能用一次。

每关摆好的这一局是生成出来的，生成的时候就保证有一条一步不错就能收齐的路线。能不能过看会不会找路，不看运气。

### 道具

每关路线上摆着几件道具，跳上去捡。九种道具各管一件事：

| 道具 | 图标 | 捡到之后 |
|---|---|---|
| 莲蓬 | `combooo-1.png` 到 `combooo-6.png` | 连击 +3 |
| 纸伞 | `upgrade-umbrella.png` | 下一跳跳得特别远 |
| 草鞋 | `upgrade-shoe.png` | 这一关每一跳都更远 |
| 斗笠 | `hat.png` | 挡一次踩空（不扣步，连击也不断） |
| 钓竿 | `upgrade-cane.png` | 收走最远的两盏灯 |
| 捞网 | `upgrade-magnet.png` | 河灯都向你挪两格 |
| 水车 | `portal.png` | 卷走身边两格内的灯 |
| 食盒 | `chest.png` | 步数 +3 |
| 铜钱 | `clover.png` | 身边买来两件道具 |

图标都在 `assets/sprites/upgrades/`。另有蒸笼（`heart.png`，步数 +1），只在步数没带满进关的方案里出现。

### 两种模式

巡夜是主线，12 关，三章各四关，每章一种主色：水乡生活是石绿，家族传承是赭石，节庆巡游是朱砂。第一章学会连击跳，第二章开始有道具和沟，第三章棋盘大、路线长。巡夜里每一关是固定的一局，练的就是它。

长夜是无尽模式，棋盘和灯每次现摆，越往后越大、路线越长。步数从上一更带过去，每更补一步。

### 六位角色

| 角色 | 技能 | 怎么解锁 |
|---|---|---|
| 守夜人 | 点灯，两盏新的河灯落在身边 | 一开始就有 |
| 钓叟 | 甩竿，收走最远的两盏河灯 | 打到第 5 关 |
| 船家少年 | 一篙撑到底，这一步想跳多远都行 | 连击到 10 |
| 渔娘 | 撒网，把河灯都揽过来 | 一步未错地过一关 |
| 货郎 | 打开货担，身边落下一件道具 | 得分到 1000 |
| 小鼓手 | 敲一阵鼓，变出一枚莲蓬 | 一步未错、连击到 10 地过一关 |

小鼓手的连击上限更高，鼓点密了步子反而短。

## 玩法方案

规则里能调的数都收在 `scripts/ruleset.gd` 里，`resources/rulesets/` 下每个文件是一套。标题页的「方案」里选，选了的记在存档里。

选择页里由易到难排：

| 方案 | 河灯 | 步数 | 一关没过 | 适合 |
|---|---|---|---|---|
| 灯谱（默认） | 开局摆好，保证有解 | 每关满格 | 可以原地再来 | 第一次玩 |
| 流水 | 边收边刷，新灯多半挨着灯 | 每关满格 | 可以原地再来 | 喜欢节奏随手一点 |
| 疾走 | 摆好，灯少三成、路线直 | 少一步 | 可以原地再来 | 短平快 |
| 万灯 | 摆好，每关多两件道具，跳也松一些 | 多两步 | 可以原地再来 | 想把玩道具 |
| 长明 | 摆好，跳更紧、道具更少 | 带到下一关，每关只补一步 | 从头再来 | 熟手 |
| 旧灯 | 纯随机刷 | 带到下一关 | 从头再来 | 留着对照，运气成分大 |

想试新方案：复制一份 `.tres`，改几个数，标题页里会自己多出来。文件名开头的数字是它在选择页里排第几。

## 开场动画

游戏一启动播一段三四秒的开场，按任意键或手柄按键跳过。默认每次开机随机换一个，不会连着两次一样；「设置」里的「开场」可以固定成某一个，或者选「不播」。三个方案：

| 方案 | 是什么 |
|---|---|
| 一灯破夜 | 一片黑里一点灯花，一盏河灯漂上来，一串灯从水底涌起，汇到标志处炸开成光 |
| 水墨惊雷 | 宣纸上一滴墨化开，标志从墨里反白浮现，一方朱红大印盖下来，墨色铺满全屏转场 |
| 守夜人点灯 | 五块石台升起，守夜人一格一格跳过去，每落一格点亮一盏灯，最后一举灯照亮全屏 |

代码在 `scripts/uis/opening.gd`，着色器是 `shaders/opening_*.gdshader`，全是实时演的，没有视频文件。

每一段都配着一段声音，一下一下对着画面：灯花是火苗窜起来，涟漪是水珠落进水里，大印盖下来是一声堂鼓，守夜人每落一步是湿石台上的一声。开场播着的时候，标题页自己的音乐压低 13 分贝；揭出标题时音乐回来。开场自己的声音按音效的音量走。

### 音频方案 · 河灯夜行

用实录古琴与竹笛写柔和的应答，保留少量钢琴伴奏和木点，给河灯和脚步提示留出空间。

本方案包含标题和关卡循环配乐、三段按动画配声的开场和 43 个交互音效。

配乐和音效使用真实录音采样，逐音编排。古筝取自 [nanliu_music](https://freesound.org/people/nanliu_music/sounds/847157/)，竹笛取自 [Carlos Carty](https://freesound.org/people/CarlosCarty/sounds/339357/)，中国锣取自 [the_very_Real_Horst](https://freesound.org/people/the_very_Real_Horst/sounds/240156/)。古琴取自 [RafaelCaro 的 Guqin-open-strings.wav](https://freesound.org/people/RafaelCaro/sounds/176266/)，采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，本项目截取单音、移调并重新混音。补充乐器来自 Versilian Studios 的 [VCSL](https://github.com/sgossner/VCSL)，包括拨弦、键盘、管乐和打击乐。脚步来自 [sgossner](https://freesound.org/people/sgossner/sounds/197778/)，水花来自 [blukotek](https://freesound.org/people/blukotek/sounds/269251/) 和 [nilbul](https://freesound.org/people/nilbul/sounds/404829/)。古筝、竹笛、锣、VCSL 和拟音录音采用 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。Freesound 使用公开试听音轨，录音文件、来源及校验值见 [采样清单](tools/audio/recorded_samples.json)。程序负责编排、裁剪、移调、叠加和混音。使用 OpenAI Codex 辅助制作与验证。

重新混音需要 Python、NumPy 与 SoundFile。

```powershell
$env:SHOUWANG_SAMPLES = 'D:\shouwang-recordings'
python tools/audio/recorded_samples.py --fetch $env:SHOUWANG_SAMPLES
python tools/audio/remake.py --output assets/audio --preview builds/audio/preview.wav
```

录一段真正的开机画面来看（帧取回到 `builds/opening/<方案>/`）。录制脚本会核对游戏实际播的是不是要录的那个、声音放出来没有，不对就报错：

```bash
tools/playtest/agent.sh a7 opening B 5 20   # 录 5 秒、每秒 20 张（30 也行；再高这台机器存不过来，
                                            # 存少了按名义帧率回放，画面会比声音快——录制脚本会报出来）
tools/playtest/assemble_opening.sh          # 本机要有 ffmpeg：每个方案拼成带声音的 open<A>.mp4 和没声音的 open<A>.gif，
                                            # 三个都有的时候再拼三宫格的对照图 openALL（没声音）和三段连着放的 openABD.mp4（带声音）
```

查开场在游戏里的样子（在播、声音放出来了、音乐压低了；播完了音乐回来）：

```bash
SW_BOOT_WAIT=1 SW_OPENING=D tools/playtest/agent.sh a7 drive tools/playtest/steps_opening.txt opening
```

`SW_BOOT_WAIT=1` 是让脚本游戏一起来就动手（平时先等 6 秒，开场早播完了）；`SW_OPENING` 指定播哪一个，不给就按设置里的来。导出以后把 `drive` 换成 `smoke` 查导出包。

### 旁白（可选）

三句台词在 `tools/audio/voice.py` 的开头，是一套的。旁白得是人的声音，不由脚本生成：要么自己录，要么请人录。

```bash
tools/audio/record_voice.sh A       # 在本机录 A 那一句（要用麦克风），存到 builds/voice/
python3 tools/audio/voice.py A      # 收拾干净（去底噪、掐空白、对响度），放进 assets/audio/opening/voiceA.wav
```

放进去以后不用改任何东西：开场播到第 0.3 秒时这句放出来，开场自己的声音轻一截，说完回来。没有这个文件就不放。

## 操作

| | 键盘鼠标 | 手柄 |
|---|---|---|
| 跳 | W A S D，或者点亮着的格子 | 左摇杆、十字键 |
| 技能（菜单里是确认） | 空格 | A |
| 菜单 | Esc | Start、Back |
| 返回 | | B |

手柄的左摇杆同时带着屏幕上的一个光标，停在按钮上时按 A 等于鼠标点击。

## 跑起来

要用 Godot 4.7.2，导出模板也是这个版本。用编辑器打开 `project.godot`，按 F5。

存档在用户数据目录下的 `Godot/app_userdata/守望/` 里：解锁的角色、本机成绩、看没看过哪条新手教程、选的方案和开场动画、开场上一次播的是哪个。

游戏启动时会在本机 `127.0.0.1:9878` 开一个调试端口，自动测试靠它驱动游戏。它只监听本机。本机成绩也只存在本机，不往任何服务器发。

## 目录

| 位置 | 放的是什么 |
|---|---|
| `scenes/` `scripts/` `resources/` | 场景、GDScript、关卡和角色道具的资源 |
| `scripts/board_gen.gd` | 摆一局河灯（保证有解）和给长夜生成棋盘，纯逻辑 |
| `scripts/board_sim.gd` | 一个"随手玩"的机器人，调难度和自动试玩都用它 |
| `scripts/ruleset.gd`、`resources/rulesets/` | 玩法方案 |
| `scripts/uis/opening.gd`、`shaders/opening_*.gdshader` | 开场动画 |
| `scripts/autoload/pad_adapter.gd` | 手柄适配、调试遥控、自动试玩的机器人、录屏 |
| `shaders/` `materials/` | 抖动和染色 |
| `assets/sprites/` | 贴图。都是纯白剪影，颜色在运行时乘上去 |
| `assets/audio/` | 音乐和音效 |
| `tools/gen_campaign.py` | 巡夜 12 关的棋盘 |
| `tools/art/` | 画贴图的脚本，每张图都能从脚本重新画出来 |
| `tools/audio/` | 算开场声音的脚本，每一段都能从脚本重新算出来 |
| `assets/audio/opening/` | 开场动画的声音（算出来的）；`voice<A>.wav` 在的话是真人录的旁白 |
| `tools/test_boards.gd`、`tools/tune_deals.gd` | 棋盘逻辑和摆棋的自动测试；难度扫描 |
| `tools/playtest/` | 在服务器上自动试玩、导出、装到掌机 |
| `tools/handheld/` | 掌机上的启动脚本、菜单项、图标 |

## 改关卡

巡夜的棋盘只在一个地方定义：`tools/gen_campaign.py`。棋盘用字符画写，一行一个字符串：

```
.   普通格          空格   水，没有格子
S   起点            P      水车所在的格子（终点）
c   脆格            x      障碍
s   补给格
```

一张棋盘只能有一个起点和一个水车。改完运行 `python3 tools/gen_campaign.py .`，它会先校验所有棋盘，再写出 `resources/campaign/*.tres`。

每关收几盏灯、摆几件道具、难易，在 `scripts/board_gen.gd` 的 `CAMPAIGN_TABLE` 里，一行一关。长夜的难度曲线在同一个文件的 `endless_opt()` 里。

### 调难度

难易是量出来的，不是拍脑袋定的。每关的数字下面，让"随手玩"的机器人（`BoardSim`，够得着的灯里挑最近的）打 200 局，看它的过关率。这是下限，真人多想一步就比它强。

```bash
tools/playtest/agent.sh a7 boards             # 每关摆固定的一局并校验，再报机器人每关的过关率
```

现在的曲线（机器人过关率）：巡夜 100、100、97、100、67、70、76、59、58、44、32、24；长夜 100、90、82、68、50、50、35。

要大范围地扫参数，用 `tools/tune_deals.gd`（在服务器上跑，用法见文件开头）。

## 改美术

贴图不是手修的 PNG。每个元素在 `tools/art/` 里有一个画图脚本。改完跑：

```bash
tools/art/regen_all.sh                                                  # 重画全部，逐个脚本自检
python3 tools/art/review.py check . assets/sprites/ui/lock.png --zoom=0.32   # 单独自检一张
```

只需要 Python、Pillow 和 numpy，不跑 Godot。每张图的画布大小、图形范围、对称程度这些数，量好了存在 `tools/art/originals.json` 里，脚本靠它们让重画的图摆在原来的位置、大小相称。画法的几条规矩写在 `tools/art/doodle.py` 的开头，动手前先读一遍。

自检只查得出静态的问题。细节够不够清楚，要进游戏连拍着色器抖动的 10 个相位来看，用下面 `agent.sh` 的 `drive` 命令。

## 在服务器上测试和导出

本机不编译，试玩和导出都放到服务器上做。入口是 `tools/playtest/agent.sh <标签> <命令>`，在工程根目录下运行：

| 命令 | 做什么 |
|---|---|
| `base setup` | 建底版（带音频）。第一次用先跑一次 |
| `a7 setup`、`a7 sync`、`a7 import` | 建环境、同步工程、导入两遍；再不开窗口启动一回，自动加载的脚本和主场景都编译过了才算过 |
| `a7 boards` | 棋盘逻辑和摆棋的自动测试 |
| `a7 flow campaign`、`a7 flow endless` | 巡夜、长夜各走一遍过关流程 |
| `a7 aspect` | 巡夜 12 关各载入一遍，量棋盘是不是整个在画面里（默认 1152×720） |
| `a7 mechanics` | 长夜模式：补给格加步数、脆格碎掉后长回来、结算面板 |
| `a7 auto [campaign|endless] [1|2] [最多打到第几关] [前缀]` | 机器人真机玩一局。1 = 照着摆好的路线走（必须一步不错、关关都过）；2 = 贪心打法。顺手查棋盘上的登记：一盏灯不能登记在两个格子上 |
| `a7 drive <步骤文件> [前缀]` | 按步骤操作游戏并截图。步骤的写法见 `drive_v100.sh` 的开头。日志里有报错，或者某一步调的检查报了没过，退出码就不是 0 |
| `a7 opening [A|B|D] [秒数] [每秒几张]` | 录一段开场动画，核对播的是不是要录的那个、声音放出来没有 |
| `a7 all` | 一轮完整回归（它不同步工程，先 `sync`）：`import` → `boards` → 两种过关流程 → `aspect` → `mechanics` → `auto campaign 1`，哪一步没过就停在那一步 |
| `a7 export`、`a7 fetch` | 导出 Linux 可执行文件（日志里有报错就不出包）；取回到 `builds/linux/shouwang.x86_64` |
| `a7 smoke <步骤文件>` | 试跑导出来的可执行文件。`steps_export.txt` 是导出包自检：方案、道具这些按路径读的资源在包里都读得到 |
| `a7 clean` | 删掉服务器上这个标签的目录 |

每个标签在服务器上有一套独立的目录、端口和虚拟显示，几个任务可以同时跑。截图取回到 `builds/shots/<标签>/`。

换一套方案来测：`SW_RULESET=hard tools/playtest/agent.sh a7 auto campaign 2`。六套的 id 见 `resources/rulesets/`。这样指定不写存档。

机器人每一关都等灯摆完了才动手，换关后多久动的手会打进游戏日志。查它为什么跳不到，或者试它在灯没摆完的时候会不会乱动：

```bash
SW_AUTO_TRACE=1 tools/playtest/agent.sh a7 auto campaign 1    # 它每一步都打进日志
SW_AUTO_EAGER=1 tools/playtest/agent.sh a7 auto campaign 1    # 换关后只等 0.2 秒就动手（平时 1.5 秒）
```

测试用的存档是服务器上各个测试共用的，选过的方案会留在里面；要按默认的「灯谱」测，带上 `SW_RULESET=dealt`。

## 装到掌机

```bash
tools/playtest/agent.sh a7 export
tools/playtest/deploy_handheld.sh
```

掌机用 `~/.ssh/config` 里的别名 `RWKV_Tail` 连，地址、用户名、钥匙都写在那里。部署只换文件，不启动游戏，也不打断正在跑的那一局。旧的包留作 `shouwang.x86_64.prev`。

想在掌机上试跑一遍，用 `tools/playtest/verify_handheld.sh`。它会占住掌机的屏幕，并关掉正在跑的游戏，所以只在确认没人在玩的时候用，并且要带上参数 `yes`。
