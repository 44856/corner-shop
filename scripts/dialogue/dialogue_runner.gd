class_name DialogueRunner
extends Node
## 对话状态机 —— dev 工程里的 Dialogue autoload，这里退化成「由场景实例化的普通节点」。
##
## 为什么不是 autoload：本任务明令禁止改 project.godot，而 autoload 必须写在那里。
## 退一步反而更好：对话归属哪个场景由场景自己决定，不在全局留一个「谁都能调、
## 谁也不知道当前在哪个场景」的单例。
##
## 仍然是枢纽结构：解析器不认识 UI，UI 不认识触发器，触发器不认识解析器 ——
## 三者只通过这里发出的信号协作。

signal dialogue_started
signal line_shown(who: String, text: String)
signal dialogue_finished

## 主角名的默认值。{NAME} 占位符就是它
const DEFAULT_PLAYER_NAME := "旅人"
## 主角名字在对话框里的颜色（冰蓝），和狗的暖橙区分开
const PLAYER_NAME_COLOR := Color("#9fd8ee")

var player_name := DEFAULT_PLAYER_NAME
var chars_per_sec := 30.0

var _lines: Array = []
var _cursor := 0
var _active := false
var _box: DialogueBox
var _vars: Dictionary = {}


func _ready() -> void:
	_box = DialogueBox.new()
	_box.name = "DialogueBox"
	_box.chars_per_sec = chars_per_sec
	add_child(_box)
	_box.advance_requested.connect(advance)
	_sync_name_color()


## 从剧本文件开始一段对话。空剧本只警告，不进对话状态、不留半个对话框。
## 返回是否真的开始了 —— 触发器据此决定要不要顺手做别的事（比如冻结玩家）。
func start(path: String) -> bool:
	var raw: Array = DialogueParser.parse_file(path)
	if raw.is_empty():
		push_warning("DialogueRunner: 剧本为空或读取失败，忽略本次 start：%s" % path)
		return false

	# 占位符在这里替换，而不是在 UI 里：换名字不属于显示层的职责
	_vars = {"NAME": player_name}
	_lines = []
	for entry: Dictionary in raw:
		_lines.append({
			"who": DialogueParser.substitute(entry["who"], _vars),
			"text": DialogueParser.substitute(entry["text"], _vars),
			"line": entry["line"],
		})

	_cursor = 0
	_active = true
	_sync_name_color()
	_box.visible = true
	dialogue_started.emit()
	# 立刻显示第 0 行，不让玩家面对一个空框按空格
	_show_current()
	return true


## 推进一行；越界即结束并关框。未激活时直接 return（否则空格会把界面打穿）。
func advance() -> void:
	if not _active:
		return
	_cursor += 1
	if _cursor < _lines.size():
		_show_current()
	else:
		_active = false
		_box.close()
		dialogue_finished.emit()


func is_active() -> bool:
	return _active


## 当前句的说话人（测试与调试用）
func current_who() -> String:
	if not _active or _lines.is_empty():
		return ""
	return _lines[_cursor]["who"]


## 当前句的正文
func current_text() -> String:
	if not _active or _lines.is_empty():
		return ""
	return _lines[_cursor]["text"]


func set_player_name(value: String) -> void:
	player_name = value
	_sync_name_color()


func _sync_name_color() -> void:
	if _box != null:
		_box.set_speaker_color(player_name, PLAYER_NAME_COLOR)


func _show_current() -> void:
	var entry: Dictionary = _lines[_cursor]
	var who: String = entry["who"]
	var text: String = entry["text"]
	_box.show_line(who, text)
	line_shown.emit(who, text)
