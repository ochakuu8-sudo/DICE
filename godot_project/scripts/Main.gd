extends Control

const BOARD_W := 4
const BOARD_H := 4
const HAND_LIMIT := 3
const ACTIONS_PER_TURN := 2
const MAX_ENCOUNTERS := 6

# Warm vertical gradient behind the whole screen instead of a flat color,
# so the app reads as a lit dungeon backdrop rather than a plain dark panel.
class Backdrop:
	extends Control

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var top_color := Color("#33264c")
		var mid_color := Color("#241c37")
		var bottom_color := Color("#161022")
		var w: float = size.x
		var h: float = size.y
		var mid_y: float = h * 0.5
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, mid_y), Vector2(0, mid_y)]),
			PackedColorArray([top_color, top_color, mid_color, mid_color])
		)
		draw_polygon(
			PackedVector2Array([Vector2(0, mid_y), Vector2(w, mid_y), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([mid_color, mid_color, bottom_color, bottom_color])
		)
		var glow_radius: float = max(w, h) * 0.62
		var glow_center := Vector2(w * 0.5, h * 0.32)
		var glow_steps := 5
		for i in range(glow_steps, 0, -1):
			var t: float = float(i) / float(glow_steps)
			draw_circle(glow_center, glow_radius * t, Color(0.55, 0.42, 0.75, 0.035))

class BoardView:
	extends Control

	var main: Control
	var glow_phase := 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		glow_phase = fmod(glow_phase + delta, TAU)
		if main != null and main.board_grid == self and (main.state == "player" or main.state == "moving"):
			queue_redraw()

	func _draw() -> void:
		if main == null or main.ring_cells.is_empty():
			return
		var line_color := Color("#6e6556")
		var next_color := Color("#65cfe6")
		var passed_color := Color("#f5d86a")
		var count: int = main.ring_cells.size()
		for i in range(count):
			var a: Vector2i = main.ring_cells[i]
			var b: Vector2i = main.ring_cells[(i + 1) % count]
			var pa: Vector2 = main._board_cell_center(a)
			var pb: Vector2 = main._board_cell_center(b)
			var segment_color := line_color
			var width := 10.0
			if main._segment_is_recent(a, b):
				segment_color = passed_color
				width = 14.0
			elif main._segment_is_next(a, b):
				segment_color = next_color
				width = 12.0
			draw_line(pa, pb, segment_color, width, true)
			_draw_arrow(pa, pb, segment_color)
		_draw_player_marker()

	# The current-position cell used to be told apart only by a gold fill.
	# This adds a dedicated token that floats above the cell, so "this is
	# you" reads as a piece on the board rather than a recolored square.
	func _draw_player_marker() -> void:
		if not main.player_visual_ready:
			return
		var center: Vector2 = main.player_visual_pos
		var token: float = main._board_token_size()
		var lift: Vector2 = center + Vector2(0.0, -token * 0.62 - main.player_hop)
		var pulse: float = 0.5 + sin(glow_phase * 2.2) * 0.5
		var impact: float = main.player_impact
		var glow_r: float = token * (0.46 + pulse * 0.16 + impact * 0.5)
		draw_circle(lift, glow_r, Color(0.89, 0.7, 0.33, 0.16 + pulse * 0.12 + impact * 0.3))
		draw_circle(lift, token * (0.30 + impact * 0.1), Color("#1c130a"))
		draw_circle(lift, token * (0.27 + impact * 0.1), Color("#f6dfa6").lerp(Color.WHITE, impact * 0.6))
		var blade_a: Vector2 = lift + Vector2(-0.14, 0.14) * token
		var blade_b: Vector2 = lift + Vector2(0.14, -0.14) * token
		draw_line(blade_a, blade_b, Color("#3a2a08"), token * 0.055, true)

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

# A tiny vector-icon renderer. Cell tokens used to be told apart only by
# fill color plus a single kanji character; this draws a real glyph per
# tile/enemy kind so the board reads at a glance instead of by color memory.
class IconGlyph:
	extends Control

	var kind := ""
	var glyph_color := Color.WHITE

	func _draw() -> void:
		if kind == "" or kind == "empty":
			return
		var s: float = min(size.x, size.y)
		var c: Vector2 = size * 0.5
		match kind:
			"slash":
				_sword(c, s)
			"guard":
				_shield(c, s)
			"fire":
				_flame(c, s)
			"heal":
				_heart(c, s)
			"bow":
				_bow(c, s)
			"trap":
				_spike(c, s)
			"warp":
				_warp(c, s)
			"shock":
				_bolt(c, s)
			"focus":
				_focus(c, s)
			"skull":
				_skull(c, s)
			"flag_start", "flag_goal":
				_flag(c, s)
			"hub":
				_hub(c, s)
			"fork":
				_fork(c, s)
			"pip_on":
				draw_circle(c, s * 0.34, glyph_color)
			"pip_off":
				draw_arc(c, s * 0.30, 0.0, TAU, 16, glyph_color, s * 0.09, true)

	func _sword(c: Vector2, s: float) -> void:
		var p1 := c + Vector2(-0.30, 0.30) * s
		var p2 := c + Vector2(0.30, -0.30) * s
		draw_line(p1, p2, glyph_color, s * 0.10, true)
		var dir := (p2 - p1).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var guard := p1.lerp(p2, 0.44)
		draw_line(guard - perp * 0.14 * s, guard + perp * 0.14 * s, glyph_color, s * 0.08, true)
		draw_circle(p1, s * 0.07, glyph_color)

	func _shield(c: Vector2, s: float) -> void:
		var pts := [
			c + Vector2(-0.26, -0.30) * s, c + Vector2(0.26, -0.30) * s,
			c + Vector2(0.28, 0.02) * s, c + Vector2(0.0, 0.34) * s,
			c + Vector2(-0.28, 0.02) * s,
		]
		draw_colored_polygon(pts, glyph_color)

	func _flame(c: Vector2, s: float) -> void:
		var pts := [
			c + Vector2(0.0, -0.36) * s, c + Vector2(0.22, -0.04) * s,
			c + Vector2(0.15, 0.30) * s, c + Vector2(0.0, 0.38) * s,
			c + Vector2(-0.15, 0.30) * s, c + Vector2(-0.22, -0.04) * s,
		]
		draw_colored_polygon(pts, glyph_color)

	func _heart(c: Vector2, s: float) -> void:
		var r := s * 0.16
		draw_circle(c + Vector2(-0.15, -0.10) * s, r, glyph_color)
		draw_circle(c + Vector2(0.15, -0.10) * s, r, glyph_color)
		var tri := [c + Vector2(-0.30, -0.02) * s, c + Vector2(0.30, -0.02) * s, c + Vector2(0.0, 0.34) * s]
		draw_colored_polygon(tri, glyph_color)

	func _bow(c: Vector2, s: float) -> void:
		var center := c + Vector2(-0.06, 0.0) * s
		var radius := s * 0.32
		draw_arc(center, radius, -1.2, 1.2, 16, glyph_color, s * 0.07, true)
		var top := center + Vector2(cos(-1.2), sin(-1.2)) * radius
		var bot := center + Vector2(cos(1.2), sin(1.2)) * radius
		draw_line(top, bot, glyph_color, s * 0.05, true)
		var arrow_end := c + Vector2(0.32, 0.0) * s
		draw_line(c + Vector2(-0.06, 0.0) * s, arrow_end, glyph_color, s * 0.05, true)
		var head := [arrow_end, arrow_end + Vector2(-0.11, -0.09) * s, arrow_end + Vector2(-0.11, 0.09) * s]
		draw_colored_polygon(head, glyph_color)

	func _spike(c: Vector2, s: float) -> void:
		var pts := []
		var spikes := 6
		for i in range(spikes * 2):
			var ang := i * PI / spikes
			var r := (0.34 if i % 2 == 0 else 0.13) * s
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, glyph_color)

	func _warp(c: Vector2, s: float) -> void:
		var radius := s * 0.28
		var end_ang := deg_to_rad(250.0)
		draw_arc(c, radius, deg_to_rad(-40.0), end_ang, 20, glyph_color, s * 0.08, true)
		var end_pt := c + Vector2(cos(end_ang), sin(end_ang)) * radius
		var tangent := Vector2(-sin(end_ang), cos(end_ang))
		var head := [end_pt + tangent * 0.15 * s, end_pt + Vector2(cos(end_ang), sin(end_ang)) * 0.13 * s, end_pt - tangent * 0.15 * s]
		draw_colored_polygon(head, glyph_color)

	func _bolt(c: Vector2, s: float) -> void:
		var pts := [
			c + Vector2(0.06, -0.36) * s, c + Vector2(-0.20, 0.04) * s,
			c + Vector2(-0.02, 0.04) * s, c + Vector2(-0.10, 0.36) * s,
			c + Vector2(0.22, -0.06) * s, c + Vector2(0.02, -0.06) * s,
		]
		draw_colored_polygon(pts, glyph_color)

	func _focus(c: Vector2, s: float) -> void:
		draw_arc(c, s * 0.30, 0.0, TAU, 24, glyph_color, s * 0.06, true)
		draw_circle(c, s * 0.11, glyph_color)

	func _skull(c: Vector2, s: float) -> void:
		draw_circle(c + Vector2(0.0, -0.05) * s, s * 0.30, glyph_color)
		var eye_col := Color(0.0, 0.0, 0.0, 0.55)
		draw_circle(c + Vector2(-0.12, -0.08) * s, s * 0.07, eye_col)
		draw_circle(c + Vector2(0.12, -0.08) * s, s * 0.07, eye_col)
		draw_rect(Rect2(c + Vector2(-0.11, 0.18) * s, Vector2(0.07, 0.11) * s), glyph_color)
		draw_rect(Rect2(c + Vector2(0.04, 0.18) * s, Vector2(0.07, 0.11) * s), glyph_color)

	func _flag(c: Vector2, s: float) -> void:
		var base := c + Vector2(-0.16, 0.32) * s
		var top := c + Vector2(-0.16, -0.34) * s
		draw_line(base, top, glyph_color, s * 0.06, true)
		var flag := [top, top + Vector2(0.34, 0.10) * s, top + Vector2(0.0, 0.20) * s]
		draw_colored_polygon(flag, glyph_color)

	# Crossroads landmark: marks the 4-way hub at the board's center.
	func _hub(c: Vector2, s: float) -> void:
		var arm := s * 0.30
		var w := s * 0.11
		draw_line(c + Vector2(0.0, -arm), c + Vector2(0.0, arm), glyph_color, w, true)
		draw_line(c + Vector2(-arm, 0.0), c + Vector2(arm, 0.0), glyph_color, w, true)
		draw_circle(c, s * 0.08, glyph_color)

	# Marks a branch point in the lookahead ribbon: the preview stops here
	# because where you go next is a choice, not a certainty.
	func _fork(c: Vector2, s: float) -> void:
		var base := c + Vector2(0.0, 0.30) * s
		draw_line(base, c, glyph_color, s * 0.09, true)
		draw_line(c, c + Vector2(-0.24, -0.30) * s, glyph_color, s * 0.09, true)
		draw_line(c, c + Vector2(0.24, -0.30) * s, glyph_color, s * 0.09, true)

# Segmented gauge bar for HP/shield: a glanceable strip instead of "HP 36/36"
# as plain text.
class GaugeBar:
	extends Control

	var value := 0
	var max_value := 1
	var segments := 10
	var fill_color := Color("#4f9d72")
	var track_color := Color("#3d3654")

	# display_value trails value: on damage it lingers high and drains down
	# through a red "about to be lost" band; on a gain it climbs up through
	# a bright "just gained" band. A bar that only ever snaps to the new
	# number reads as a static readout, not something that just happened.
	var display_value: float = 0.0:
		set(v):
			display_value = v
			queue_redraw()

	func _draw() -> void:
		if segments <= 0 or size.x <= 0.0 or size.y <= 0.0:
			return
		var gap := 2.0
		var seg_w: float = (size.x - gap * float(segments - 1)) / float(segments)
		var filled := 0
		var trail := 0
		if max_value > 0:
			filled = int(round(float(value) / float(max_value) * float(segments)))
			trail = int(round(display_value / float(max_value) * float(segments)))
		filled = clamp(filled, 0, segments)
		trail = clamp(trail, 0, segments)
		var lo: int = min(filled, trail)
		var hi: int = max(filled, trail)
		var gaining: bool = filled > trail
		for i in range(segments):
			var x: float = i * (seg_w + gap)
			var col: Color
			if i < lo:
				col = fill_color
			elif i < hi:
				col = Color("#f2fff5") if gaining else Color("#ff6a56")
			else:
				col = track_color
			draw_rect(Rect2(Vector2(x, 0.0), Vector2(seg_w, size.y)), col, true)

# A die face drawn with real pips instead of a "面 1/2/3/4/5/6" text string.
class DiceFace:
	extends Control

	var value := 1
	var dot_color := Color("#14171f")
	var face_color := Color("#ede7d8")

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), face_color, true)
		var dot_r: float = min(size.x, size.y) * 0.09
		for p in _pip_positions(value):
			draw_circle(Vector2(p.x * size.x, p.y * size.y), dot_r, dot_color)

	func _pip_positions(v: int) -> Array:
		var l := 0.24
		var c := 0.5
		var r := 0.76
		var t := 0.24
		var m := 0.5
		var b := 0.76
		match v:
			1:
				return [Vector2(c, m)]
			2:
				return [Vector2(l, t), Vector2(r, b)]
			3:
				return [Vector2(l, t), Vector2(c, m), Vector2(r, b)]
			4:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, b), Vector2(r, b)]
			5:
				return [Vector2(l, t), Vector2(r, t), Vector2(c, m), Vector2(l, b), Vector2(r, b)]
			_:
				return [Vector2(l, t), Vector2(r, t), Vector2(l, m), Vector2(r, m), Vector2(l, b), Vector2(r, b)]

