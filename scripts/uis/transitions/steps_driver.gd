extends Node
## 石阶沉浮（transition_steps.gd）里每帧最后动石阶的那只手。TransitionStyle 自己不是节点，没有 _process，所以要一个真节点；
## process_priority 比格子、角色、对战的玩法都大，排在每帧最后（它们每一帧都会把自己的高度写一遍，这里随后改写）。
## 单独一个文件，不写成样式文件里的内部类：调试遥控是按脚本的文件名找节点的（pad_adapter.gd 的 _call）。
## 文件名故意不带 transition_ 前缀：agent.sh all 把 transitions/ 里 transition_*.gd 每一个都当成一种样式量一遍。
## 这里只做转发，事情都在样式里。

var style: TransitionStyle       # 样式本身（transition_steps.gd）

func _process(delta: float) -> void:
	if style != null: style.call("_tick", delta)

## 排查用（call steps_driver.gd debug_last）：最近一趟量出来的数。中间那一段最长的一帧 SceneTransitionControl 不报，这里报
func debug_last() -> String:
	return str(style.call("debug_last")) if style != null else "样式还没装上"

## 排查用（call steps_driver.gd debug_trace）：过渡做完以后查一遍，石阶、灯、主角是不是都回到了平时的样子
func debug_trace() -> String:
	return str(style.call("debug_trace")) if style != null else "样式还没装上"

## 排查用（call steps_driver.gd debug_frames）：就地放一遍，在几处要紧的时刻各存一张无损的 PNG（录像存的 JPG 深色偏色）
func debug_frames() -> String:
	return str(style.call("debug_frames")) if style != null else "样式还没装上"
