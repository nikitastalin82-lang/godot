extends Node3D
## NPC: размещает модель на земле, запускает доступную idle-анимацию
## и плавно поворачивается к игроку.

@export var character: PackedScene
@export var npc_name := "NPC"
@export var look_at_player_range := 4.0
@export var turn_speed := 3.0
@export var idle_bob_amplitude := 0.015
@export var idle_bob_speed := 1.4
@export var idle_turn_min := 3.0
@export var idle_turn_max := 7.0
@export var external_idle_animation: PackedScene = preload("res://анимки/стойка.fbx")

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
	if _player == null and get_tree().current_scene != null:
		_player = get_tree().current_scene.find_child("Player", true, false) as Node3D
	_reset_idle_timer()


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
		push_warning("Npc '%s': у модели нет AnimationPlayer." % npc_name)
		return

	var chosen: StringName = &""
	for animation_name in _animation_player.get_animation_list():
		if animation_name == &"RESET":
			continue
		var lower := String(animation_name).to_lower()
		if lower.contains("idle") or lower.contains("stand") or lower.contains("breath") or lower.contains("wait"):
			chosen = animation_name
			break
	if chosen != &"":
		var clip := _animation_player.get_animation(chosen)
		clip.loop_mode = Animation.LOOP_LINEAR
		_animation_player.play(chosen)
		return

	if _copy_external_idle():
		return
	push_warning("Npc '%s': idle-анимация не найдена или не удалось сопоставить кости." % npc_name)


func _copy_external_idle() -> bool:
	if external_idle_animation == null:
		return false
	var source := external_idle_animation.instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var target_skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if source_player == null or source_skeleton == null or target_skeleton == null:
		source.free()
		push_warning("Npc '%s': в стойка.fbx или модели не найден AnimationPlayer/Skeleton3D." % npc_name)
		return false

	var source_clip: Animation
	for animation_name in source_player.get_animation_list():
		if animation_name != &"RESET":
			source_clip = source_player.get_animation(animation_name)
			break
	if source_clip == null:
		source.free()
		return false

	var target_clip := source_clip.duplicate() as Animation
	var mapped_tracks := 0
	var target_path := _animation_player.get_path_to(target_skeleton)
	for track_index in range(target_clip.get_track_count()):
		var track_path := String(target_clip.track_get_path(track_index))
		var separator := track_path.rfind(":")
		if separator < 0:
			continue
		var bone_name := track_path.substr(separator + 1)
		if target_skeleton.find_bone(bone_name) < 0:
			continue
		target_clip.track_set_path(track_index, NodePath(String(target_path) + ":" + bone_name))
		mapped_tracks += 1

	source.free()
	if mapped_tracks < 8:
		push_warning("Npc '%s': совпало слишком мало костей для переноса idle (%d)." % [npc_name, mapped_tracks])
		return false

	var library := _animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library(&"", library)
	var clip_name := &"external_idle"
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	target_clip.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(clip_name, target_clip)
	_animation_player.play(clip_name)
	print("Npc '%s': запущена внешняя idle-анимация, дорожек костей: %d." % [npc_name, mapped_tracks])
	return true


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
