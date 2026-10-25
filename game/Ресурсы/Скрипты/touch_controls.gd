extends CanvasLayer
## Сенсорное управление: плавающий джойстик (левая половина экрана),
## поворот камеры свайпом (правая половина) и кнопки действий.
## Игрок создаёт этот узел сам на сенсорных устройствах.
## Кнопки нажимают обычные действия (jump, run, climb, elbow),
## поэтому клавиатура и сенсор работают одним и тем же кодом.

signal look_delta(relative: Vector2)

## Показывать интерфейс и на ПК (для тестов; вместе с настройкой проекта
## input_devices/pointing/emulate_touch_from_mouse).
@export var show_on_desktop := false
@export var stick_radius := 120.0
@export var stick_deadzone := 0.12
@export var ui_opacity := 0.55

## Вектор движения (x — вправо, y — назад), длина 0..1.
var move_vector := Vector2.ZERO
var stick_active := false

var _canvas: Control
var _move_index := -1
var _look_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _buttons: Array[Dictionary] = []


func _ready() -> void:
	layer = 10
	add_to_group(&"touch_controls")
	visible = DisplayServer.is_touchscreen_available() or show_on_desktop

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ui)

	_buttons = [
		{"action": &"jump", "label": "JUMP", "offset": Vector2(-140, -150), "radius": 72.0, "index": -1},
		{"action": &"run", "label": "RUN", "offset": Vector2(-310, -96), "radius": 50.0, "index": -1},
		{"action": &"climb", "label": "E", "offset": Vector2(-120, -310), "radius": 46.0, "index": -1},
		{"action": &"elbow", "label": "F", "offset": Vector2(-270, -250), "radius": 46.0, "index": -1},
		{"action": &"toggle_view", "label": "VIEW", "offset": Vector2(-70, -450), "radius": 40.0, "index": -1},
	]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_touch_down(touch.index, touch.position)
		else:
			_on_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_touch_drag(drag.index, drag.position, drag.relative)


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _button_center(button: Dictionary) -> Vector2:
	return _viewport_size() + (button["offset"] as Vector2)


func _on_touch_down(index: int, pos: Vector2) -> void:
	# 1. Кнопки имеют приоритет.
	for button in _buttons:
		if int(button["index"]) != -1:
			continue
		var reach := float(button["radius"]) * 1.25
		if pos.distance_to(_button_center(button)) <= reach:
			button["index"] = index
			if InputMap.has_action(button["action"]):
				Input.action_press(button["action"])
			_canvas.queue_redraw()
			return
	# 2. Левая половина — джойстик, правая — камера.
	if pos.x < _viewport_size().x * 0.5:
		if _move_index == -1:
			_move_index = index
			_stick_origin = pos
			_stick_pos = pos
			stick_active = true
	elif _look_index == -1:
		_look_index = index
	_canvas.queue_redraw()


func _on_touch_up(index: int) -> void:
	for button in _buttons:
		if int(button["index"]) == index:
			button["index"] = -1
			if InputMap.has_action(button["action"]):
				Input.action_release(button["action"])
	if index == _move_index:
		_move_index = -1
		stick_active = false
		move_vector = Vector2.ZERO
	if index == _look_index:
		_look_index = -1
	_canvas.queue_redraw()


func _on_touch_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _move_index:
		var offset := pos - _stick_origin
		if offset.length() > stick_radius:
			# Плавающий джойстик: центр подтягивается за пальцем.
			_stick_origin = pos - offset.normalized() * stick_radius
			offset = pos - _stick_origin
		_stick_pos = pos
		var v := offset / stick_radius
		var length := v.length()
		if length < stick_deadzone:
			move_vector = Vector2.ZERO
		else:
			move_vector = v.normalized() * clampf(inverse_lerp(stick_deadzone, 1.0, length), 0.0, 1.0)
		_canvas.queue_redraw()
	elif index == _look_index:
		look_delta.emit(relative)


func _release_all() -> void:
	for button in _buttons:
		if int(button["index"]) != -1:
			button["index"] = -1
			Input.action_release(button["action"])
	_move_index = -1
	_look_index = -1
	stick_active = false
	move_vector = Vector2.ZERO
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_ui() -> void:
	var line_color := Color(1, 1, 1, ui_opacity)
	if _move_index != -1:
		_canvas.draw_arc(_stick_origin, stick_radius, 0.0, TAU, 48, line_color, 3.0, true)
		_canvas.draw_circle(_stick_pos, stick_radius * 0.38, Color(1, 1, 1, ui_opacity * 0.9))
	else:
		var size := _viewport_size()
		var hint := Vector2(stick_radius + 60.0, size.y - stick_radius - 60.0)
		_canvas.draw_arc(hint, stick_radius, 0.0, TAU, 48, Color(1, 1, 1, ui_opacity * 0.35), 3.0, true)

	var font := ThemeDB.fallback_font
	var font_size := 22
	for button in _buttons:
		var center := _button_center(button)
		var radius := float(button["radius"])
		var pressed := int(button["index"]) != -1
		var fill := Color(1, 1, 1, 0.35 if pressed else 0.12)
		_canvas.draw_circle(center, radius, fill)
		_canvas.draw_arc(center, radius, 0.0, TAU, 40, line_color, 3.0, true)
		var label := String(button["label"])
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		_canvas.draw_string(font, center + Vector2(-text_size.x * 0.5, font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, line_color)
