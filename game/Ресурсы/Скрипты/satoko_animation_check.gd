extends Node3D

const SATOKO_SCENE_PATH := "res://Модель персонажа Сатоко Кирагая/webglripper_hyper3d.ai_20261024-090446-rigged.glb"
const IDLE_SCENE_PATH := "res://анимки/стойка.fbx"


func _ready() -> void:
	print("\n========== SATOKO IDLE DIAGNOSTIC ==========")
	var satoko := _instantiate(SATOKO_SCENE_PATH)
	var idle := _instantiate(IDLE_SCENE_PATH)
	if satoko == null or idle == null:
		return
	add_child(satoko)
	add_child(idle)
	var target_skeleton := _find_node(satoko, "Skeleton3D") as Skeleton3D
	var source_skeleton := _find_node(idle, "Skeleton3D") as Skeleton3D
	var player := _find_node(idle, "AnimationPlayer") as AnimationPlayer
	if target_skeleton == null or source_skeleton == null or player == null:
		print("DIAG_FAIL target_skeleton=", target_skeleton, " source_skeleton=", source_skeleton, " animation_player=", player)
		return
	print("TARGET BONES ", target_skeleton.get_bone_count())
	for i in target_skeleton.get_bone_count():
		print("TARGET_BONE ", i, " ", target_skeleton.get_bone_name(i), " parent=", target_skeleton.get_bone_parent(i))
	print("SOURCE BONES ", source_skeleton.get_bone_count())
	for i in source_skeleton.get_bone_count():
		print("SOURCE_BONE ", i, " ", source_skeleton.get_bone_name(i), " parent=", source_skeleton.get_bone_parent(i))
	print("ANIMATION PLAYER ROOT ", player.root_node)
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		print("CLIP ", anim_name, " tracks=", anim.get_track_count(), " length=", anim.length)
		for i in anim.get_track_count():
			print("TRACK ", anim.track_get_type(i), " ", anim.track_get_path(i))
	var matches := 0
	for i in source_skeleton.get_bone_count():
		var bone := String(source_skeleton.get_bone_name(i))
		if target_skeleton.find_bone(bone) >= 0:
			matches += 1
	print("EXACT_BONE_MATCHES ", matches, "/", source_skeleton.get_bone_count())
	print("============================================")

	# Test the actual NPC scene and its runtime retargeting, not just the source rigs.
	var npc_pack := load("res://Ресурсы/Сцены/npcs.tscn") as PackedScene
	if npc_pack == null:
		print("RUNTIME_DIAG_FAIL cannot load npcs.tscn")
		return
	var npc_root := npc_pack.instantiate()
	add_child(npc_root)
	await get_tree().process_frame
	var npc := _find_node(npc_root, "NpcSatoko")
	if npc == null:
		print("RUNTIME_DIAG_FAIL NpcSatoko node not found")
		return
	var runtime_skeleton := _find_node(npc, "Skeleton3D") as Skeleton3D
	var runtime_player := _find_node(npc, "AnimationPlayer") as AnimationPlayer
	if runtime_skeleton == null or runtime_player == null:
		print("RUNTIME_DIAG_FAIL skeleton=", runtime_skeleton, " player=", runtime_player)
		return
	print("RUNTIME_ANIMATION current=", runtime_player.current_animation, " is_playing=", runtime_player.is_playing(), " root=", runtime_player.root_node)
	var runtime_clip := runtime_player.get_animation("satoko_idle")
	if runtime_clip == null:
		print("RUNTIME_DIAG_FAIL satoko_idle clip missing")
		return
	print("RUNTIME_TRACKS ", runtime_clip.get_track_count())
	for i in runtime_clip.get_track_count():
		print("RUNTIME_TRACK ", runtime_clip.track_get_path(i))
	var before := runtime_skeleton.get_bone_pose_rotation(1)
	runtime_player.seek(0.0, true)
	runtime_player.advance(0.0)
	var pose_start := runtime_skeleton.get_bone_pose_rotation(1)
	runtime_player.seek(minf(0.75, runtime_clip.length), true)
	runtime_player.advance(0.0)
	var pose_later := runtime_skeleton.get_bone_pose_rotation(1)
	print("RUNTIME_POSE pelvis_start=", pose_start, " pelvis_later=", pose_later, " changed=", not pose_start.is_equal_approx(pose_later), " original=", before)
	print("========== END RUNTIME DIAGNOSTIC ==========")



func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		print("DIAG_FAIL cannot load ", path)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		print("DIAG_FAIL root is not Node3D: ", path)
	return node


func _find_node(root: Node, wanted: String) -> Node:
	if root.name == wanted:
		return root
	for child in root.get_children():
		var found := _find_node(child, wanted)
		if found != null:
			return found
	return null
