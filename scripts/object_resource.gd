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
	
	# 新加的放在最后，不要插在中间，否则已有的 .tres 文件里按数字存的效果编号会全部错位
	MoreUpgrades # Clover：接下来更容易刷出升级道具
}