# A short expanding ring + radiating spark lines, played once at an enemy's
# cell when it's defeated. Driving redraws off a single tweened "progress"
# property keeps the whole effect to one _draw() call.
class BurstEffect:
	extends Control

	var center := Vector2.ZERO
	var token := 40.0
	var progress: float = 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		var a: float = 1.0 - progress
		if a <= 0.0:
			return
		var ring_r: float = token * (0.32 + progress * 0.85)
		draw_arc(center, ring_r, 0.0, TAU, 22, Color(1.0, 0.85, 0.6, a * 0.85), token * 0.10 * (1.0 - progress * 0.6), true)
		for i in range(6):
			var ang: float = i * TAU / 6.0
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(center + dir * token * 0.22, center + dir * ring_r, Color(1.0, 0.78, 0.5, a), token * 0.05, true)

var rng := RandomNumberGenerator.new()

var bg_rect: Control
var root_box: VBoxContainer
var header_label: Label
var instruction_label: Label
var route_label: Label
var gauges_box: VBoxContainer
var hp_bar: GaugeBar
var hp_value_label: Label
var shield_bar: GaugeBar
var shield_value_label: Label
var action_pip_box: HBoxContainer
var ledger_box: HFlowContainer
var stats_label: Label
var enemy_status_box: VBoxContainer
var lookahead_box: HBoxContainer
var board_grid: BoardView
var dice_box: HBoxContainer
var command_box: HBoxContainer
var reward_box: VBoxContainer
var log_label: Label
var end_turn_button: Button
var restart_button: Button
var ui_font: Font
var ui_font_heavy: Font

var cell_buttons: Array = []
var cell_icons: Array = []
var cell_index_labels: Array = []
var cell_badges: Array = []

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
var player_visual_pos := Vector2.ZERO
var player_visual_ready := false
var player_hop := 0.0
var player_impact := 0.0

# Board topology: a single one-way ring around the perimeter. Enemies live
# off-board (see enemy_status_box) and never occupy a cell — the ring is
# purely the player's own resource/hazard track.
var ring_cells: Array[Vector2i] = []
var ring_index_map: Dictionary = {}
var ring_forward: Dictionary = {}
var preview_path: Array[Vector2i] = []

# Cells the player has passed through or stopped on this *turn* (across
# every die rolled this turn, not just the current one) — checked against
# each enemy's telegraph when the turn ends.
var turn_visited: Dictionary = {}

var permanent_board: Array = []
var temp_board: Array = []
var enemies: Array = []
var next_enemy_uid := 0
# The HP each bar is currently *showing*, per enemy uid — separate from the
# enemy's real "hp", which mutates the instant a tile hits it. While
# suppress_stat_reveal is on, this is what stays on screen; _flush_turn_ledger
# is what lets it catch up to the real value.
var enemy_hp_prev: Dictionary = {}
# While true (during the player's own movement/dice resolution), tile
# effects still mutate real state immediately but skip revealing it on the
# HP/shield bars and enemy panel — they queue a ledger chip instead. See
# _flush_turn_ledger, which is what turns this back off and reveals the
# turn's net result in one animated pass.
var suppress_stat_reveal := false
# One running-total entry per ledger chip kind (and per enemy uid, for
# damage dealt): key -> {"panel": Control, "label": Label, "total": int}.
var ledger_chips: Dictionary = {}
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
	"empty": {"short": "道", "name": "道", "kind": "基本", "color": Color("#453a5c"), "pass": "", "stop": "停止: シールド+1"},
	"slash": {"short": "攻", "name": "斬撃路", "kind": "攻撃", "color": Color("#a74646"), "pass": "通過: 最もHPが低い敵に2+コンボダメージ", "stop": "停止: 最もHPが低い敵に4+コンボダメージ"},
	"guard": {"short": "守", "name": "防御路", "kind": "防御", "color": Color("#3d67a8"), "pass": "通過: シールド+1", "stop": "停止: シールド+3"},
	"fire": {"short": "火", "name": "火走り", "kind": "攻撃", "color": Color("#bd6238"), "pass": "通過: 全敵に1+コンボダメージ", "stop": "停止: 最もHPが低い敵に3+コンボダメージ"},
	"heal": {"short": "癒", "name": "癒し道", "kind": "回復", "color": Color("#459a5d"), "pass": "通過: HP+1", "stop": "停止: HP+3"},
	"bow": {"short": "射", "name": "射撃台", "kind": "遠隔", "color": Color("#a59446"), "pass": "通過: 最もHPが低い敵に1+コンボダメージ", "stop": "停止: 最もHPが低い敵に3+コンボダメージ"},
	"trap": {"short": "罠", "name": "罠道", "kind": "牽制", "color": Color("#7550a8"), "pass": "通過: 最もHPが高い敵に2+コンボダメージ", "stop": "停止: 最もHPが高い敵に4+コンボダメージ"},
	"warp": {"short": "跳", "name": "跳躍路", "kind": "移動", "color": Color("#2f8c9b"), "pass": "通過: 追加で1歩進める", "stop": "停止: 追加行動+1"},
	"shock": {"short": "雷", "name": "雷線", "kind": "全体", "color": Color("#7d70d6"), "pass": "通過: 全敵に1+コンボダメージ", "stop": "停止: 全敵に2+コンボダメージ"},
	"focus": {"short": "集", "name": "集中路", "kind": "補助", "color": Color("#718063"), "pass": "通過: シールド+1、以降の攻撃+1", "stop": "停止: ダイスを1個引く"}
}

