extends Node3D

const SATOKO_SCENE_PATH := "res://Ресурсы/Модели/Персонажи/satoko.glb"
const UAL_SCENE_PATH := "res://Ресурсы/Анимации/UAL1_Standard.glb"
const REFERENCE_ANIMATION_CANDIDATES := ["Idle_Loop", "Idle", "Idle_Breathing"]

var satoko_instance: Node3D
var ual_instance: Node3D


func _ready() -> void:
	print("\n========== SATOKO / UAL RETARGET DIAGNOSTIC ==========")
	var satoko_packed := load(SATOKO_SCENE_PATH) as PackedScene
	if satoko_packed == null:
		push_error("Не найдена модель Сатоко: " + SATOKO_SCENE_PATH)
		return

	var ual_packed := load(UAL_SCENE_PATH) as PackedScene
	if ual_packed == null:
		push_error("Не найдена библиотека UAL1: " + UAL_SCENE_PATH)
		return

	satoko_instance = satoko_packed.instantiate() as Node3D
	ual_instance = ual_packed.instantiate() as Node3D
	if satoko_instance == null or ual_instance == null:
		push_error("Не удалось создать экземпляр одной из GLB-сцен.")
		return

	add_child(satoko_instance)
	add_child(ual_instance)
	satoko_instance.position = Vector3(-1.5, 0.0, 0.0)
	ual_instance.position = Vector3(1.5, 0.0, 0.0)
	satoko_instance.name = "Satoko_Original"
	ual_instance.name = "UAL_Reference"

	var satoko_skeleton := _find_skeleton(satoko_instance)
	var ual_skeleton := _find_skeleton(ual_instance)
	var ual_player := _find_animation_player(ual_instance)

	if satoko_skeleton == null or ual_skeleton == null:
		push_error("Не найден Skeleton3D в одной из моделей.")
		return
	if ual_player == null:
		push_error("В UAL1 не найден AnimationPlayer.")
		return

	_report_skeleton("SATOKO", satoko_skeleton)
	_report_skeleton("UAL1", ual_skeleton)
	_compare_skeletons(satoko_skeleton, ual_skeleton)
	_report_animation_tracks(ual_player)

	var chosen_animation := _find_reference_animation(ual_player)
	if chosen_animation.is_empty():
		push_warning("Не нашёл Idle-клип для демонстрации. Смотри список CLIP выше.")
	else:
		ual_player.play(chosen_animation)
		print("На эталонной модели UAL запущена анимация: ", chosen_animation)

	print("ВАЖНО: это диагностика исходных скелетов, НЕ ретаргетинг.")
	print("Сатоко оставлена без изменений; UAL показана рядом как эталон.")
	print("=====================================================\n")


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


func _report_skeleton(label: String, skeleton: Skeleton3D) -> void:
	print("\n[", label, "] bones=", skeleton.get_bone_count(),
		" motion_scale=", skeleton.motion_scale)
	for index in skeleton.get_bone_count():
		var parent_index := skeleton.get_bone_parent(index)
		var parent_name := "<root>" if parent_index < 0 else skeleton.get_bone_name(parent_index)
		var rest := skeleton.get_bone_rest(index)
		print("BONE ", skeleton.get_bone_name(index),
			" | parent=", parent_name,
			" | rest_origin=", rest.origin,
			" | rest_basis=", rest.basis)


func _compare_skeletons(satoko: Skeleton3D, source: Skeleton3D) -> void:
	var satoko_names: Array[String] = []
	for i in satoko.get_bone_count():
		satoko_names.append(String(satoko.get_bone_name(i)))

	var exact_matches := 0
	var missing: Array[String] = []
	var parent_mismatches: Array[String] = []
	for i in source.get_bone_count():
		var source_name := String(source.get_bone_name(i))
		var target_index := satoko.find_bone(source_name)
		if target_index < 0:
			missing.append(source_name)
			continue
		exact_matches += 1
		var source_parent := source.get_bone_parent(i)
		var target_parent := satoko.get_bone_parent(target_index)
		var source_parent_name := "" if source_parent < 0 else String(source.get_bone_name(source_parent))
		var target_parent_name := "" if target_parent < 0 else String(satoko.get_bone_name(target_parent))
		if source_parent_name != target_parent_name:
			parent_mismatches.append("%s: UAL parent=%s / Satoko parent=%s" % [
				source_name, source_parent_name, target_parent_name
			])

	print("\n[COMPARISON]")
	print("Exact bone-name matches: ", exact_matches, "/", source.get_bone_count())
	print("Source bones absent on Satoko: ", missing)
	print("Parent hierarchy mismatches: ", parent_mismatches)
	print("Note: matching names/hierarchy do not prove matching Bone Rest transforms.")


func _report_animation_tracks(player: AnimationPlayer) -> void:
	print("\n[ANIMATIONS] clips=", player.get_animation_list().size())
	for animation_name in player.get_animation_list():
		var animation := player.get_animation(animation_name)
		var bone_tracks: Array[String] = []
		for track_index in animation.get_track_count():
			var track_path := String(animation.track_get_path(track_index))
			if track_path.contains(":"):
				bone_tracks.append(track_path)
		print("CLIP: ", animation_name, " | tracks=", animation.get_track_count(),
			" | bone/property paths=", bone_tracks.size())


func _find_reference_animation(player: AnimationPlayer) -> StringName:
	for candidate in REFERENCE_ANIMATION_CANDIDATES:
		if player.has_animation(candidate):
			return StringName(candidate)
	for animation_name in player.get_animation_list():
		if String(animation_name).to_lower().contains("idle"):
			return animation_name
	return &""
