extends Node3D
## Простой NPC: ставит модель на землю/рельеф, доигрывает встроенную анимацию
## модели если она есть (ищет по имени idle/breath/stand), иначе — лёгкое
## процедурное "дыхание" и медленные случайные повороты, чтобы фигура не
## выглядела мёртвым манекеном даже без своих анимаций ходьбы.
## У новой модели (Сатоко Кирагая) отдельных файлов анимации нет — только
## сама риггед-модель, поэтому скрипт не полагается на внешние клипы.

@export var character: PackedScene
@export var npc_name := "NPC"
## Поворачиваться в сторону игрока, когда тот подходит ближе этого расстояния (0 — выключено).
@export var look_at_player_range := 4.0
@export var turn_speed := 3.0
@export var idle_bob_amplitude := 0.015
@export var idle_bob_speed := 1.4
## Случайные повороты, когда нет анимации (имитация "живости").
@export var idle_turn_min := 3.0
@export var idle_turn_max := 7.0

var _model: Node3D
var _bob_pivot: Node3D
var _animation_player: AnimationPlayer
var _player: Node3D
var _idle_timer := 0.0
var _idle_threshold := 4.0
var _target_yaw := 0.0


func _ready() -> void:
	add_to_group(&"npc")
	if character == null:
		push_warning("Npc '%s': не задана модель персонажа." % name)
		return

	var terrain := get_tree().get_first_node_in_group(&"terrain")
	if terrain != null:
		position.y += terrain.sample_height(global_position.x, global_position.z)

	var instance := character.instantiate()
	_model = instance as Node3D
	if _model == null:
		push_warning("Npc '%s': корень модели не Node3D." % name)
		instance.free()
		return

	_bob_pivot = Node3D.new()
	_bob_pivot.name = "Bob"
	add_child(_bob_pivot)
	_bob_pivot.add_child(_model)
	_target_yaw = rotation.y

	_snap_to_ground()
	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play_idle_if_available()

	_player = get_tree().get_first_node_in_group(&"player")
	if _player == null:
		# В сцене игрок не состоит в группе — ищем по известному пути как запасной вариант.
		_player = get_tree().current_scene.find_child("Player", true, false) as Node3D

	_reset_idle_timer()


## Модель может быть экспортирована с произвольным пивотом (не всегда ровно
## по ногам), поэтому дополнительно подравниваем по нижней точке меша.
func _snap_to_ground() -> void:
	var aabb := AABB()
	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if has_aabb:
			aabb = aabb.merge(box)
		else:
			aabb = box
			has_aabb = true
	if has_aabb:
		_model.position.y -= aabb.position.y - global_position.y


func _play_idle_if_available() -> void:
	if _animation_player == null:
		return
	var keywords := ["idle", "breath", "stand", "wait"]
	var chosen: StringName = &""
	for animation_name in _animation_player.get_animation_list():
		if animation_name == &"RESET":
			continue
		if chosen == &"":
			chosen = animation_name
		var lower := String(animation_name).to_lower()
		for keyword in keywords:
			if lower.contains(keyword):
				chosen = animation_name
				break
	if chosen == &"":
		return
	var clip := _animation_player.get_animation(chosen)
	if clip != null:
		clip.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(chosen)


func _process(delta: float) -> void:
	if _bob_pivot == null:
		return
	_bob_pivot.position.y = sin(Time.get_ticks_msec() * 0.001 * idle_bob_speed) * idle_bob_amplitude

	if look_at_player_range > 0.0 and _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() <= look_at_player_range and to_player.length_squared() > 0.01:
			_target_yaw = atan2(to_player.x, to_player.z) + PI
	elif _animation_player == null or not _animation_player.is_playing():
		_idle_timer += delta
		if _idle_timer >= _idle_threshold:
			_reset_idle_timer()
			_target_yaw += randf_range(-1.2, 1.2)

	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-turn_speed * delta))


func _reset_idle_timer() -> void:
	_idle_timer = 0.0
	_idle_threshold = randf_range(idle_turn_min, idle_turn_max)
