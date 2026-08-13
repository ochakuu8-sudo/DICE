extends Control

const BOARD_W := 5
const BOARD_H := 5
const HAND_LIMIT := 3
const ACTIONS_PER_TURN := 2
const MAX_ENCOUNTERS := 6

class BoardView:
	extends Control

	var main: Control

	func _draw() -> void:
		if main == null or main.track_cells.is_empty():
			return
		var line_color := Color("#6e6556")
		var next_color := Color("#65cfe6")
		var passed_color := Color("#f5d86a")
		for i in range(main.track_cells.size() - 1):
			var a: Vector2 = main._board_cell_center(main.track_cells[i])
			var b: Vector2 = main._board_cell_center(main.track_cells[i + 1])
			var segment_color := line_color
			var width := 10.0
			if main._segment_is_recent(i):
				segment_color = passed_color
				width = 14.0
			elif main._segment_is_next(i):
				segment_color = next_color
				width = 12.0
			draw_line(a, b, segment_color, width, true)
			if i % 2 == 0:
				_draw_arrow(a, b, segment_color)

	func _draw_arrow(a: Vector2, b: Vector2, color: Color) -> void:
		var dir := b - a
		if dir.length() < 1.0:
			return
		dir = dir.normalized()
		var mid := a.lerp(b, 0.58)
		var side := Vector2(-dir.y, dir.x)
		var tip := mid + dir * 9.0
		var left := mid - dir * 7.0 + side * 6.0
		var right := mid - dir * 7.0 - side * 6.0
		draw_colored_polygon([tip, left, right], color.lightened(0.12))

var rng := RandomNumberGenerator.new()

var bg_rect: ColorRect
var root_box: VBoxContainer
var header_label: Label
var instruction_label: Label
var route_label: Label
var stats_label: Label
var enemy_plan_label: Label
var board_grid: BoardView
var dice_box: HBoxContainer
var command_box: HBoxContainer
var reward_box: VBoxContainer
var log_label: Label
var end_turn_button: Button
var restart_button: Button
var ui_font: Font

var cell_buttons: Array = []

var state := "title"
var hero_key := ""
var hero_name := ""
var encounter := 0
var player_hp := 30
var player_max_hp := 30
var player_shield := 0
var player_pos := Vector2i(2, 2)
var player_step := 0
var actions_left := 0

var permanent_board: Array = []
var temp_board: Array = []
var track_cells: Array[Vector2i] = []
var enemies: Array = []
var dice_bag: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var hand: Array = []

var selected_die := {}
var selected_roll := 0
var selected_tag := ""
var steps_left := 0
var route_path: Array[Vector2i] = []
var route_power := 0
var route_hits := 0
var pending_reward_type := ""
var pending_reward_name := ""

var tile_defs := {
	"empty": {"short": "道", "name": "道", "kind": "基本", "color": Color("#2f3442"), "pass": "", "stop": "停止: シールド+1"},
	"slash": {"short": "攻", "name": "斬撃路", "kind": "攻撃", "color": Color("#a74646"), "pass": "通過: この移動中の通過攻撃+2", "stop": "停止: 攻撃力+1"},
	"guard": {"short": "守", "name": "防御路", "kind": "防御", "color": Color("#3d67a8"), "pass": "通過: シールド+1", "stop": "停止: シールド+3"},
	"fire": {"short": "火", "name": "火走り", "kind": "攻撃", "color": Color("#bd6238"), "pass": "通過: 通過攻撃+1、敵を燃やす", "stop": "停止: 最も近い敵に2ダメージ"},
	"heal": {"short": "癒", "name": "癒し道", "kind": "回復", "color": Color("#459a5d"), "pass": "通過: HP+1", "stop": "停止: HP+3"},
	"bow": {"short": "射", "name": "射撃台", "kind": "遠隔", "color": Color("#a59446"), "pass": "通過: 通過攻撃+1", "stop": "停止: 同じ行か列の敵に3ダメージ"},
	"trap": {"short": "罠", "name": "罠道", "kind": "妨害", "color": Color("#7550a8"), "pass": "通過: 今いるマスに罠を残す", "stop": "停止: 周囲に罠を置く"},
	"warp": {"short": "跳", "name": "跳躍路", "kind": "移動", "color": Color("#2f8c9b"), "pass": "通過: 追加で1歩進める", "stop": "停止: 追加行動+1"},
	"shock": {"short": "雷", "name": "雷線", "kind": "全体", "color": Color("#7d70d6"), "pass": "通過: 全敵に1ダメージ", "stop": "停止: 全敵に2ダメージ"},
	"focus": {"short": "集", "name": "集中路", "kind": "補助", "color": Color("#718063"), "pass": "通過: 攻撃力+1、シールド+1", "stop": "停止: ダイスを1個引く"}
}

var temp_defs := {
	"none": {"short": "", "color": Color("#00000000"), "desc": ""},
	"hazard": {"short": "毒", "color": Color("#58385c"), "desc": "通過: HP-2。敵も踏むと2ダメージ"},
	"trap_temp": {"short": "罠", "color": Color("#8b3e72"), "desc": "敵が踏むと5ダメージ"},
	"block": {"short": "壁", "color": Color("#171a21"), "desc": "通れない"}
}

var reward_pool := [
	{"type": "slash"}, {"type": "guard"}, {"type": "fire"},
	{"type": "heal"}, {"type": "bow"}, {"type": "trap"},
	{"type": "warp"}, {"type": "shock"}, {"type": "focus"}
]

