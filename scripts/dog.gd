extends Node3D
## 程序化拼出来的一只狗（坐姿，脸朝 +Z）
##
## 本工程零外部模型。二次元低模狗不需要细节，轮廓对了就成立：
## 一个后臀 + 一段前胸 + 球头 + 盒子口鼻 + 锥形耳朵 + 四根腿 + 一条上翘的尾巴。
##
## 呼吸起伏作用在 _breath 这个子节点组上（只含上半身），
## 腿和臀部留在地面 —— 否则整只狗会像被抬起来一样上下漂。
##
## 交互（本期新增）：走近按 F 开始对话，头顶浮出提示。
## 触发条件是「距离 + 按键」，不占用 Area3D —— 和 dev 工程的 trigger_zone 同一套思路：
## 对话内容、UI、解析全都不在这个文件里，这里只负责「喊一声 start」。

const K := preload("res://scripts/kit.gd")
const UiFont := preload("res://scripts/ui_font.gd")

## 对话剧本。换剧本只改这一行，狗的代码不用动
const DIALOGUE_SCRIPT := "res://dialogue/dog_01.txt"

## 毛色
@export var fur_color := Color("#c9a86a")
## 呼吸起伏幅度（米）。0 = 不动
@export var breath_amplitude := 0.01
## 呼吸周期（秒）
@export var breath_period := 2.5

@export_group("交互")
## 玩家进入这个半径内才能对话（米，只算水平距离）
@export var talk_radius := 2.4
## 头顶提示文案（只在自管交互时用）
@export var prompt_text := "按 F 说话"
## 是否由狗自己管「距离判定 + 按键 + 头顶提示」。
##
## 场景里若有 interaction_hub（城门那两个守卫就是走他那套），就把它置 false：
## 提示改由 HUD 统一出、按键改由中枢统一分发，狗只留下 talk() 这个入口。
## 两套同时在跑的话，一次按键会被两边各处理一次 —— 对话会开两遍。
@export var self_interaction := true

var _breath: Node3D
var _tail: Node3D
var _prompt: Label3D
var _t := 0.0

# 交互相关
var _player: Node3D
var _dialogue: Node
var _wag := 0.0


func _ready() -> void:
	_ensure_action()

	var fur := K.toon(fur_color, {"line": 0.008, "shade": 0.60, "rim": 0.10})
	var fur_dark := K.toon(fur_color.darkened(0.25), {"line": 0.008, "shade": 0.60, "rim": 0.10})
	var nose := K.toon(Color("#2b2622"), {"line": 0.0, "shade": 0.50})
	var eye := K.toon(Color("#23242b"), {"line": 0.0, "shade": 0.50})

	_breath = K.group(self, "Breath")

	_build_rear(fur, fur_dark)
	_build_legs(fur, fur_dark)
	_build_torso(fur)
	_build_head(fur, fur_dark, nose, eye)
	_build_tail(fur)
	_build_prompt()


## 交互装配：由场景把玩家和对话状态机递进来。
## 不在这里主动 find 节点 —— 那是反向依赖，狗不该知道场景长什么样。
func bind_interaction(player: Node3D, dialogue: Node) -> void:
	_player = player
	_dialogue = dialogue


## F 键在代码里注册。project.godot 里已经有就跳过，不覆盖用户的键位
func _ensure_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	InputMap.action_add_event("interact", ev)


# ---------------------------------------------------------------- 造型

## 后臀 + 收起的后腿（坐姿的重量都在这）
func _build_rear(fur: Material, fur_dark: Material) -> void:
	var haunch := K.sphere(self, 0.155, Vector3(0.0, 0.155, -0.14), fur)
	haunch.scale = Vector3(1.0, 1.0, 1.15)

	for side in [1.0, -1.0]:
		var thigh := K.sphere(self, 0.09, Vector3(0.135 * side, 0.115, -0.06), fur_dark)
		thigh.scale = Vector3(0.78, 0.85, 1.20)
		var paw := K.sphere(self, 0.045, Vector3(0.115 * side, 0.040, 0.06), fur_dark)
		paw.scale = Vector3(0.90, 0.70, 1.25)


## 前腿：竖直撑地
func _build_legs(fur: Material, fur_dark: Material) -> void:
	for side in [1.0, -1.0]:
		K.cyl(self, 0.036, 0.30, Vector3(0.075 * side, 0.15, 0.16), fur, Vector3.ZERO, 10)
		var paw := K.sphere(self, 0.042, Vector3(0.075 * side, 0.035, 0.195), fur_dark)
		paw.scale = Vector3(1.0, 0.75, 1.35)


