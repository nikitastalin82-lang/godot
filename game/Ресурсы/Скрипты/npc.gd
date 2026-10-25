extends Node3D

@export var character: PackedScene
@export var npc_name := "NPC"
@export var look_at_player_range := 4.0
@export var turn_speed := 3.0
@export var external_idle_animation: PackedScene = preload("res://анимки/стойка.fbx")

var _model: Node3D
var _animation_player: AnimationPlayer
var _player: Node3D
var _target_yaw := 0.0


func _ready() -> void:
	add_to_group(&"npc")
	if character == null:
		push_warning("NPC: character is not assigned.")
		return

	var instance := character.instantiate()
	_model = instance as Node3D
	if _model == null:
		instance.free()
		push_warning("NPC: character root must be Node3D.")
		return

	add_child(_model)
	_target_yaw = rotation.y

	var terrain := get_tree().get_first_node_in_group(&"terrain")
	if terrain != null:
		position.y += terrain.sample_height(global_position.x, global_position.z)

	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		_animation_player = AnimationPlayer.new()
		_animation_player.name = "AnimationPlayer"
		_model.add_child(_animation_player)

	_play_idle()
	_player = get_tree().get_first_node_in_group(&"player")
	if _player == null and get_tree().current_scene != null:
		_player = get_tree().current_scene.find_child("Player", true, false) as Node3D


func _build_bone_map() -> Dictionary:
	var result := {
		"Hips": "pelvis",
		"Spine": "spine_01",
		"Spine1": "spine_02",
		"Spine2": "spine_03",
		"Neck": "neck_01",
		"Head": "head",
		"HeadTop_End": "head_leaf"
	}
	for side in ["Left", "Right"]:
		var suffix: String = "l" if side == "Left" else "r"
		result[side + "Shoulder"] = "clavicle_" + suffix
		result[side + "Arm"] = "upperarm_" + suffix
		result[side + "ForeArm"] = "lowerarm_" + suffix
		result[side + "Hand"] = "hand_" + suffix
		result[side + "UpLeg"] = "thigh_" + suffix
		result[side + "Leg"] = "calf_" + suffix
		result[side + "Foot"] = "foot_" + suffix
		result[side + "ToeBase"] = "ball_" + suffix
		result[side + "Toe_End"] = "ball_leaf_" + suffix
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var finger_name: String = String(finger).to_lower()
			for segment in range(1, 5):
				var segment_name: String = "%02d" % segment
				var target_name: String = finger_name + "_" + segment_name
				if segment == 4:
					target_name += "_leaf"
				result[side + "Hand" + String(finger) + str(segment)] = target_name + "_" + suffix
	return result


func _play_idle() -> void:
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("NPC %s: Skeleton3D not found." % npc_name)
		return

	if external_idle_animation == null:
		push_warning("NPC %s: idle FBX is not assigned." % npc_name)
		return

	var source := external_idle_animation.instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	if source_player == null or source_skeleton == null:
		source.free()
		push_warning("NPC %s: стойка.fbx has no AnimationPlayer or Skeleton3D." % npc_name)
		return

	var source_clip: Animation
	for anim_name in source_player.get_animation_list():
		if anim_name != &"RESET":
			source_clip = source_player.get_animation(anim_name)
			break
	if source_clip == null:
		source.free()
		push_warning("NPC %s: стойка.fbx contains no animation clip." % npc_name)
		return

	var target_clip := source_clip.duplicate() as Animation
	var bone_map := _build_bone_map()
	var mapped := 0
	var unmapped: Array[String] = []
	var animation_root := _animation_player.get_node_or_null(_animation_player.root_node) as Node
	if animation_root == null:
		animation_root = _animation_player
	var skeleton_path := animation_root.get_path_to(skeleton)
	for i in range(target_clip.get_track_count()):
		var old_path := String(target_clip.track_get_path(i))
		var colon := old_path.rfind(":")
		if colon == -1:
			continue
		var source_bone := old_path.substr(colon + 1)
		if source_skeleton.find_bone(source_bone) == -1:
			continue
		var target_bone: String = bone_map.get(source_bone.trim_prefix("mixamorig_"), "")
		if target_bone.is_empty() or skeleton.find_bone(target_bone) == -1:
			unmapped.append(source_bone)
			continue
		target_clip.track_set_path(i, NodePath(String(skeleton_path) + ":" + target_bone))
		mapped += 1

	source.free()
	if mapped == 0:
		push_warning("NPC %s: no compatible animation tracks were mapped." % npc_name)
		return
	if not unmapped.is_empty():
		push_warning("NPC %s: skipped unmapped bones: %s" % [npc_name, ", ".join(unmapped)])

	var library: AnimationLibrary
	if _animation_player.has_animation_library(&""):
		library = _animation_player.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library(&"", library)
	if library.has_animation(&"satoko_idle"):
		library.remove_animation(&"satoko_idle")
	target_clip.loop_mode = Animation.LOOP_LINEAR
	var error := library.add_animation(&"satoko_idle", target_clip)
	if error != OK:
		push_warning("NPC %s: could not add idle animation: %s" % [npc_name, error])
		return
	_animation_player.play(&"satoko_idle")
	print("NPC %s: idle started; mapped tracks: %d/%d" % [npc_name, mapped, target_clip.get_track_count()])


func _process(delta: float) -> void:
	if _player != null and look_at_player_range > 0.0:
		var direction := _player.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.01 and direction.length() <= look_at_player_range:
			_target_yaw = atan2(direction.x, direction.z) + PI
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-turn_speed * delta))
