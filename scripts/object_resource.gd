class_name ObjectResource extends Resource

@export var texture: CompressedTexture2D
@export var alternate_textures : Array[CompressedTexture2D]
@export var score := 1.0
@export var combo : bool = false
@export var walkable: bool = true
@export var charge_gain := 0

@export_category("Effect")
@export var effect: ObjectEffect
@export var value := 1.0
@export_multiline var description: String

enum ObjectEffect {
	None,
	
#	Upgrades
	SpawnFishes, # Umbrella
	TemporaryMoveDistance, # Shoe
	AttractFishes, # Magnet
	CollectFarestFishes, # Cane
	
#	Meta
	EndLevel,
	
	#Health
	RegainMovesLeft,
	GainCombo,
	
	MoreUpgrades, # 铜钱（旧效果：更容易刷出道具，现在不用了）

	# 新加的放在最后，不要插在中间，否则已有的 .tres 文件里按数字存的效果编号会全部错位
	ReachUp, # 草鞋：这一关之后每一跳都加 value 格
	Shield, # 斗笠：挡掉 value 次踩空（不扣步、不清连击）
	CollectNear, # 水车：收走身边 value 格内的灯
	AddMoves, # 食盒：步数 + value
	SpawnItems # 铜钱：在主角身边刷出 value 件道具
}