## 前胸 + 脖子（跟着呼吸动）
func _build_torso(fur: Material) -> void:
	var chest := K.sphere(_breath, 0.145, Vector3(0.0, 0.310, 0.03),
		fur, Vector3(deg_to_rad(-8.0), 0.0, 0.0))
	chest.scale = Vector3(0.98, 1.15, 1.05)

	K.cyl(_breath, 0.070, 0.15, Vector3(0.0, 0.440, 0.115), fur,
		Vector3(deg_to_rad(22.0), 0.0, 0.0), 12)


func _build_head(fur: Material, fur_dark: Material, nose: Material, eye: Material) -> void:
	K.sphere(_breath, 0.125, Vector3(0.0, 0.505, 0.205), fur, Vector3.ZERO, 20)

	# 口鼻
	K.box(_breath, Vector3(0.115, 0.085, 0.14), Vector3(0.0, 0.472, 0.305), fur)
	K.sphere(_breath, 0.028, Vector3(0.0, 0.492, 0.372), nose, Vector3.ZERO, 8)

	# 眼睛
	for side in [1.0, -1.0]:
		K.sphere(_breath, 0.017, Vector3(0.055 * side, 0.532, 0.305), eye, Vector3.ZERO, 8)

	# 耳朵：锥体。绕 Z 轴往外倒一点，不然像是插在头上的两根钉子
	for side in [1.0, -1.0]:
		K.cyl(_breath, 0.042, 0.115, Vector3(0.082 * side, 0.610, 0.165), fur_dark,
			Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(-12.0) * side), 8, 0.004)


## 尾巴：两段圆柱折出一个向上的弯。
## 原本用 kit.tube() 拼折线，但 tube 的面绕序是内向的，generate_normals 算出来
## 法线朝里，整条尾巴吃不到光、渲染成一根黑棍。换成 CylinderMesh（kit.strut）法线正常。
##
## 挂在 _tail 这个枢轴上（原点在尾巴根部）而不是直接放世界坐标：
## 绕 Y 轴转这个枢轴就是「摇尾巴」，直接转整条狗会变成在扭身子。
func _build_tail(mat: Material) -> void:
	_tail = K.group(_breath, "Tail", Vector3(0.0, 0.235, -0.260))
	var a := Vector3.ZERO
	var b := Vector3(0.0, 0.165, -0.120)
	var c := Vector3(0.0, 0.285, -0.085)
	K.strut(_tail, a, b, 0.027, mat, 8)
	K.strut(_tail, b, c, 0.026, mat, 8)
	K.sphere(_tail, 0.030, c, mat, Vector3.ZERO, 8)


## 头顶提示：Label3D + billboard，始终面向镜头
func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.text = prompt_text
	_prompt.font = UiFont.get_font()
	_prompt.font_size = 44
	_prompt.pixel_size = 0.0022
	_prompt.position = Vector3(0.0, 0.86, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color("#fff3d6")
	_prompt.outline_size = 10
	_prompt.outline_modulate = Color(0.05, 0.06, 0.08, 0.92)
	_prompt.visible = false
	add_child(_prompt)


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	_t += delta

	if _breath != null and breath_amplitude > 0.0 and breath_period > 0.0:
		_breath.position.y = sin(_t * TAU / breath_period) * breath_amplitude

	# 尾巴：平时轻摆，说话时摇得快且大 —— 一个不用音频也能表达「它很兴奋」的手段
	var talking: bool = _dialogue != null and _dialogue.is_active()
	var target := 1.0 if talking else 0.16
	_wag = lerpf(_wag, target, 1.0 - exp(-5.0 * delta))
	if _tail != null:
		_tail.rotation.y = sin(_t * (7.0 + 7.0 * _wag)) * 0.22 * _wag

	if _prompt != null:
		_prompt.visible = self_interaction and _can_talk()


# ---------------------------------------------------------------- 交互

## 供 interaction_hub 调用：能不能说、说哪一段，判定仍然留在狗自己这里。
## 返回 false 表示这一刻不该说话（没醒 / 正在对话 / 离得太远）。
func talk() -> bool:
	if not _can_talk():
		return false
	_dialogue.start(DIALOGUE_SCRIPT)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not self_interaction:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _can_talk():
		return
	# 吃掉输入，避免同一次按键被别的监听者再处理一次
	get_viewport().set_input_as_handled()
	_dialogue.start(DIALOGUE_SCRIPT)


## 能否开始对话：在范围内、没在对话中、已经醒了。
## 「醒了」这一条很关键 —— 否则玩家躺着的时候就能按 F 和狗聊天。
func _can_talk() -> bool:
	if _player == null or _dialogue == null:
		return false
	if not is_instance_valid(_player) or not is_instance_valid(_dialogue):
		return false
	if _dialogue.is_active():
		return false
	var locked: Variant = _player.get("input_locked")
	if locked == true:
		return false
	return _distance_to_player() <= talk_radius


func _distance_to_player() -> float:
	if _player == null or not is_inside_tree():
		return INF
	var d: Vector3 = _player.global_position - global_position
	d.y = 0.0
	return d.length()
