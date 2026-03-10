# game_over_overlay.gd
# Меню конца игры. Popup = модальное окно, ввод под ним не проходит (панель руды, индикатор и т.д.).
extends Popup

var _overlay: ColorRect
var _center: CenterContainer
var _vbox: VBoxContainer
var _title: Label
var _score_label: Label
var _kills_label: Label
var _btn_restart: Button
var _btn_menu: Button

const _btn_w := 250
const _btn_h := 50

func _ready():
	var vs = Vector2(Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT)
	set_size(vs)
	position = Vector2.ZERO
	exclusive = true
	unfocusable = false

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.1, 0.1, 0.12, 1.0)  # как в главном меню (menu.gd)
	add_child(_overlay)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 16)
	_vbox.custom_minimum_size = Vector2(_btn_w, 0)
	_center.add_child(_vbox)

	_title = Label.new()
	_title.text = "Игра окончена"
	_title.add_theme_font_size_override("font_size", 32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_title)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 18)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_score_label)

	_kills_label = Label.new()
	_kills_label.add_theme_font_size_override("font_size", 18)
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_kills_label)

	_btn_restart = Button.new()
	_btn_restart.text = "Начать заново"
	_btn_restart.custom_minimum_size = Vector2(_btn_w, _btn_h)
	_btn_restart.pressed.connect(_on_restart)
	_vbox.add_child(_btn_restart)

	_btn_menu = Button.new()
	_btn_menu.text = "В меню"
	_btn_menu.custom_minimum_size = Vector2(_btn_w, _btn_h)
	_btn_menu.pressed.connect(_on_menu)
	_vbox.add_child(_btn_menu)


func show_end_screen():
	if not GameManager or not GameManager.ecs:
		return
	var gs = GameManager.ecs.game_state
	var xp_total = 0
	for pid in GameManager.ecs.player_states.keys():
		var ps = GameManager.ecs.player_states[pid]
		xp_total += ps.get("current_xp", 0)
		var lv = ps.get("level", 1)
		if lv > 1:
			xp_total += (lv - 1) * 100
	var kills = int(gs.get("total_enemies_killed", 0))
	_score_label.text = "Вы набрали %d очков" % xp_total
	_kills_label.text = "Убито врагов: %d" % kills
	var vs = Vector2(Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT)
	set_size(vs)
	_overlay.set_size(vs)
	_center.set_size(vs)
	if is_inside_tree():
		var vp_size = get_viewport().get_visible_rect().size
		var pos = (vp_size - vs) * 0.5
		popup(Rect2i(int(pos.x), int(pos.y), int(vs.x), int(vs.y)))


func _on_restart():
	hide()
	call_deferred("_do_restart")


func _on_menu():
	hide()
	call_deferred("_do_menu")


func _do_restart():
	GameManager.request_restart_game()


func _do_menu():
	GameManager.request_exit_to_menu()