var temp_defs := {
	"none": {"short": "", "color": Color("#00000000"), "desc": ""},
	"hazard": {"short": "毒", "color": Color("#58385c"), "desc": "通過: HP-2"},
	"block": {"short": "壁", "color": Color("#161022"), "desc": "通れない"}
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
		"desc": "盤面は斬撃路と防御路で埋め尽くされている。HPの低い敵から確実に仕留める。",
		"dice": [
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"},
			{"name": "重撃ダイス", "faces": [3, 4, 4, 5, 6, 6], "tag": "heavy"},
			{"name": "守りダイス", "faces": [1, 2, 2, 3, 3, 4], "tag": "steel"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [
			[0, 0, "slash"], [1, 0, "guard"], [2, 0, "slash"], [3, 0, "guard"],
			[3, 1, "slash"], [3, 2, "guard"], [3, 3, "slash"], [2, 3, "guard"],
			[1, 3, "slash"], [0, 3, "guard"], [0, 2, "slash"], [0, 1, "guard"]
		]
	},
	"mage": {
		"name": "魔導士",
		"hp": 28,
		"desc": "盤面は火走りと防御路で埋め尽くされている。敵全体を薄く広く削っていく。",
		"dice": [
			{"name": "火花ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "fire"},
			{"name": "揺らぎダイス", "faces": [1, 1, 3, 5, 6, 6], "tag": "arcane"},
			{"name": "集中ダイス", "faces": [2, 2, 3, 3, 4, 4], "tag": "focus"},
			{"name": "標準ダイス", "faces": [1, 2, 3, 4, 5, 6], "tag": "normal"}
		],
		"tiles": [
			[0, 0, "fire"], [1, 0, "guard"], [2, 0, "fire"], [3, 0, "guard"],
			[3, 1, "fire"], [3, 2, "guard"], [3, 3, "fire"], [2, 3, "guard"],
			[1, 3, "fire"], [0, 3, "guard"], [0, 2, "fire"], [0, 1, "guard"]
		]
	},
	"rogue": {
		"name": "盗賊",
		"hp": 31,
		"desc": "盤面は斬撃路と防御路で埋め尽くされている。報酬で罠や射撃台を仕込んで育てる。",
		"dice": [
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"},
			{"name": "仕掛けダイス", "faces": [1, 2, 3, 3, 5, 6], "tag": "trick"},
			{"name": "幸運ダイス", "faces": [1, 2, 2, 4, 4, 6], "tag": "lucky"},
			{"name": "軽業ダイス", "faces": [1, 1, 2, 2, 3, 4], "tag": "swift"}
		],
		"tiles": [
			[0, 0, "slash"], [1, 0, "guard"], [2, 0, "slash"], [3, 0, "guard"],
			[3, 1, "slash"], [3, 2, "guard"], [3, 3, "slash"], [2, 3, "guard"],
			[1, 3, "slash"], [0, 3, "guard"], [0, 2, "slash"], [0, 1, "guard"]
		]
	}
}

func _ready() -> void:
	rng.randomize()
	_build_track_graph()
	# DotGothic16: a dot-matrix / retro-arcade style Japanese font, blocky
	# and bold by design rather than a thin general-purpose UI face. It's a
	# single static weight, so the "heavy" variant is a synthetic embolden
	# instead of a variable-font axis.
	var base_font: Font = load("res://assets/DotGothic16.ttf")
	var regular_variation := FontVariation.new()
	regular_variation.base_font = base_font
	regular_variation.variation_embolden = 0.15
	ui_font = regular_variation
	var heavy_variation := FontVariation.new()
	heavy_variation.base_font = base_font
	heavy_variation.variation_embolden = 0.85
	ui_font_heavy = heavy_variation
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
		bg_rect.queue_redraw()
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
	bg_rect = Backdrop.new()
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root_box)

	header_label = _make_label(26, Color("#f5f1e8"), HORIZONTAL_ALIGNMENT_CENTER, true)
	root_box.add_child(header_label)
	instruction_label = _make_label(21, Color("#ffe28a"), HORIZONTAL_ALIGNMENT_CENTER, true)
	root_box.add_child(instruction_label)
	route_label = _make_label(16, Color("#dfe7f3"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(route_label)

	gauges_box = VBoxContainer.new()
	gauges_box.add_theme_constant_override("separation", 4)
	gauges_box.custom_minimum_size = Vector2(280, 0)
	gauges_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root_box.add_child(gauges_box)
	hp_bar = GaugeBar.new()
	hp_value_label = Label.new()
	gauges_box.add_child(_build_gauge_row("HP", Color("#f0b7a7"), Color("#4f9d72"), hp_bar, hp_value_label))
	shield_bar = GaugeBar.new()
	shield_bar.fill_color = Color("#4d7fc4")
	shield_value_label = Label.new()
	gauges_box.add_child(_build_gauge_row("盾", Color("#8fb6e8"), Color("#4d7fc4"), shield_bar, shield_value_label))

	action_pip_box = HBoxContainer.new()
	action_pip_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_pip_box.add_theme_constant_override("separation", 6)
	root_box.add_child(action_pip_box)

	# Holds a chip per tile effect queued this turn (see _queue_ledger_entry)
	# — this is what "moves" while the HP/shield bars stay frozen, so the
	# player watches the tally build up instead of the bars twitching per
	# tile. _flush_turn_ledger clears it once the bars catch up at turn end.
	ledger_box = HFlowContainer.new()
	ledger_box.alignment = FlowContainer.ALIGNMENT_CENTER
	ledger_box.add_theme_constant_override("h_separation", 5)
	ledger_box.add_theme_constant_override("v_separation", 4)
	ledger_box.custom_minimum_size = Vector2(320, 0)
	ledger_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root_box.add_child(ledger_box)

	stats_label = _make_label(14, Color("#8d95ab"), HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(stats_label)

	enemy_status_box = VBoxContainer.new()
	enemy_status_box.add_theme_constant_override("separation", 3)
	enemy_status_box.custom_minimum_size = Vector2(330, 0)
	enemy_status_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root_box.add_child(enemy_status_box)

	lookahead_box = HBoxContainer.new()
	lookahead_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lookahead_box.add_theme_constant_override("separation", 5)
	root_box.add_child(lookahead_box)

	board_grid = BoardView.new()
	board_grid.main = self
	board_grid.size_flags_vertical = Control.SIZE_FILL
	board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_grid.custom_minimum_size = Vector2(0, 430)
	board_grid.resized.connect(Callable(self, "_layout_board_buttons"))
	board_grid.resized.connect(Callable(self, "_resync_player_visual"))
	root_box.add_child(board_grid)

	for i in range(BOARD_W * BOARD_H):
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(58, 58)
		_apply_font(cell)
		cell.add_theme_font_size_override("font_size", 13)
		cell.pressed.connect(Callable(self, "_on_cell_pressed").bind(i))
		board_grid.add_child(cell)
		cell_buttons.append(cell)

		var icon := IconGlyph.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(icon)
		cell_icons.append(icon)

		var index_label := Label.new()
		index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		index_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		index_label.position = Vector2(4, 1)
		_apply_font(index_label)
		index_label.add_theme_font_size_override("font_size", 9)
		index_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		cell.add_child(index_label)
		cell_index_labels.append(index_label)

		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.position = Vector2(-26, -19)
		_apply_font(badge)
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color("#fff1ea"))
		badge.add_theme_constant_override("outline_size", 5)
		badge.add_theme_color_override("font_outline_color", Color("#4a120c"))
		cell.add_child(badge)
		cell_badges.append(badge)

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

func _make_label(size: int, color: Color, align: HorizontalAlignment, heavy: bool = false) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(label, heavy)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _build_gauge_row(caption: String, caption_color: Color, fill_color: Color, bar: GaugeBar, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := _make_label(12, caption_color, HORIZONTAL_ALIGNMENT_LEFT)
	cap.text = caption
	cap.custom_minimum_size = Vector2(24, 0)
	row.add_child(cap)
	bar.fill_color = fill_color
	bar.custom_minimum_size = Vector2(0, 11)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	_apply_font(value_label, true)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color("#fff8ec"))
	value_label.custom_minimum_size = Vector2(54, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row

func _show_title() -> void:
	state = "title"
	encounter = 0
	board_grid.visible = false
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "Dice Board Rogue"
	instruction_label.text = "キャラクターを選択"
	route_label.text = "環状のコースを出目ぶん前進し、攻撃マスを踏んで敵を倒します。敵は中央から攻撃を予告してきます。"
	stats_label.text = "予告された危険マスを避けつつ、攻撃・防御マスを踏むダイスを選びましょう。"
	_clear_children(enemy_status_box)
	log_label.text = "戦闘後は毎回、新しいマスを永続ボードへ配置します。育てたコースで戦いましょう。"
	end_turn_button.visible = false
	restart_button.visible = false
	gauges_box.visible = false
	action_pip_box.visible = false
	lookahead_box.visible = false

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
	next_enemy_uid = 0
	enemy_hp_prev = {}
	player_step = _track_index(_start_pos())
	player_pos = _pos_for_step(player_step)
	_snap_player_visual()
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
	_snap_player_visual()
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
		enemies.append(_make_enemy("ボス", 32, 8, "guaranteed", []))
		enemies.append(_make_enemy("護衛", 12, 4, "positional", [1, 3]))
		enemies.append(_make_enemy("護衛", 12, 4, "positional", [2, 5]))
	else:
		var enemy_count: int = min(2 + int(encounter / 2), 4)
		for i in range(enemy_count):
			var type_name := "敵"
			var hp := 8 + encounter * 2
			var damage := 3 + int(encounter / 2)
			var attack_kind := "positional"
			var offsets: Array = [2 + i]
			if encounter >= 3 and i == 0:
				type_name = "射手"
				hp -= 2
				damage += 1
				attack_kind = "guaranteed"
				offsets = []
			elif encounter >= 4 and i == 1:
				type_name = "重装"
				hp += 6
				damage += 2
				offsets = [1, 3, 5]
			enemies.append(_make_enemy(type_name, hp, damage, attack_kind, offsets))

	for n in range(min(encounter, 4)):
		var p2 := _random_empty_cell()
		if p2.x >= 0:
			temp_board[p2.y][p2.x] = "hazard"

	for enemy in enemies:
		_generate_telegraph(enemy)

# attack_kind "guaranteed" always hits the player each turn; "positional"
# only hits if the player's route this turn touches one of the cells it
# telegraphs (attack_offsets: ring steps ahead of the player, resolved to
# fixed cells at telegraph time — see _generate_telegraph).
func _make_enemy(type_name: String, hp: int, damage: int, attack_kind: String, offsets: Array) -> Dictionary:
	next_enemy_uid += 1
	return {
		"type": type_name,
		"uid": next_enemy_uid,
		"hp": hp,
		"max_hp": hp,
		"damage": damage,
		"attack_kind": attack_kind,
		"attack_offsets": offsets,
		"telegraph_cells": [],
	}

# Locks in this enemy's next attack. For a positional attacker, the target
# cells are fixed now, based on the player's position right now — they do
# not follow the player around as the turn plays out.
func _generate_telegraph(enemy: Dictionary) -> void:
	if str(enemy.get("attack_kind", "positional")) == "guaranteed":
		enemy["telegraph_cells"] = []
		return
	var cells: Array = []
	for offset in enemy.get("attack_offsets", []):
		cells.append(_pos_for_step(player_step + int(offset)))
	enemy["telegraph_cells"] = cells

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
	turn_visited = {}
	ledger_chips = {}
	if ledger_box != null:
		_clear_children(ledger_box)
	_draw_to_hand()
	if message != "":
		log_label.text = message
	suppress_stat_reveal = false
	_refresh_all()
	# From here until _flush_turn_ledger runs (turn end), tile effects queue
	# into the ledger instead of moving the bars right away.
	suppress_stat_reveal = true

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
	gauges_box.visible = true
	action_pip_box.visible = true
	ledger_box.visible = state == "player" or state == "moving"

	hp_bar.max_value = max(player_max_hp, 1)
	hp_bar.segments = clamp(player_max_hp, 1, 18)
	# While suppress_stat_reveal is on, the bars/numbers stay exactly as they
	# were at the start of this turn — tile effects are still queuing up in
	# the ledger instead. _flush_turn_ledger is what turns this back off.
	if not suppress_stat_reveal:
		hp_bar.fill_color = _hp_ratio_color(float(player_hp) / float(max(player_max_hp, 1)))
		_animate_bar(hp_bar, player_hp)
		hp_value_label.text = "%d / %d" % [player_hp, player_max_hp]

	var shield_cap: int = clamp(max(player_shield, 6), 1, 14)
	if not suppress_stat_reveal:
		shield_bar.max_value = shield_cap
		shield_bar.segments = shield_cap
		_animate_bar(shield_bar, player_shield)
		shield_value_label.text = str(player_shield)

	_clear_children(action_pip_box)
	for i in range(ACTIONS_PER_TURN):
		var pip := IconGlyph.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.kind = "pip_on" if i < actions_left else "pip_off"
		pip.glyph_color = Color("#e3b355") if i < actions_left else Color("#4a5470")
		action_pip_box.add_child(pip)

	stats_label.text = "山札 %d　捨札 %d　手札 %d" % [draw_pile.size(), discard_pile.size(), hand.size()]
	_refresh_enemy_status()

# Lets a GaugeBar's fill catch up to its new value instead of snapping,
# with a short pause first so the ghost band (see GaugeBar._draw) has a
# beat to register before it starts closing.
func _animate_bar(bar: GaugeBar, new_value: int) -> void:
	if bar.value == new_value:
		return
	bar.value = new_value
	var tween := create_tween()
	tween.tween_interval(0.12)
	tween.tween_property(bar, "display_value", float(new_value), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# A quick scale punch, safe to use on children of Container nodes: unlike
# position, scale/pivot aren't touched by container layout passes, so this
# never fights the parent VBoxContainer over where the node sits.
func _punch_control(control: Control, peak_scale: float = 1.05, out_time: float = 0.06, back_time: float = 0.14) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size / 2.0
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(peak_scale, peak_scale), out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(1.0, 1.0), back_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Green while healthy, amber in the middle, red when in danger — the color
# itself carries the warning, not just the fraction filled.
func _hp_ratio_color(ratio: float) -> Color:
	if ratio > 0.55:
		return Color("#4f9d72")
	if ratio > 0.25:
		return Color("#c9a23f")
	return Color("#c1483a")

# Enemy bars stay in the "danger" family throughout (a full-HP enemy is not
# "safe" the way full player HP is): bright ember while strong, fading
# toward a dull, weakened tone as it nears death.
func _enemy_hp_color(ratio: float) -> Color:
	return Color("#5c463d").lerp(Color("#e2704a"), clamp(ratio, 0.0, 1.0))

func _refresh_enemy_status() -> void:
	if enemy_status_box == null:
		return
	_clear_children(enemy_status_box)
	enemy_status_box.visible = state != "title" and not enemies.is_empty()
	for enemy in enemies:
		enemy_status_box.add_child(_make_enemy_status_row(enemy))

func _make_enemy_status_row(enemy: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)

	var icon := IconGlyph.new()
	icon.kind = "skull"
	icon.glyph_color = Color("#f0b7a7")
	icon.custom_minimum_size = Vector2(15, 15)
	row.add_child(icon)

	var name_label := _make_label(11, Color("#f0b7a7"), HORIZONTAL_ALIGNMENT_LEFT)
	name_label.text = str(enemy["type"])
	name_label.custom_minimum_size = Vector2(46, 0)
	row.add_child(name_label)

	var max_hp: int = max(int(enemy["max_hp"]), 1)
	var real_hp: int = int(enemy["hp"])
	var uid: int = int(enemy.get("uid", -1))
	var prev_hp: int = int(enemy_hp_prev.get(uid, real_hp))
	# Mid-turn (suppressed), this row keeps showing whatever it showed last
	# turn — real_hp may already have dropped (even to 0, if this enemy
	# died to a combo mid-move) but that only becomes visible at the flush.
	var shown_hp: int = prev_hp if suppress_stat_reveal else real_hp
	var bar := GaugeBar.new()
	bar.fill_color = _enemy_hp_color(float(shown_hp) / float(max_hp))
	bar.track_color = Color("#3d3654")
	bar.value = shown_hp
	bar.display_value = float(prev_hp)
	bar.max_value = max_hp
	bar.segments = clamp(max_hp, 1, 14)
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	if not suppress_stat_reveal:
		if prev_hp != real_hp:
			var tween := create_tween()
			tween.tween_interval(0.12)
			tween.tween_property(bar, "display_value", float(real_hp), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		enemy_hp_prev[uid] = real_hp

	var value_label := _make_label(12, Color("#fff8ec"), HORIZONTAL_ALIGNMENT_RIGHT, true)
	value_label.text = "%d/%d" % [shown_hp, max_hp]
	value_label.custom_minimum_size = Vector2(44, 0)
	row.add_child(value_label)

	var plan_label := _make_label(10, Color("#8d95ab"), HORIZONTAL_ALIGNMENT_LEFT)
	plan_label.text = _enemy_plan(enemy)
	plan_label.custom_minimum_size = Vector2(88, 0)
	row.add_child(plan_label)

	return row

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

# Places the piece token instantly at player_pos with no motion — for a
# fresh spawn (run start, new encounter), not an in-turn step. Waits a
# couple of frames first: board_grid has often just become visible, and
# its real size isn't final until the container layout pass catches up
# (see _resync_player_visual for the general case, e.g. window resize).
func _snap_player_visual() -> void:
	player_visual_ready = false
	await get_tree().process_frame
	await get_tree().process_frame
	player_visual_pos = _board_cell_center(player_pos)
	player_visual_ready = true
	player_hop = 0.0

func _resync_player_visual() -> void:
	if player_visual_ready:
		player_visual_pos = _board_cell_center(player_pos)

# Hops the piece token from wherever it's currently drawn to player_pos:
# a straight slide plus a small up-and-down arc, instead of teleporting.
func _animate_player_step(duration: float = 0.16) -> void:
	var target: Vector2 = _board_cell_center(player_pos)
	if not player_visual_ready:
		_snap_player_visual()
		return
	var move_tween := create_tween()
	move_tween.tween_property(self, "player_visual_pos", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var hop_tween := create_tween()
	hop_tween.tween_property(self, "player_hop", 16.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(self, "player_hop", 0.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await move_tween.finished

# A brief bright pulse on the player's own token when a *stop* effect
# resolves — stronger than a pass, so stopping reads as the bigger event
# it mechanically is, even before the popup text is parsed.
func _flash_player_stop() -> void:
	player_impact = 1.0
	var tween := create_tween()
	tween.tween_property(self, "player_impact", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
		return "コースは一方通行。敵の攻撃予告と効果マスを見て、ちょうどよい出目のダイスを選びましょう。"
	if state == "reward_select":
		return "選んだマスは永続ボードに残ります。次の戦闘のルートが変わります。"
	if state == "reward_place":
		return "配置中: %s" % pending_reward_name
	return ""

func _enemy_plan(enemy: Dictionary) -> String:
	if str(enemy.get("attack_kind", "positional")) == "guaranteed":
		return "必中%d" % int(enemy["damage"])
	var offsets: Array = enemy.get("attack_offsets", [])
	var parts := []
	for o in offsets:
		parts.append(str(o))
	return "%sマス先 %d" % ["・".join(parts), int(enemy["damage"])]

func _refresh_board() -> void:
	_rebuild_preview_path()
	_layout_board_buttons()
	var danger_cells := _telegraphed_cells()
	for y in range(BOARD_H):
		for x in range(BOARD_W):
			var idx := _idx(x, y)
			var button: Button = cell_buttons[idx]
			var icon: IconGlyph = cell_icons[idx]
			var index_label: Label = cell_index_labels[idx]
			var badge: Label = cell_badges[idx]
			var pos := Vector2i(x, y)

			if not ring_index_map.has(pos):
				# Off-ring cell: enemies live in the status panel now, not
				# on the board, so only the ring itself is ever clickable.
				button.visible = false
				button.disabled = true
				continue
			button.visible = true

			var perm_type: String = str(permanent_board[y][x])
			var temp_type: String = str(temp_board[y][x])
			var color: Color = tile_defs[perm_type]["color"]
			var icon_kind: String = perm_type if perm_type != "empty" else ""
			var border_color := Color("#a9a292")
			var border_width := 1
			var is_player_cell := pos == player_pos
			var is_start := pos == _start_pos()

			if temp_type != "none":
				color = temp_defs[temp_type]["color"]
				icon_kind = "trap" if temp_type == "hazard" else ""

			if is_start:
				index_label.text = "始"
				icon_kind = "flag_start"
			else:
				index_label.text = "%02d" % int(ring_index_map[pos])

			badge.text = ""

			var is_danger := danger_cells.has(pos)
			if is_danger:
				color = Color("#7a2a2a")
				border_color = Color("#ff8f6b")
				border_width = 5
				badge.text = "!"

			if is_player_cell:
				color = Color("#e1b93c")
				border_color = Color("#fff2a1")
				border_width = 6
			elif route_path.has(pos):
				border_color = Color("#f5d86a")
				border_width = 3
				color = color.lightened(0.14)
			elif not is_danger and state == "player":
				var ahead := _steps_ahead(pos)
				if ahead > 0:
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

			button.text = ""
			button.tooltip_text = _cell_tooltip(pos, perm_type, temp_type)
			icon.kind = icon_kind
			icon.glyph_color = Color(1, 1, 1, 0.92)
			icon.queue_redraw()
			_apply_cell_button_color(button, color, border_color, border_width, is_player_cell, is_danger)
	board_grid.queue_redraw()
	_refresh_lookahead()

# Union of every living enemy's telegraphed cells, for the board's warning
# highlight. Only meaningful once the encounter is under way.
func _telegraphed_cells() -> Dictionary:
	var cells := {}
	if state == "title" or state == "reward_select":
		return cells
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		for c in enemy.get("telegraph_cells", []):
			cells[c] = true
	return cells

func _refresh_lookahead() -> void:
	if lookahead_box == null:
		return
	_clear_children(lookahead_box)
	lookahead_box.visible = state == "player"
	if state != "player":
		return
	for pos in preview_path:
		lookahead_box.add_child(_make_lookahead_chip(pos))

func _make_lookahead_chip(pos: Vector2i) -> Control:
	var perm_type: String = str(permanent_board[pos.y][pos.x])
	var temp_type: String = str(temp_board[pos.y][pos.x])
	var color: Color = tile_defs[perm_type]["color"]
	var kind: String = perm_type if perm_type != "empty" else ""
	if temp_type != "none":
		color = temp_defs[temp_type]["color"]
		kind = "trap" if temp_type == "hazard" else ""

	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(34, 34)
	var box := StyleBoxFlat.new()
	box.corner_radius_top_left = 10
	box.corner_radius_top_right = 10
	box.corner_radius_bottom_left = 10
	box.corner_radius_bottom_right = 10
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = Color(1, 1, 1, 0.12)

	var is_danger := _telegraphed_cells().has(pos)
	if is_danger:
		color = Color("#7a2a2a")
		box.border_color = Color("#ff8f6b")
	box.bg_color = color
	wrap.add_theme_stylebox_override("panel", box)

	var icon := IconGlyph.new()
	icon.kind = kind
	icon.glyph_color = Color(1, 1, 1, 0.92)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(icon)

	if is_danger:
		var warn_tag := Label.new()
		warn_tag.text = "!"
		_apply_font(warn_tag)
		warn_tag.add_theme_font_size_override("font_size", 13)
		warn_tag.add_theme_color_override("font_color", Color("#fff1ea"))
		warn_tag.add_theme_constant_override("outline_size", 4)
		warn_tag.add_theme_color_override("font_outline_color", Color("#4a120c"))
		warn_tag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		warn_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		warn_tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
		warn_tag.position = Vector2(-14, -15)
		wrap.add_child(warn_tag)

	return wrap

func _refresh_dice() -> void:
	_clear_children(dice_box)
	if state != "player" and state != "moving":
		return
	for i in range(hand.size()):
		var die: Dictionary = hand[i]
		var b := Button.new()
		var tag := str(die["tag"])
		var faces: Array = die["faces"]
		b.text = ""
		b.custom_minimum_size = Vector2(126, 128)
		b.disabled = state != "player" or actions_left <= 0
		b.pressed.connect(Callable(self, "_on_die_pressed").bind(i))
		_apply_button_color(b, _tag_color(tag))

		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		b.add_child(col)

		var face := DiceFace.new()
		face.value = _die_display_value(faces)
		face.custom_minimum_size = Vector2(34, 34)
		face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(face)

		var name_label := _make_label(13, Color("#f5f1e8"), HORIZONTAL_ALIGNMENT_CENTER)
		name_label.text = str(die["name"])
		col.add_child(name_label)

		var range_label := _make_label(10, Color("#c9c2b2"), HORIZONTAL_ALIGNMENT_CENTER)
		range_label.text = _faces_to_text(faces)
		col.add_child(range_label)

		var tag_label := _make_label(10, Color("#f6dfa6"), HORIZONTAL_ALIGNMENT_CENTER)
		tag_label.text = _tag_name(tag)
		col.add_child(tag_label)

		dice_box.add_child(b)

func _die_display_value(faces: Array) -> int:
	if faces.is_empty():
		return 1
	var sorted_faces: Array = faces.duplicate()
	sorted_faces.sort()
	return int(sorted_faces[int(sorted_faces.size() / 2)])

func _set_dice_box_disabled(flag: bool) -> void:
	for child in dice_box.get_children():
		if child is Button:
			child.disabled = flag

# Flickers the pressed die through a few random faces before settling on
# the real roll, with a small punch on landing — instead of the result
# just appearing.
# Tumbles the die through random faces with wobble/jitter that slows down
# as it "settles" (like a physical die losing momentum), then lands on the
# real roll with an overshoot bounce — a flat value-swap didn't feel like
# anything was actually being rolled.
func _animate_dice_roll(button: Button, faces: Array, final_value: int) -> void:
	if button == null or not is_instance_valid(button) or button.get_child_count() == 0:
		return
	var col: Node = button.get_child(0)
	if col == null or col.get_child_count() == 0:
		return
	var face: DiceFace = col.get_child(0) as DiceFace
	if face == null:
		return
	face.pivot_offset = face.size / 2.0
	var base_pos: Vector2 = face.position
	var delays: Array = [0.035, 0.04, 0.045, 0.055, 0.07, 0.09, 0.12]
	for i in range(delays.size()):
		face.value = int(faces[rng.randi_range(0, faces.size() - 1)])
		var settle: float = float(i) / float(delays.size() - 1)
		var wobble: float = deg_to_rad(28.0) * (1.0 - settle)
		face.rotation = rng.randf_range(-wobble, wobble)
		var jitter: float = 3.5 * (1.0 - settle)
		face.position = base_pos + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		face.queue_redraw()
		await get_tree().create_timer(delays[i]).timeout
		if not is_instance_valid(face):
			return
	face.value = final_value
	face.position = base_pos
	face.queue_redraw()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(face, "scale", Vector2(1.4, 1.4), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(face, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(face, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

func _on_die_pressed(index: int) -> void:
	if state != "player" or index < 0 or index >= hand.size() or actions_left <= 0:
		return
	var die: Dictionary = hand[index]
	var faces: Array = die["faces"]
	var final_roll := int(faces[rng.randi_range(0, faces.size() - 1)])

	_set_dice_box_disabled(true)
	if index < dice_box.get_child_count():
		await _animate_dice_roll(dice_box.get_child(index) as Button, faces, final_roll)

	selected_die = die.duplicate(true)
	selected_roll = final_roll
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
	elif ring_index_map.has(pos):
		_show_cell_info(pos)

var cell_info_panel: Control = null

# Tooltips only show on hover, which doesn't exist on touch — this is the
# tap equivalent: a small card with the tile's actual effect text, anchored
# over the tapped cell for a couple of seconds.
func _show_cell_info(pos: Vector2i) -> void:
	if cell_info_panel != null and is_instance_valid(cell_info_panel):
		cell_info_panel.queue_free()
		cell_info_panel = null

	var idx := _idx(pos.x, pos.y)
	if idx < 0 or idx >= cell_buttons.size():
		return
	var anchor_button: Button = cell_buttons[idx]

	var perm_type: String = str(permanent_board[pos.y][pos.x])
	var temp_type: String = str(temp_board[pos.y][pos.x])
	var tile: Dictionary = tile_defs[perm_type]

	var panel := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#2e2645")
	box.border_color = Color("#e3b355")
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.corner_radius_top_left = 10
	box.corner_radius_top_right = 10
	box.corner_radius_bottom_left = 10
	box.corner_radius_bottom_right = 10
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	box.shadow_size = 8
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 30

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	var title_label := _make_label(13, Color("#f6dfa6"), HORIZONTAL_ALIGNMENT_LEFT)
	title_label.text = tile["name"]
	col.add_child(title_label)

	if str(tile["pass"]) != "":
		var pass_label := _make_label(11, Color("#d7d2c4"), HORIZONTAL_ALIGNMENT_LEFT)
		pass_label.text = str(tile["pass"])
		pass_label.custom_minimum_size = Vector2(210, 0)
		pass_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(pass_label)

	var stop_label := _make_label(11, Color("#d7d2c4"), HORIZONTAL_ALIGNMENT_LEFT)
	stop_label.text = str(tile["stop"])
	stop_label.custom_minimum_size = Vector2(210, 0)
	stop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(stop_label)

	if temp_type != "none":
		var temp_label := _make_label(11, Color("#e6a9c9"), HORIZONTAL_ALIGNMENT_LEFT)
		temp_label.text = str(temp_defs[temp_type]["desc"])
		col.add_child(temp_label)

	if _telegraphed_cells().has(pos):
		var danger_label := _make_label(11, Color("#ff9a7a"), HORIZONTAL_ALIGNMENT_LEFT)
		danger_label.text = "敵の攻撃予告あり"
		col.add_child(danger_label)

	add_child(panel)
	cell_info_panel = panel

	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var target_pos: Vector2 = anchor_button.global_position + Vector2(anchor_button.size.x * 0.5 - panel.size.x * 0.5, -panel.size.y - 10.0)
	target_pos.x = clamp(target_pos.x, 4.0, get_viewport_rect().size.x - panel.size.x - 4.0)
	target_pos.y = max(target_pos.y, 4.0)
	panel.position = target_pos

	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(Callable(self, "_clear_cell_info_panel").bind(panel))

func _clear_cell_info_panel(panel: Control) -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	if cell_info_panel == panel:
		cell_info_panel = null

func _advance_player() -> void:
	var messages := []
	while steps_left > 0:
		player_step = _normalize_step(player_step + 1)
		player_pos = _pos_for_step(player_step)
		route_path.append(player_pos)
		turn_visited[player_pos] = true
		steps_left -= 1
		var pass_message := _resolve_pass_tile(player_pos)
		if pass_message != "":
			messages.append(pass_message)
		log_label.text = " ".join(messages)
		_refresh_all()
		await _animate_player_step(0.16)

		if player_hp <= 0:
			await _flush_turn_ledger()
			_show_game_over("移動中に倒れました。")
			return
		if not _any_enemy_alive():
			await _flush_turn_ledger()
			_show_reward()
			return

	if player_hp <= 0:
		await _flush_turn_ledger()
		_show_game_over("移動中に倒れました。")
		return
	if not _any_enemy_alive():
		await _flush_turn_ledger()
		_show_reward()
		return

	messages.append(_resolve_stop_tile(player_pos))
	actions_left -= 1
	if player_hp <= 0:
		await _flush_turn_ledger()
		_show_game_over("移動後に倒れました。")
		return
	if not _any_enemy_alive():
		await _flush_turn_ledger()
		_show_reward()
		return
	if actions_left <= 0 or hand.is_empty():
		state = "player"
		log_label.text = " ".join(messages) + " 敵の行動。"
		_refresh_all()
		await get_tree().create_timer(0.25).timeout
		await _flush_turn_ledger()
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
		var dmg := _combo_damage(2)
		if _strike_lowest(dmg):
			messages.append("斬撃路を通過。%dダメージ。" % dmg)
	elif tile_type == "guard":
		_gain_shield(1)
		messages.append("防御路を通過。盾+1。")
	elif tile_type == "fire":
		var dmg := _combo_damage(1)
		if _strike_all(dmg):
			messages.append("火走りを通過。全敵に%dダメージ。" % dmg)
	elif tile_type == "heal":
		_heal(1)
		messages.append("癒し道を通過。HP+1。")
	elif tile_type == "bow":
		var dmg := _combo_damage(1)
		if _strike_lowest(dmg):
			messages.append("射撃台を通過。%dダメージ。" % dmg)
	elif tile_type == "trap":
		var dmg := _combo_damage(2)
		if _strike_highest(dmg):
			messages.append("罠道を通過。最もHPが高い敵に%dダメージ。" % dmg)
	elif tile_type == "warp":
		steps_left += 1
		messages.append("跳躍路を通過。追加で1歩。")
	elif tile_type == "shock":
		var dmg := _combo_damage(1)
		if _strike_all(dmg):
			messages.append("雷線を通過。全敵に%dダメージ。" % dmg)
	elif tile_type == "focus":
		_gain_shield(1)
		route_power += 1
		messages.append("集中路を通過。盾+1、以降の攻撃+%d。" % route_power)
	return " ".join(messages)

func _resolve_stop_tile(pos: Vector2i) -> String:
	_flash_player_stop()
	var tile_type: String = str(permanent_board[pos.y][pos.x])
	if tile_type == "empty":
		_gain_shield(1)
		return "道で停止。盾+1。"
	if tile_type == "slash":
		var dmg := _combo_damage(4)
		if _strike_lowest(dmg):
			return "斬撃路で停止。%dダメージ。" % dmg
		return "斬撃路で停止。敵はいない。"
	if tile_type == "guard":
		_gain_shield(3)
		return "防御路で停止。盾+3。"
	if tile_type == "fire":
		var dmg := _combo_damage(3)
		if _strike_lowest(dmg):
			return "火走りで停止。%dダメージ。" % dmg
		return "火走りで停止。敵はいない。"
	if tile_type == "heal":
		_heal(3)
		return "癒し道で停止。HP+3。"
	if tile_type == "bow":
		var dmg := _combo_damage(3)
		if _strike_lowest(dmg):
			return "射撃台で停止。%dダメージ。" % dmg
		return "射撃台で停止。敵はいない。"
	if tile_type == "trap":
		var dmg := _combo_damage(4)
		if _strike_highest(dmg):
			return "罠道で停止。最もHPが高い敵に%dダメージ。" % dmg
		return "罠道で停止。敵はいない。"
	if tile_type == "warp":
		actions_left += 1
		return "跳躍路で停止。追加行動+1。"
	if tile_type == "shock":
		var dmg := _combo_damage(2)
		if _strike_all(dmg):
			return "雷線で停止。全敵に%dダメージ。" % dmg
		return "雷線で停止。敵はいない。"
	if tile_type == "focus":
		_draw_to_hand()
		return "集中路で停止。ダイスを補充。"
	return ""

# Attack tiles deal this much: a flat base, plus every attack tile already
# hit this move (route_hits) and any temporary bonus from 集中路 this move
# (route_power) — chaining several attack tiles in one big roll compounds.
func _combo_damage(base: int) -> int:
	return base + route_power + route_hits

func _strike_lowest(amount: int) -> bool:
	var target := _lowest_hp_enemy()
	if target.is_empty():
		return false
	_damage_enemy(target, amount)
	route_hits += 1
	return true

func _strike_highest(amount: int) -> bool:
	var target := _highest_hp_enemy()
	if target.is_empty():
		return false
	_damage_enemy(target, amount)
	route_hits += 1
	return true

func _strike_all(amount: int) -> bool:
	var hit_any := false
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			_damage_enemy(enemy, amount)
			hit_any = true
	if hit_any:
		route_hits += 1
	return hit_any

# Resolves every enemy's already-telegraphed attack: guaranteed-hit enemies
# always land; positional ones only land if the player's route this *turn*
# (every cell passed or stopped on, across every die rolled) touched one of
# the cells that enemy telegraphed at the start of the turn.
func _enemy_turn() -> void:
	state = "enemy"
	var messages := []
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var hit := false
		if str(enemy.get("attack_kind", "positional")) == "guaranteed":
			hit = true
		else:
			var cells: Array = enemy.get("telegraph_cells", [])
			for c in cells:
				if turn_visited.has(c):
					hit = true
					break
		if hit:
			_take_damage(int(enemy["damage"]))
			messages.append("%sの攻撃、%dダメージ。" % [enemy["type"], int(enemy["damage"])])
		else:
			messages.append("%sの攻撃を回避。" % enemy["type"])

	if encounter >= 3 and not enemies.is_empty() and rng.randi_range(0, 100) < 45:
		var p := _random_empty_cell()
		if p.x >= 0:
			temp_board[p.y][p.x] = "hazard"
			messages.append("毒沼が広がった。")

	_cleanup_dead_enemies()
	if player_hp <= 0:
		_show_game_over("敵の攻撃で倒れました。")
		return
	if enemies.is_empty():
		_show_reward()
		return
	for enemy in enemies:
		_generate_telegraph(enemy)
	_start_player_turn(" ".join(messages))

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
	_clear_children(enemy_status_box)
	log_label.text = "勝利。報酬マスを1つ選んで、永続ボードに配置してください。"

	var options := reward_pool.duplicate(true)
	options.shuffle()
	for i in range(3):
		var reward: Dictionary = options[i]
		var reward_type := str(reward["type"])
		var tile: Dictionary = tile_defs[reward_type]
		var b := Button.new()
		b.text = ""
		b.custom_minimum_size = Vector2(0, 88)
		b.pressed.connect(Callable(self, "_on_reward_selected").bind(reward_type, "%sマス" % tile["name"]))
		_apply_button_color(b, tile["color"], Color("#f5d86a"), 2)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 12)
		row.offset_left = 14
		row.offset_right = -14
		b.add_child(row)

		var icon := IconGlyph.new()
		icon.kind = reward_type
		icon.glyph_color = Color(1, 1, 1, 0.92)
		icon.custom_minimum_size = Vector2(30, 30)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)

		var col := VBoxContainer.new()
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)

		var title_label := _make_label(14, Color("#f5f1e8"), HORIZONTAL_ALIGNMENT_LEFT)
		title_label.text = "[%s] %sマス" % [tile["kind"], tile["name"]]
		col.add_child(title_label)

		var desc_label := _make_label(11, Color("#e6dfc8"), HORIZONTAL_ALIGNMENT_LEFT)
		desc_label.text = "%s / %s" % [tile["pass"], tile["stop"]]
		col.add_child(desc_label)

		reward_box.add_child(b)
	_refresh_board()

func _on_reward_selected(tile_type: String, tile_name: String) -> void:
	pending_reward_type = tile_type
	pending_reward_name = tile_name
	state = "reward_place"
	_clear_children(reward_box)
	log_label.text = "%s を置くマスを選んでください。始点以外なら上書きできます。" % tile_name
	_refresh_all()

func _show_victory() -> void:
	state = "victory"
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "踏破成功"
	instruction_label.text = "踏破成功"
	route_label.text = "すごろく式ルート戦闘のプロトタイプはここまでです。"
	stats_label.text = "%s は最終戦を突破しました。" % hero_name
	_clear_children(enemy_status_box)
	log_label.text = "別キャラや別配置で再挑戦できます。"
	end_turn_button.visible = false
	restart_button.visible = true
	_refresh_board()
	_play_result_flourish(Color(1.0, 0.85, 0.45, 0.5))

func _show_game_over(reason: String) -> void:
	state = "game_over"
	_clear_children(dice_box)
	_clear_children(reward_box)
	header_label.text = "ゲームオーバー"
	instruction_label.text = "ゲームオーバー"
	route_label.text = "次は敵を通るルート、攻撃路、防御路の配置を変えて挑戦してください。"
	stats_label.text = reason
	_clear_children(enemy_status_box)
	log_label.text = "ボード構築とダイス選択を変えて再挑戦できます。"
	end_turn_button.visible = false
	restart_button.visible = true
	_refresh_board()
	_play_result_flourish(Color(0.16, 0.05, 0.05, 0.6))

# A full-screen flash that dissolves away, plus a bounce on the header
# text — the win/lose moment used to just be a couple of lines of text
# swapped in place, no punctuation at all.
func _play_result_flourish(flash_color: Color) -> void:
	var overlay := ColorRect.new()
	overlay.color = flash_color
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	add_child(overlay)
	var fade_tween := create_tween()
	fade_tween.tween_property(overlay, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_tween.tween_callback(overlay.queue_free)

	if header_label != null and header_label.size.length() > 0.0:
		header_label.pivot_offset = header_label.size / 2.0
		header_label.scale = Vector2(1.6, 1.6)
		var header_tween := create_tween()
		header_tween.tween_property(header_label, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _on_end_turn_pressed() -> void:
	if state == "moving":
		return
	if state == "player":
		log_label.text = "行動を終えました。敵の行動。"
		await _flush_turn_ledger()
		_enemy_turn()

func _can_step_to(pos: Vector2i) -> bool:
	return false

func _can_place_reward(pos: Vector2i) -> bool:
	if not _inside(pos):
		return false
	if not ring_index_map.has(pos):
		return false
	if pos == _start_pos():
		return false
	if temp_board[pos.y][pos.x] == "block":
		return false
	return true

# Attack tiles auto-target: "slash"/"bow" go for the kill on whatever's
# already weakest, "trap" goes after the toughest target instead.
func _lowest_hp_enemy() -> Dictionary:
	var best := {}
	var best_hp := 2147483647
	for enemy in enemies:
		var hp := int(enemy["hp"])
		if hp > 0 and hp < best_hp:
			best = enemy
			best_hp = hp
	return best

func _highest_hp_enemy() -> Dictionary:
	var best := {}
	var best_hp := -1
	for enemy in enemies:
		var hp := int(enemy["hp"])
		if hp > 0 and hp > best_hp:
			best = enemy
			best_hp = hp
	return best

func _random_empty_cell() -> Vector2i:
	var choices := []
	for p in ring_cells:
		if p == player_pos:
			continue
		if temp_board[p.y][p.x] != "none":
			continue
		choices.append(p)
	if choices.is_empty():
		return Vector2i(-1, -1)
	return choices[rng.randi_range(0, choices.size() - 1)]

func _take_damage(amount: int) -> void:
	var blocked: int = min(player_shield, amount)
	player_shield -= blocked
	var hp_loss := amount - blocked
	player_hp -= hp_loss
	if suppress_stat_reveal:
		if hp_loss > 0:
			_queue_ledger_entry("self_dmg", hp_loss)
		return
	if hp_loss > 0:
		_spawn_floating_text(player_pos, "-%d" % hp_loss, Color("#ff9a86"))
		_punch_control(gauges_box, 1.08)
	elif blocked > 0:
		_spawn_floating_text(player_pos, "防", Color("#8fb6e8"))
		_punch_control(gauges_box, 1.04)

func _heal(amount: int) -> void:
	var gained: int = min(player_max_hp, player_hp + amount) - player_hp
	player_hp = min(player_max_hp, player_hp + amount)
	if gained <= 0:
		return
	if suppress_stat_reveal:
		_queue_ledger_entry("heal", gained)
		return
	_spawn_floating_text(player_pos, "+%d" % gained, Color("#9fe0b6"))
	_punch_control(gauges_box, 1.05)

func _gain_shield(amount: int) -> void:
	if amount <= 0:
		return
	player_shield += amount
	if suppress_stat_reveal:
		_queue_ledger_entry("shield", amount)
		return
	_spawn_floating_text(player_pos, "+%d 盾" % amount, Color("#9fc3ff"))
	_punch_control(gauges_box, 1.04)

# All enemy HP loss should route through here so the hit always gets a
# number and a punch, wherever the damage came from (route attacks, tile
# effects, traps). Enemies live in the status panel now, not the board, so
# the feedback plays there instead of at a cell.
func _damage_enemy(enemy: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	enemy["hp"] = int(enemy["hp"]) - amount
	if suppress_stat_reveal:
		_queue_ledger_entry("enemy_dmg", amount, int(enemy.get("uid", -1)))
		return
	_spawn_enemy_panel_popup("-%d" % amount, Color("#ffb199"))
	_flash_enemy_panel()

# Tile effects during the player's own move don't touch the bars right
# away — they add into a running total here instead, one chip per kind
# (and per enemy, for damage dealt), so the turn's numbers accumulate in
# place rather than piling up as a new chip per tile. See
# _flush_turn_ledger for where these get cashed in.
func _queue_ledger_entry(kind: String, amount: int, uid: int = -1) -> void:
	var key: String = "%s:%d" % [kind, uid] if kind == "enemy_dmg" else kind
	if ledger_chips.has(key):
		var entry: Dictionary = ledger_chips[key]
		var total: int = int(entry["total"]) + amount
		entry["total"] = total
		var label: Label = entry["label"]
		label.text = _ledger_chip_text(kind, total)
		var chip: Control = entry["panel"]
		_punch_control(chip, 1.22, 0.05, 0.16)
	else:
		var made := _spawn_ledger_chip(kind, amount)
		ledger_chips[key] = {"panel": made["panel"], "label": made["label"], "total": amount}

func _ledger_chip_text(kind: String, amount: int) -> String:
	return ("+%d" % amount) if kind in ["heal", "shield"] else ("-%d" % amount)

func _ledger_chip_style(kind: String) -> Dictionary:
	match kind:
		"self_dmg":
			return {"icon": "skull", "color": Color("#ff9a86")}
		"heal":
			return {"icon": "heal", "color": Color("#9fe0b6")}
		"shield":
			return {"icon": "guard", "color": Color("#9fc3ff")}
	return {"icon": "slash", "color": Color("#ffb199")}

func _spawn_ledger_chip(kind: String, amount: int) -> Dictionary:
	if ledger_box == null or not is_instance_valid(ledger_box):
		return {"panel": null, "label": null}
	var style := _ledger_chip_style(kind)
	var icon_kind: String = style["icon"]
	var color: Color = style["color"]
	var text := _ledger_chip_text(kind, amount)

	# PanelContainer (not a plain Panel) so the chip auto-sizes to its
	# content instead of collapsing to zero size and overlapping whatever
	# sits next to it in the flow.
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.6)
	box.border_color = color
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	box.content_margin_left = 6.0
	box.content_margin_right = 7.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	chip.add_child(row)

	var icon := IconGlyph.new()
	icon.kind = icon_kind
	icon.glyph_color = color
	icon.custom_minimum_size = Vector2(13, 13)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var label := _make_label(12, color, HORIZONTAL_ALIGNMENT_LEFT, true)
	label.text = text
	row.add_child(label)

	ledger_box.add_child(chip)
	chip.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(chip, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return {"panel": chip, "label": label}

func _cleanup_dead_enemies() -> void:
	var survivors := []
	var any_died := false
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			survivors.append(enemy)
		else:
			any_died = true
	enemies = survivors
	if any_died:
		_spawn_enemy_panel_popup("撃破!", Color("#f6dfa6"))
		_spawn_death_burst_at_panel()

# enemies isn't pruned of the dead until _flush_turn_ledger runs (a killed
# enemy keeps its row, frozen at its last-shown HP, until the turn's reveal
# plays out) — so "any enemies left" during the player's move has to mean
# "any real hp above 0", not "array not empty".
func _any_enemy_alive() -> bool:
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			return true
	return false

# The moment a player turn actually ends: every tile effect queued this
# turn (ledger_chips) gets revealed at once — the HP/shield bars and any
# hit enemies' bars animate from what they were still showing to their real
# current value, the ledger chips that prompted it clear out, and only then
# do we prune anything that died along the way. Call this before leaving
# the player's turn, whichever way it ends (button, actions spent, a fatal
# or lethal tile).
func _flush_turn_ledger() -> void:
	suppress_stat_reveal = false
	var had_entries: bool = not ledger_chips.is_empty()
	ledger_chips = {}

	if had_entries:
		await get_tree().create_timer(0.25).timeout
		_punch_control(gauges_box, 1.08)
		_flash_enemy_panel()
		var fade_tween := create_tween()
		fade_tween.set_parallel(true)
		for chip in ledger_box.get_children():
			fade_tween.tween_property(chip, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_refresh_header()
	_refresh_board()

	if had_entries:
		await get_tree().create_timer(0.6).timeout

	_clear_children(ledger_box)
	_cleanup_dead_enemies()

# A number that drifts up and fades out at a board cell — the only
# feedback HP changes used to get was the gauge silently jumping.
# A number that pops in big, drifts up, and fades — deliberately louder
# than a UI label: this is the primary way a hit or a heal registers, so
# it has to win against everything else changing on screen at once.
func _spawn_floating_text(pos: Vector2i, text: String, color: Color) -> void:
	if board_grid == null or not is_instance_valid(board_grid):
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, true)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	var center: Vector2 = _board_cell_center(pos)
	var base_pos: Vector2 = center + Vector2(-20, -_board_token_size() * 1.1)
	label.position = base_pos
	label.z_index = 25
	label.scale = Vector2(0.3, 0.3)
	board_grid.add_child(label)
	label.pivot_offset = label.size / 2.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_pos.y - 46.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

# Same idea as _spawn_floating_text, but for the enemy status panel (no
# board cell to anchor to since enemies don't occupy one).
func _spawn_enemy_panel_popup(text: String, color: Color) -> void:
	if enemy_status_box == null or not is_instance_valid(enemy_status_box):
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, true)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.z_index = 25
	add_child(label)
	label.pivot_offset = label.size / 2.0
	var base_pos: Vector2 = enemy_status_box.global_position + Vector2(enemy_status_box.size.x * 0.5 - label.size.x * 0.5, -label.size.y - 6.0 + float(rng.randi_range(-3, 3)))
	label.position = base_pos
	label.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_pos.y - 34.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

# A quick scale punch on the whole panel, so a hit registers even before
# the reader parses the popup number.
func _flash_enemy_panel() -> void:
	if enemy_status_box == null or not is_instance_valid(enemy_status_box):
		return
	enemy_status_box.pivot_offset = enemy_status_box.size / 2.0
	var tween := create_tween()
	tween.tween_property(enemy_status_box, "scale", Vector2(1.03, 1.03), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_status_box, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_death_burst_at_panel() -> void:
	if enemy_status_box == null or not is_instance_valid(enemy_status_box):
		return
	var burst := BurstEffect.new()
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.center = enemy_status_box.global_position + Vector2(16.0, enemy_status_box.size.y * 0.5)
	burst.token = 44.0
	burst.z_index = 21
	add_child(burst)
	var tween := create_tween()
	tween.tween_property(burst, "progress", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(burst.queue_free)

func _make_empty_board(value: String) -> Array:
	var board := []
	for y in range(BOARD_H):
		var row := []
		for x in range(BOARD_W):
			row.append(value)
		board.append(row)
	return board

# Builds the ring: 12 perimeter cells (a 4x4 grid), one-way. This is the
# player's whole board — enemies live off-board in enemy_status_box and
# never occupy a cell themselves.
func _build_track_graph() -> void:
	ring_cells = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3),
		Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3),
		Vector2i(0, 2), Vector2i(0, 1),
	]
	ring_index_map = {}
	ring_forward = {}
	for i in range(ring_cells.size()):
		ring_index_map[ring_cells[i]] = i
		ring_forward[ring_cells[i]] = ring_cells[(i + 1) % ring_cells.size()]

func _normalize_step(step: int) -> int:
	if ring_cells.is_empty():
		return 0
	var size := ring_cells.size()
	return ((step % size) + size) % size

func _pos_for_step(step: int) -> Vector2i:
	if ring_cells.is_empty():
		return Vector2i.ZERO
	return ring_cells[_normalize_step(step)]

func _track_index(pos: Vector2i) -> int:
	return int(ring_index_map.get(pos, 0))

# How many steps ahead pos is on the ring, within the 6-cell preview window.
func _steps_ahead(pos: Vector2i) -> int:
	var idx := preview_path.find(pos)
	if idx == -1:
		return -1
	return idx + 1

func _start_pos() -> Vector2i:
	if ring_cells.is_empty():
		return Vector2i.ZERO
	return ring_cells[0]

# The next 6 cells ahead of the player on the ring. Drives both the
# lookahead ribbon and the board's "next" glow.
func _rebuild_preview_path() -> void:
	preview_path = []
	if state != "player":
		return
	for i in range(1, 7):
		preview_path.append(_pos_for_step(player_step + i))

func _segment_is_recent(a: Vector2i, b: Vector2i) -> bool:
	if route_path.size() < 2:
		return false
	for i in range(route_path.size() - 1):
		if (route_path[i] == a and route_path[i + 1] == b) or (route_path[i] == b and route_path[i + 1] == a):
			return true
	return false

func _segment_is_next(a: Vector2i, b: Vector2i) -> bool:
	if state != "player":
		return false
	if not preview_path.is_empty():
		var first: Vector2i = preview_path[0]
		if (a == player_pos and b == first) or (b == player_pos and a == first):
			return true
	for i in range(preview_path.size() - 1):
		if (preview_path[i] == a and preview_path[i + 1] == b) or (preview_path[i] == b and preview_path[i + 1] == a):
			return true
	return false

func _idx(x: int, y: int) -> int:
	return y * BOARD_W + x

func _inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_W and pos.y >= 0 and pos.y < BOARD_H

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
			return Color("#a85940")
		"steel":
			return Color("#55708f")
		"heavy":
			return Color("#7d746c")
		"swift":
			return Color("#4c8f83")
		"trick":
			return Color("#7d5a93")
		"lucky":
			return Color("#998a4d")
		"arcane":
			return Color("#6b5cae")
		"focus":
			return Color("#728a65")
	return Color("#4a5570")

func _hero_color(key: String) -> Color:
	match key:
		"knight":
			return Color("#3f5c86")
		"mage":
			return Color("#634590")
		"rogue":
			return Color("#5f7a4e")
	return Color("#3c4760")

func _cell_tooltip(pos: Vector2i, perm_type: String, temp_type: String) -> String:
	var lines := []
	if ring_index_map.has(pos):
		lines.append("コース%02d" % int(ring_index_map[pos]))
	var ahead := _steps_ahead(pos)
	if ahead > 0:
		lines.append("現在地から%dマス先" % ahead)
	if _telegraphed_cells().has(pos):
		lines.append("敵の攻撃予告: このマスを通過/停止すると被弾します")
	if pos == player_pos:
		lines.append("自分の現在地")
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

func _apply_font(control: Control, heavy: bool = false) -> void:
	var font: Font = ui_font_heavy if heavy else ui_font
	if font != null:
		control.add_theme_font_override("font", font)
