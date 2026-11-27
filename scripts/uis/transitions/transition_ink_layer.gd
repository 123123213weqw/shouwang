extends TextureRect
## 「墨迹晕开」那一层墨（transition_ink.gd 用 full_rect() 建的贴图节点，套着 shaders/transition_ink.gdshader）。
## 样式自己不是节点，调试遥控（tools/playtest 的 call）只找得到带脚本的节点，所以把"冻在某一时辰"的排查办法放在这儿，
## 转手交给样式。在游戏里调（参数只能是整数）：
##   call transition_ink_layer.gd debug_pose 1 300 -1 -1     盖住走到三成的那一帧冻住：墨从主角这会儿站的地方晕开
##   call transition_ink_layer.gd debug_pose 2 400 50 46     掀开走到四成的那一帧冻住：墨从画面的 50%、46% 那儿化开
##   call transition_ink_layer.gd debug_pose 0 0 0 0         收起来，回到什么都看不见
## 冻着的时侯 snap 一张全分辨率的图，湿边、毛刺、须、纸纹都看得清。平时游戏不会走到这儿。

var ink: RefCounted        ## 管这一层的样式（transition_ink.gd）。那个文件按规矩不写 class_name，所以这儿也不写死类型

func debug_pose(phase: int, step: int, ox: int, oy: int) -> String:
	if ink == null: return "这一层还没交给样式"
	return ink.debug_pose(phase, step, ox, oy)