var hero_defs := {
	"knight": {
		"name": "剣士",
		"hp": 36,
		"desc": "攻撃路と防御路をつないで、敵を通過しながら倒す。",
		"dice": [
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"},
			{"name": "重撃ダイス", "faces": [3, 4, 4, 5, 6, 6], "tag": "heavy"},
			{"name": "守りダイス", "faces": [1, 2, 2, 3, 3, 4], "tag": "steel"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [[1, 2, "slash"], [2, 2, "guard"], [3, 2, "slash"], [0, 2, "bow"], [4, 2, "heal"]]
	},
	"mage": {
		"name": "魔導士",
		"hp": 28,
		"desc": "火走りと雷線で、離れた敵にも通過効果を飛ばす。",
		"dice": [
			{"name": "火花ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "fire"},
			{"name": "揺らぎダイス", "faces": [1, 1, 3, 5, 6, 6], "tag": "arcane"},
			{"name": "集中ダイス", "faces": [2, 2, 3, 3, 4, 4], "tag": "focus"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [[0, 0, "fire"], [4, 0, "fire"], [0, 4, "shock"], [4, 4, "warp"], [2, 2, "focus"]]
	},
	"rogue": {
		"name": "盗賊",
		"hp": 31,
		"desc": "罠と射撃台を仕込み、敵の進路を利用する。",
		"dice": [
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"},
			{"name": "仕掛けダイス", "faces": [1, 2, 3, 3, 5, 6], "tag": "trick"},
			{"name": "幸運ダイス", "faces": [1, 2, 2, 4, 4, 6], "tag": "lucky"},
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"}
		],
		"tiles": [[1, 1, "trap"], [3, 1, "trap"], [1, 3, "bow"], [3, 3, "bow"], [2, 2, "warp"]]
	}
}

func _ready() -> void:
	rng.randomize()
	_build_track_cells()
	ui_font = load("res://assets/NotoSansJP.ttf")
	_build_ui()
	_fit_layout()
	_show_title()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and root_box != null:
		_fit_layout()

func _fit_layout() -> void:
	if bg_rect != null:
		bg_rect.position = Vector2.ZERO
		bg_rect.size = get_viewport_rect().size
	if root_box != null:
		root_box.position = Vector2(14, 14)
		root_box.size = get_viewport_rect().size - Vector2(28, 28)
	if board_grid != null:
		var viewport_size := get_viewport_rect().size
		var board_height: float
		if viewport_size.y > viewport_size.x:
			board_height = min(viewport_size.y * 0.44, max(340.0, viewport_size.x * 0.62))
		else:
			board_height = min(viewport_size.y * 0.68, max(500.0, viewport_size.x * 0.58))
		board_grid.custom_minimum_size = Vector2(0, board_height)
		_layout_board_buttons()

func _build_ui() -> void:
	bg_rect = ColorRect.new()
	bg_rect.color = Color("#171a21")
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root_box)

	header_label = _make_label(26, Color("#f5f1e8"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(header_label)
	instruction_label = _make_label(21, Color("#f5d86a"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(instruction_label)
	route_label = _make_label(16, Color("#dfe7f3"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(route_label)
	stats_label = _make_label(16, Color("#d7d2c4"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(stats_label)
	enemy_plan_label = _make_label(14, Color("#f0b7a7"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(enemy_plan_label)

	board_grid = BoardView.new()
	board_grid.main = self
	board_grid.size_flags_vertical = Control.SIZE_FILL
	board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_grid.custom_minimum_size = Vector2(0, 430)
	board_grid.resized.connect(Callable(self, "_layout_board_buttons"))
	root_box.add_child(board_grid)

	for i in range(BOARD_W * BOARD_H):
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(58, 58)
		_apply_font(cell)
		cell.add_theme_font_size_override("font_size", 13)
		cell.pressed.connect(Callable(self, "_on_cell_pressed").bind(i))
		board_grid.add_child(cell)
		cell_buttons.append(cell)

	dice_box = HBoxContainer.new()
	dice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_box.add_theme_constant_override("separation", 8)
	root_box.add_child(dice_box)

	command_box = HBoxContainer.new()
	command_box.alignment = BoxContainer.ALIGNMENT_CENTER
	command_box.add_theme_constant_override("separation", 8)
	root_box.add_child(command_box)

	end_turn_button = Button.new()
	end_turn_button.text = "行動終了"
	_apply_font(end_turn_button)
	end_turn_button.pressed.connect(Callable(self, "_on_end_turn_pressed"))
	command_box.add_child(end_turn_button)

	restart_button = Button.new()
	restart_button.text = "最初から"
	_apply_font(restart_button)
	restart_button.pressed.connect(Callable(self, "_show_title"))
	command_box.add_child(restart_button)

	reward_box = VBoxContainer.new()
	reward_box.add_theme_constant_override("separation", 8)
	root_box.add_child(reward_box)

	log_label = _make_label(15, Color("#d7d2c4"), HORIZONTAL_ALIGNMENT_LEFT)
	root_box.add_child(log_label)

func _make_label(size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(label)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _show_title() -> void:
	state = "title"
	encounter = 0
	board_grid.visible = false
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "Dice Board Rogue"
	instruction_label.text = "キャラクターを選択"
	route_label.text = "一本道のすごろくコースを出目ぶん前進し、通過した敵と道で効果が発生します。"
	stats_label.text = "自由移動ではなく、先のコースを読んでどのダイスを使うかを選びます。"
	enemy_plan_label.text = ""
	log_label.text = "戦闘後は毎回、新しいマスを永続ボードへ配置します。進む先のルートを育ててください。"
	end_turn_button.visible = false
	restart_button.visible = false

	for key in hero_defs.keys():
		var hero: Dictionary = hero_defs[key]
		var b := Button.new()
		b.text = "%s\n%s" % [hero["name"], hero["desc"]]
		b.custom_minimum_size = Vector2(0, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, "_start_run").bind(key))
		_apply_button_color(b, _hero_color(key), Color("#f5d86a"), 2)
		reward_box.add_child(b)

func _start_run(key: String) -> void:
	hero_key = key
	var hero: Dictionary = hero_defs[key]
	hero_name = str(hero["name"])
	player_max_hp = int(hero["hp"])
	player_hp = player_max_hp
	player_shield = 0
	player_step = _track_index(_start_pos())
	player_pos = _pos_for_step(player_step)
	encounter = 0
	permanent_board = _make_empty_board("empty")
	for entry in hero["tiles"]:
		permanent_board[int(entry[1])][int(entry[0])] = str(entry[2])
	dice_bag = []
	for die in hero["dice"]:
		dice_bag.append(die.duplicate(true))
	_start_encounter()

func _start_encounter() -> void:
	encounter += 1
	board_grid.visible = true
	player_pos = _pos_for_step(player_step)
	player_shield = 0
	actions_left = ACTIONS_PER_TURN
	selected_die = {}
	selected_roll = 0
	selected_tag = ""
	steps_left = 0
	route_path = []
	route_power = 0
	route_hits = 0
	temp_board = _make_empty_board("none")
	enemies = []
	_setup_encounter()
	_reset_dice_for_encounter()
	_clear_children(reward_box)
	_start_player_turn("第%d戦開始。先のコースを見て、使うダイスを選んでください。" % encounter)

func _setup_encounter() -> void:
	if encounter == MAX_ENCOUNTERS:
		enemies.append(_make_enemy_on_track("ボス", player_step + 8, 32, 7, 1))
		enemies.append(_make_enemy_on_track("護衛", player_step + 4, 12, 4, 1))
		enemies.append(_make_enemy_on_track("護衛", player_step + 12, 12, 4, 1))
		return

	var enemy_count: int = min(2 + int(encounter / 2), 4)
	for i in range(enemy_count):
		var type_name := "敵"
		var hp := 8 + encounter * 2
		var damage := 3 + int(encounter / 2)
		var offset := 3 + i * 3 + rng.randi_range(0, 1)
		if encounter >= 3 and i == 0:
			type_name = "射手"
			hp -= 2
			damage += 1
		elif encounter >= 4 and i == 1:
			type_name = "重装"
			hp += 6
			damage += 2
			offset += 2
		enemies.append(_make_enemy_on_track(type_name, player_step + offset, hp, damage, 1))

	for n in range(min(encounter, 4)):
		var p2 := _random_empty_cell()
		if p2.x >= 0:
			temp_board[p2.y][p2.x] = "hazard"

func _make_enemy(type_name: String, x: int, y: int, hp: int, damage: int, move: int) -> Dictionary:
	var step := _track_index(Vector2i(x, y))
	return _make_enemy_on_track(type_name, step, hp, damage, move)

func _make_enemy_on_track(type_name: String, step: int, hp: int, damage: int, move: int) -> Dictionary:
	var normalized_step := _normalize_step(step)
	return {
		"type": type_name,
		"step": normalized_step,
		"pos": _pos_for_step(normalized_step),
		"hp": hp,
		"max_hp": hp,
		"damage": damage,
		"move": move
	}

func _reset_dice_for_encounter() -> void:
	draw_pile = []
	discard_pile = []
	hand = []
	for die in dice_bag:
		draw_pile.append(die.duplicate(true))
	draw_pile.shuffle()
	_draw_to_hand()

func _start_player_turn(message: String = "") -> void:
	state = "player"
	player_shield = 0
	actions_left = ACTIONS_PER_TURN
	selected_die = {}
	selected_roll = 0
	steps_left = 0
	route_path = []
	route_power = 0
	route_hits = 0
	_draw_to_hand()
	if message != "":
		log_label.text = message
	_refresh_all()

func _draw_to_hand() -> void:
	while hand.size() < HAND_LIMIT:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile.duplicate(true)
			discard_pile = []
			draw_pile.shuffle()
		hand.append(draw_pile.pop_back())

func _refresh_all() -> void:
	_refresh_header()
	_refresh_board()
	_refresh_dice()
	end_turn_button.visible = state == "player" or state == "moving"
	restart_button.visible = state != "title"

func _refresh_header() -> void:
	header_label.text = "%s / 第%d戦%s" % [hero_name, encounter, " ボス" if encounter == MAX_ENCOUNTERS else ""]
	instruction_label.text = _state_instruction()
	route_label.text = _route_status_text()
	stats_label.text = "HP %d/%d   盾 %d   行動 %d/%d   山札 %d   捨札 %d   手札 %d" % [
		player_hp, player_max_hp, player_shield, actions_left, ACTIONS_PER_TURN, draw_pile.size(), discard_pile.size(), hand.size()
	]
	enemy_plan_label.text = _enemy_plan_summary()

func _layout_board_buttons() -> void:
	if board_grid == null or cell_buttons.is_empty():
		return
	var token_size := _board_token_size()
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var index := _idx(x, y)
			var button: Button = cell_buttons[index]
			var center := _board_cell_center(Vector2i(x, y))
			button.position = center - Vector2(token_size, token_size) * 0.5
			button.size = Vector2(token_size, token_size)
	board_grid.queue_redraw()

func _board_token_size() -> float:
	if board_grid == null:
		return 46.0
	var step := _board_spacing()
	return clamp(step * 0.56, 36.0, 70.0)

func _cell_font_size() -> int:
	var token_size := _board_token_size()
	if token_size >= 62.0:
		return 15
	if token_size >= 50.0:
		return 13
	return 10

func _board_spacing() -> float:
	if board_grid == null:
		return 64.0
	var available := board_grid.size - Vector2(80, 64)
	var raw_spacing: float = min(available.x / float(BOARD_W - 1), available.y / float(BOARD_H - 1))
	# Scale the cap with the viewport's smaller side instead of a fixed pixel
	# value: with canvas_items/expand stretch, a wide desktop window reports a
	# much larger logical viewport than the portrait design size, so a fixed
	# cap left the board using only a small fraction of the space it was
	# actually given.
	var viewport_size := get_viewport_rect().size
	var max_spacing: float = min(viewport_size.x, viewport_size.y) * 0.16
	return clamp(raw_spacing, 50.0, max_spacing)

func _board_origin() -> Vector2:
	var step := _board_spacing()
	var board_size := Vector2(step * float(BOARD_W - 1), step * float(BOARD_H - 1))
	return (board_grid.size - board_size) * 0.5

func _board_cell_center(pos: Vector2i) -> Vector2:
	var origin := _board_origin()
	var step := _board_spacing()
	return origin + Vector2(float(pos.x) * step, float(pos.y) * step)

func _state_instruction() -> String:
	match state:
		"player":
			return "ダイスを選ぶ"
		"moving":
			return "出目ぶん前進中"
		"enemy":
			return "敵の行動中"
		"reward_select":
			return "報酬マスを選ぶ"
		"reward_place":
			return "報酬マスを配置する"
		"victory":
			return "踏破成功"
		"game_over":
			return "ゲームオーバー"
	return ""

func _route_status_text() -> String:
	if state == "moving":
		return "%s の出目 %d / 残り %d歩 / 通過攻撃+%d / 命中 %d回" % [
			selected_die.get("name", "ダイス"), selected_roll, steps_left, route_power, route_hits
		]
	if state == "player":
		return "コースは一方通行。先にいる敵や効果マスを見て、ちょうどよい出目のダイスを切ります。"
	if state == "reward_select":
		return "選んだマスは永続ボードに残ります。次の戦闘のルートが変わります。"
	if state == "reward_place":
		return "配置中: %s" % pending_reward_name
	return ""

func _enemy_plan_summary() -> String:
	if enemies.is_empty() or state == "title":
		return ""
	var parts := []
	for enemy in enemies:
		parts.append("%s HP%d: %s" % [enemy["type"], int(enemy["hp"]), _enemy_plan(enemy)])
	return "敵予告  " + " / ".join(parts)

func _enemy_plan(enemy: Dictionary) -> String:
	var dist := _track_gap(enemy)
	if str(enemy["type"]) == "射手" and dist <= 4:
		return "射撃%d" % int(enemy["damage"])
	if dist <= 1:
		return "攻撃%d" % int(enemy["damage"])
	return "逆走接近"

func _refresh_board() -> void:
	_layout_board_buttons()
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var idx := _idx(x, y)
			var button: Button = cell_buttons[idx]
			var pos := Vector2i(x, y)
			var perm_type: String = str(permanent_board[y][x])
			var temp_type: String = str(temp_board[y][x])
			var color: Color = tile_defs[perm_type]["color"]
			var border_color := Color("#a9a292")
			var border_width := 1
			var is_player_cell := pos == player_pos
			var has_enemy := false
			var font_size := _cell_font_size()
			var text_parts := []
			var track_index := _track_index(pos)

			if temp_type != "none":
				color = temp_defs[temp_type]["color"]
				text_parts.append(temp_defs[temp_type]["short"])
			if track_index == 0:
				text_parts.append("始")
			elif track_index == track_cells.size() - 1:
				text_parts.append("戻")
			else:
				text_parts.append("%02d" % track_index)
			text_parts.append(str(tile_defs[perm_type]["short"]))

			var enemy := _enemy_at(pos)
			if not enemy.is_empty():
				has_enemy = true
				color = Color("#8d2f35")
				text_parts = ["敵", "HP%d" % int(enemy["hp"])]
				border_color = Color("#ffb1a4")
				border_width = 5
				font_size += 2

			if is_player_cell:
				color = Color("#e1b93c")
				if has_enemy:
					text_parts = ["現在地", "敵HP%d" % int(enemy["hp"])]
				else:
					text_parts = ["現在地", "%02d" % track_index]
				border_color = Color("#fff2a1")
				border_width = 6
				font_size += 2
			elif route_path.has(pos):
				text_parts.push_front("通過")
				border_color = Color("#f5d86a")
				border_width = 3
				color = color.lightened(0.14)
			elif state == "player":
				var ahead := _steps_ahead(pos)
				if ahead > 0 and ahead <= 6:
					text_parts.push_front("+%d" % ahead)
					border_color = Color("#8fe8ff")
					border_width = 2

			button.disabled = false
			if state == "moving":
				button.disabled = true
			elif state == "reward_place":
				if _can_place_reward(pos):
					color = color.lightened(0.16)
					border_color = Color("#8fe8ff")
					border_width = 4
				else:
					button.disabled = true
					color = color.darkened(0.3)
			elif state == "title" or state == "reward_select":
				button.disabled = true

			button.text = "\n".join(text_parts)
			button.tooltip_text = _cell_tooltip(pos, perm_type, temp_type)
			button.add_theme_font_size_override("font_size", font_size)
			_apply_cell_button_color(button, color, border_color, border_width, is_player_cell, has_enemy)
	board_grid.queue_redraw()

func _refresh_dice() -> void:
	_clear_children(dice_box)
	if state != "player" and state != "moving":
		return
	for i in range(hand.size()):
		var die: Dictionary = hand[i]
		var b := Button.new()
		var tag := str(die["tag"])
		b.text = "%s\n面 %s\n%s" % [die["name"], _faces_to_text(die["faces"]), _tag_name(tag)]
		b.custom_minimum_size = Vector2(176, 78)
		b.disabled = state != "player" or actions_left <= 0
		b.pressed.connect(Callable(self, "_on_die_pressed").bind(i))
		_apply_button_color(b, _tag_color(tag))
		dice_box.add_child(b)

func _on_die_pressed(index: int) -> void:
	if state != "player" or index < 0 or index >= hand.size() or actions_left <= 0:
		return
	selected_die = hand[index].duplicate(true)
	var faces: Array = selected_die["faces"]
	selected_roll = int(faces[rng.randi_range(0, faces.size() - 1)])
	selected_tag = str(selected_die["tag"])
	steps_left = selected_roll
	route_power = _tag_route_bonus(selected_tag)
	route_hits = 0
	route_path = [player_pos]
	discard_pile.append(selected_die)
	hand.remove_at(index)
	state = "moving"
	log_label.text = "%s を振って %d。コースを%dマス前進します。" % [selected_die["name"], selected_roll, selected_roll]
	_refresh_all()
	await get_tree().create_timer(0.18).timeout
	await _advance_player()

func _on_cell_pressed(index: int) -> void:
	var pos := Vector2i(index % BOARD_W, int(index / BOARD_W))
	if state == "reward_place":
		if _can_place_reward(pos):
			permanent_board[pos.y][pos.x] = pending_reward_type
			if encounter >= MAX_ENCOUNTERS:
				_show_victory()
			else:
				_start_encounter()
				log_label.text = "%s を配置しました。次の戦闘へ。" % pending_reward_name
				_refresh_all()

func _advance_player() -> void:
	var messages := []
	while steps_left > 0:
		player_step = _normalize_step(player_step + 1)
		player_pos = _pos_for_step(player_step)
		route_path.append(player_pos)
		steps_left -= 1
		var pass_message := _resolve_pass_tile(player_pos)
		if pass_message != "":
			messages.append(pass_message)
		var enemy := _enemy_at(player_pos)
		if not enemy.is_empty():
			messages.append(_hit_enemy_on_route(enemy))
		_cleanup_dead_enemies()
		log_label.text = " ".join(messages)
		_refresh_all()
		await get_tree().create_timer(0.12).timeout

		if player_hp <= 0:
			_show_game_over("移動中に倒れました。")
			return
		if enemies.is_empty():
			_show_reward()
			return

	if player_hp <= 0:
		_show_game_over("移動中に倒れました。")
		return
	if enemies.is_empty():
		_show_reward()
		return

	messages.append(_resolve_stop_tile(player_pos))
	_cleanup_dead_enemies()
	actions_left -= 1
	if player_hp <= 0:
		_show_game_over("移動後に倒れました。")
		return
	if enemies.is_empty():
		_show_reward()
		return
	if actions_left <= 0 or hand.is_empty():
		state = "player"
		log_label.text = " ".join(messages) + " 敵の行動。"
		_refresh_all()
		await get_tree().create_timer(0.25).timeout
		_enemy_turn()
	else:
		state = "player"
		log_label.text = " ".join(messages) + " 次のダイスを選べます。"
		_refresh_all()

func _resolve_pass_tile(pos: Vector2i) -> String:
	var tile_type: String = str(permanent_board[pos.y][pos.x])
	var temp_type: String = str(temp_board[pos.y][pos.x])
	var messages := []
	if temp_type == "hazard":
		_take_damage(2)
		messages.append("毒沼を通過して2ダメージ。")
	if tile_type == "slash":
		route_power += 2
		messages.append("斬撃路を通過。通過攻撃+2。")
	elif tile_type == "guard":
		player_shield += 1
		messages.append("防御路を通過。盾+1。")
	elif tile_type == "fire":
		route_power += 1
		messages.append("火走りを通過。通過攻撃+1。")
	elif tile_type == "heal":
		_heal(1)
		messages.append("癒し道を通過。HP+1。")
	elif tile_type == "bow":
		route_power += 1
		messages.append("射撃台を通過。通過攻撃+1。")
	elif tile_type == "trap":
		temp_board[pos.y][pos.x] = "trap_temp"
		messages.append("罠道を通過。罠を残した。")
	elif tile_type == "warp":
		steps_left += 1
		messages.append("跳躍路を通過。追加で1歩。")
	elif tile_type == "shock":
		for enemy in enemies:
			enemy["hp"] -= 1
		messages.append("雷線を通過。全敵に1ダメージ。")
	elif tile_type == "focus":
		route_power += 1
		player_shield += 1
		messages.append("集中路を通過。通過攻撃+1、盾+1。")
	return " ".join(messages)

func _resolve_stop_tile(pos: Vector2i) -> String:
	var tile_type: String = str(permanent_board[pos.y][pos.x])
	if tile_type == "empty":
		player_shield += 1
		return "道で停止。盾+1。"
	if tile_type == "slash":
		route_power += 1
		return "斬撃路で停止。次の通過攻撃を構えた。"
	if tile_type == "guard":
		player_shield += 3
		return "防御路で停止。盾+3。"
	if tile_type == "fire":
		var target := _nearest_enemy(player_pos, 99)
		if not target.is_empty():
			target["hp"] -= 2
			return "火走りで停止。最も近い敵に2ダメージ。"
		return "火走りで停止。敵はいない。"
	if tile_type == "heal":
		_heal(3)
		return "癒し道で停止。HP+3。"
	if tile_type == "bow":
		var shot := _line_enemy(player_pos)
		if not shot.is_empty():
			shot["hp"] -= 3
			return "射撃台で停止。同じ行/列の敵に3ダメージ。"
		return "射撃台で停止。射線上に敵はいない。"
	if tile_type == "trap":
		var placed := 0
		var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		for d: Vector2i in dirs:
			var p: Vector2i = player_pos + d
			if _inside(p) and temp_board[p.y][p.x] == "none":
				temp_board[p.y][p.x] = "trap_temp"
				placed += 1
		return "罠道で停止。周囲に罠を%d個置いた。" % placed
	if tile_type == "warp":
		actions_left += 1
		return "跳躍路で停止。追加行動+1。"
	if tile_type == "shock":
		for enemy in enemies:
			enemy["hp"] -= 2
		return "雷線で停止。全敵に2ダメージ。"
	if tile_type == "focus":
		_draw_to_hand()
		return "集中路で停止。ダイスを補充。"
	return ""

func _hit_enemy_on_route(enemy: Dictionary) -> String:
	var damage := 1 + route_power + int(selected_roll / 3)
	if selected_tag == "heavy":
		damage += 1
	if selected_tag == "fire":
		damage += 1
	enemy["hp"] -= damage
	route_hits += 1
	return "%sを通過攻撃。%dダメージ。" % [enemy["type"], damage]

func _enemy_turn() -> void:
	state = "enemy"
	var messages := []
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var dist := _track_gap(enemy)
		if str(enemy["type"]) == "射手" and dist <= 4:
			_take_damage(int(enemy["damage"]))
			messages.append("射手の射撃%d。" % int(enemy["damage"]))
			continue
		if dist <= 1:
			_take_damage(int(enemy["damage"]))
			messages.append("%sの攻撃%d。" % [enemy["type"], int(enemy["damage"])])
		else:
			_move_enemy_toward(enemy)
			var epos: Vector2i = enemy["pos"]
			if temp_board[epos.y][epos.x] == "trap_temp":
				enemy["hp"] -= 5
				temp_board[epos.y][epos.x] = "none"
				messages.append("%sが罠で5ダメージ。" % enemy["type"])
			elif temp_board[epos.y][epos.x] == "hazard":
				enemy["hp"] -= 2
				messages.append("%sが毒で2ダメージ。" % enemy["type"])
			else:
				messages.append("%sがコースを逆走して接近。" % enemy["type"])

	if encounter >= 3 and not enemies.is_empty() and rng.randi_range(0, 100) < 45:
		var p := _random_empty_cell()
		if p.x >= 0:
			temp_board[p.y][p.x] = "hazard"
			messages.append("敵の侵食で毒沼が増えた。")

	_cleanup_dead_enemies()
	if player_hp <= 0:
		_show_game_over("敵の攻撃で倒れました。")
		return
	if enemies.is_empty():
		_show_reward()
		return
	_start_player_turn(" ".join(messages))

func _move_enemy_toward(enemy: Dictionary) -> void:
	var move_count := int(enemy["move"])
	var direction := -1
	var enemy_step := int(enemy["step"])
	var player_to_enemy := _forward_distance(player_step, enemy_step)
	var enemy_to_player := _forward_distance(enemy_step, player_step)
	if enemy_to_player < player_to_enemy:
		direction = 1
	for i in range(move_count):
		var next_step := _normalize_step(int(enemy["step"]) + direction)
		var next_pos := _pos_for_step(next_step)
		if not _enemy_at_excluding(next_pos, enemy).is_empty():
			break
		enemy["step"] = next_step
		enemy["pos"] = next_pos

func _show_reward() -> void:
	state = "reward_select"
	board_grid.visible = true
	_clear_children(dice_box)
	_clear_children(reward_box)
	end_turn_button.visible = false
	if encounter >= MAX_ENCOUNTERS:
		_show_victory()
		return
	header_label.text = "戦闘報酬"
	instruction_label.text = _state_instruction()
	route_label.text = _route_status_text()
	stats_label.text = "HP %d/%d   現在のボードは次戦へ持ち越されます。" % [player_hp, player_max_hp]
	enemy_plan_label.text = ""
	log_label.text = "勝利。報酬マスを1つ選んで、永続ボードに配置してください。"

	var options := reward_pool.duplicate(true)
	options.shuffle()
	for i in range(3):
		var reward: Dictionary = options[i]
		var reward_type := str(reward["type"])
		var tile: Dictionary = tile_defs[reward_type]
		var b := Button.new()
		b.text = "[%s] %sマス\n%s / %s" % [tile["kind"], tile["name"], tile["pass"], tile["stop"]]
		b.custom_minimum_size = Vector2(0, 88)
		b.pressed.connect(Callable(self, "_on_reward_selected").bind(reward_type, "%sマス" % tile["name"]))
		_apply_button_color(b, tile["color"], Color("#f5d86a"), 2)
		reward_box.add_child(b)
	_refresh_board()

func _on_reward_selected(tile_type: String, tile_name: String) -> void:
	pending_reward_type = tile_type
	pending_reward_name = tile_name
	state = "reward_place"
	_clear_children(reward_box)
	log_label.text = "%s を置くマスを選んでください。中央以外なら上書きできます。" % tile_name
	_refresh_all()

func _show_victory() -> void:
	state = "victory"
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "踏破成功"
	instruction_label.text = "踏破成功"
	route_label.text = "すごろく式ルート戦闘のプロトタイプはここまでです。"
	stats_label.text = "%s は最終戦を突破しました。" % hero_name
	enemy_plan_label.text = ""
	log_label.text = "別キャラや別配置で再挑戦できます。"
	end_turn_button.visible = false
	restart_button.visible = true
	_refresh_board()

func _show_game_over(reason: String) -> void:
	state = "game_over"
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "ゲームオーバー"
	instruction_label.text = "ゲームオーバー"
	route_label.text = "次は敵を通るルート、攻撃路、防御路の配置を変えて挑戦してください。"
	stats_label.text = reason
	enemy_plan_label.text = ""
	log_label.text = "ボード構築とダイス選択を変えて再挑戦できます。"
	end_turn_button.visible = false
	restart_button.visible = true
	_refresh_board()

func _on_end_turn_pressed() -> void:
	if state == "moving":
		return
	if state == "player":
		log_label.text = "行動を終えました。敵の行動。"
		_enemy_turn()

func _can_step_to(pos: Vector2i) -> bool:
	return false

func _can_place_reward(pos: Vector2i) -> bool:
	if not _inside(pos):
		return false
	if pos == _start_pos():
		return false
	if temp_board[pos.y][pos.x] == "block":
		return false
	return true

func _nearest_enemy(origin: Vector2i, max_range: int) -> Dictionary:
	var best := {}
	var best_dist := 999
	for enemy in enemies:
		var dist := _manhattan(origin, enemy["pos"])
		if dist <= max_range and dist < best_dist:
			best = enemy
			best_dist = dist
	return best

func _line_enemy(origin: Vector2i) -> Dictionary:
	var best := {}
	var best_dist := 999
	for enemy in enemies:
		if _same_line(origin, enemy["pos"]):
			var dist := _manhattan(origin, enemy["pos"])
			if dist < best_dist:
				best = enemy
				best_dist = dist
	return best

func _enemy_at(pos: Vector2i) -> Dictionary:
	for enemy in enemies:
		if enemy["pos"] == pos:
			return enemy
	return {}

func _enemy_at_excluding(pos: Vector2i, excluded: Dictionary) -> Dictionary:
	for enemy in enemies:
		if enemy == excluded:
			continue
		if enemy["pos"] == pos:
			return enemy
	return {}

func _random_empty_cell() -> Vector2i:
	var choices := []
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var p := Vector2i(x, y)
			if p == player_pos:
				continue
			if temp_board[y][x] != "none":
				continue
			if not _enemy_at(p).is_empty():
				continue
			choices.append(p)
	if choices.is_empty():
		return Vector2i(-1, -1)
	return choices[rng.randi_range(0, choices.size() - 1)]

func _take_damage(amount: int) -> void:
	var blocked: int = min(player_shield, amount)
	player_shield -= blocked
	player_hp -= amount - blocked

func _heal(amount: int) -> void:
	player_hp = min(player_max_hp, player_hp + amount)

func _cleanup_dead_enemies() -> void:
	var survivors := []
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			survivors.append(enemy)
	enemies = survivors

func _make_empty_board(value: String) -> Array:
	var board := []
	for y in range(BOARD_H):
		var row := []
		for x in range(BOARD_W):
			row.append(value)
		board.append(row)
	return board

func _build_track_cells() -> void:
	track_cells = []
	for y in range(BOARD_H):
		if y % 2 == 0:
			for x in range(BOARD_W):
				track_cells.append(Vector2i(x, y))
		else:
			for x in range(BOARD_W - 1, -1, -1):
				track_cells.append(Vector2i(x, y))

func _normalize_step(step: int) -> int:
	if track_cells.is_empty():
		return 0
	var size := track_cells.size()
	return ((step % size) + size) % size

func _pos_for_step(step: int) -> Vector2i:
	if track_cells.is_empty():
		return Vector2i.ZERO
	return track_cells[_normalize_step(step)]

func _track_index(pos: Vector2i) -> int:
	for i in range(track_cells.size()):
		if track_cells[i] == pos:
			return i
	return 0

func _forward_distance(from_step: int, to_step: int) -> int:
	if track_cells.is_empty():
		return 0
	var size := track_cells.size()
	return (_normalize_step(to_step) - _normalize_step(from_step) + size) % size

func _track_gap(enemy: Dictionary) -> int:
	var enemy_step := int(enemy.get("step", _track_index(enemy["pos"])))
	var forward := _forward_distance(player_step, enemy_step)
	var backward := _forward_distance(enemy_step, player_step)
	return min(forward, backward)

func _steps_ahead(pos: Vector2i) -> int:
	return _forward_distance(player_step, _track_index(pos))

func _start_pos() -> Vector2i:
	return Vector2i(int(BOARD_W / 2), int(BOARD_H / 2))

func _segment_is_recent(index: int) -> bool:
	if route_path.size() < 2:
		return false
	var a := track_cells[index]
	var b := track_cells[index + 1]
	for i in range(route_path.size() - 1):
		if route_path[i] == a and route_path[i + 1] == b:
			return true
	return false

func _segment_is_next(index: int) -> bool:
	if state != "player":
		return false
	var start := _normalize_step(player_step)
	for ahead in range(0, 6):
		if _normalize_step(start + ahead) == index:
			return true
	return false

func _idx(x: int, y: int) -> int:
	return y * BOARD_W + x

func _inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_W and pos.y >= 0 and pos.y < BOARD_H

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _same_line(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.y == b.y

func _faces_to_text(faces: Array) -> String:
	var parts := []
	for face in faces:
		parts.append(str(face))
	return "/".join(parts)

func _tag_route_bonus(tag: String) -> int:
	if tag == "heavy":
		return 1
	if tag == "fire":
		return 1
	if tag == "lucky" and selected_roll >= 5:
		return 1
	return 0

func _tag_name(tag: String) -> String:
	match tag:
		"fire":
			return "火: 通過攻撃+1"
		"steel":
			return "鉄: 防御向き"
		"heavy":
			return "重撃: 通過攻撃+1"
		"swift":
			return "軽業: 小回り"
		"trick":
			return "仕掛け"
		"lucky":
			return "幸運"
		"arcane":
			return "秘術"
		"focus":
			return "集中"
	return "標準"

func _tag_color(tag: String) -> Color:
	match tag:
		"fire":
			return Color("#8f4932")
		"steel":
			return Color("#455c76")
		"heavy":
			return Color("#68605a")
		"swift":
			return Color("#3f776d")
		"trick":
			return Color("#67487b")
		"lucky":
			return Color("#80733f")
		"arcane":
			return Color("#594c93")
		"focus":
			return Color("#5f7354")
	return Color("#3d4658")

func _hero_color(key: String) -> Color:
	match key:
		"knight":
			return Color("#344b6d")
		"mage":
			return Color("#50396f")
		"rogue":
			return Color("#4f6340")
	return Color("#303948")

func _cell_tooltip(pos: Vector2i, perm_type: String, temp_type: String) -> String:
	var lines := []
	var ahead := _steps_ahead(pos)
	lines.append("コース%d / 現在地から%dマス先" % [_track_index(pos), ahead])
	if pos == player_pos:
		lines.append("自分の現在地")
	var enemy := _enemy_at(pos)
	if not enemy.is_empty():
		lines.append("%s / HP %d / 次: %s" % [enemy["type"], int(enemy["hp"]), _enemy_plan(enemy)])
	if temp_type != "none":
		lines.append(temp_defs[temp_type]["desc"])
	var tile: Dictionary = tile_defs[perm_type]
	lines.append("%s: %s / %s" % [tile["name"], tile["pass"], tile["stop"]])
	return "\n".join(lines)

func _apply_button_color(button: Button, color: Color, border_color: Color = Color("#a9a292"), border_width: int = 1) -> void:
	_apply_font(button)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.border_width_left = border_width
	normal.border_width_top = border_width
	normal.border_width_right = border_width
	normal.border_width_bottom = border_width
	normal.border_color = border_color
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.14)
	button.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = color.darkened(0.42)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("#f5f1e8"))
	button.add_theme_color_override("font_disabled_color", Color("#b7b1a6"))

func _apply_cell_button_color(button: Button, color: Color, border_color: Color, border_width: int, is_player_cell: bool = false, has_enemy: bool = false) -> void:
	_apply_font(button)
	var radius: int = int(max(24.0, _board_token_size() * 0.5))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_left = radius
	normal.corner_radius_bottom_right = radius
	normal.border_width_left = border_width
	normal.border_width_top = border_width
	normal.border_width_right = border_width
	normal.border_width_bottom = border_width
	normal.border_color = border_color
	normal.shadow_color = Color("#00000073")
	normal.shadow_size = 14 if is_player_cell or has_enemy else 8
	normal.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.14)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = color if is_player_cell or has_enemy else color.darkened(0.22)
	button.add_theme_stylebox_override("disabled", disabled)
	var font_color := Color("#fff8e7")
	if is_player_cell:
		font_color = Color("#1d1a12")
	elif has_enemy:
		font_color = Color("#fff3ec")
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_color if is_player_cell or has_enemy else Color("#d3cbbc"))

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _apply_font(control: Control) -> void:
	if ui_font != null:
		control.add_theme_font_override("font", ui_font)
