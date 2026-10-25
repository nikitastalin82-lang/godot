extends Node3D

const SATOKO_SCENE_PATH := "res://Ресурсы/Модели/Персонажи/satoko.glb"
const UAL_SCENE_PATH := "res://Ресурсы/Анимации/UAL1_Standard.glb"

var satoko_instance: Node3D
var ual_instance: Node3D

func _ready() -> void:
	print("\n========== SATOKO ANIMATION CHECK ==========")
	var satoko_packed := load(SATOKO_SCENE_PATH) as PackedScene
	if satoko_packed == null:
		push_error("Не найдена модель Сатоко: " + SATOKO_SCENE_PATH)
		return

	var ual_packed := load(UAL_SCENE_PATH) as PackedScene
	if ual_packed == null:
		push_error("Не найдена библиотека UAL1. Скопируй UAL1_Standard.glb в: " + UAL_SCENE_PATH)
		return

	satoko_instance = satoko_packed.instantiate() as Node3D
	ual_instance = ual_packed.instantiate() as Node3D
	if satoko_instance == null or ual_instance == null:
		push_error("Не удалось создать экземпляр одной из GLB-сцен.")
		return

	add_child(satoko_instance)
	add_child(ual_instance)
	satoko_instance.position = Vector3(-1.2, 0.0, 0.0)
	ual_instance.position = Vector3(1.2, 0.0, 0.0)
	ual_instance.visible = false

	var satoko_skeleton := _find_skeleton(satoko_instance)
	var ual_skeleton := _find_skeleton(ual_instance)
	var ual_player := _find_animation_player(ual_instance)

	if satoko_skeleton == null:
		push_error("В модели Сатоко не найден Skeleton3D.")
		return
	if ual_skeleton == null:
		push_error("В UAL1 не найден Skeleton3D.")
		return
	if ual_player == null:
		push_error("В UAL1 не найден AnimationPlayer.")
		return

	var satoko_bones := _bone_names(satoko_skeleton)
	var ual_bones := _bone_names(ual_skeleton)
	var matched := 0
	var missing: Array[String] = []
	for bone_name in ual_bones:
		if satoko_bones.has(bone_name):
			matched += 1
		else:
			missing.append(bone_name)

	print("Satoko skeleton: ", satoko_skeleton.get_path())
	print("Satoko bones: ", satoko_bones.size())
	print("UAL1 bones: ", ual_bones.size())
	print("Exact bone-name matches: ", matched, "/", ual_bones.size())
	print("UAL bones missing on Satoko: ", missing)
	print("Animation clips found: ", ual_player.get_animation_list().size())

	for animation_name in ual_player.get_animation_list():
		var animation := ual_player.get_animation(animation_name)
		var bone_tracks: Array[String] = []
		for track_index in animation.get_track_count():
			var track_path := animation.track_get_path(track_index)
			if String(track_path).contains(":"):
				bone_tracks.append(String(track_path))
		print("CLIP: ", animation_name, " | tracks: ", animation.get_track_count(),
			" | bone/property paths: ", bone_tracks.size())
		for path in bone_tracks:
			print("  ", path)

	print("Проверка завершена. Исходная модель не изменялась.")
	print("===========================================\n")


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


func _bone_names(skeleton: Skeleton3D) -> Array[String]:
	var result: Array[String] = []
	for index in skeleton.get_bone_count():
		result.append(skeleton.get_bone_name(index))
	return result
