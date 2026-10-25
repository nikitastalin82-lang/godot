extends CharacterBody3D

@export var speed: float = 3.0
@export var run_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003
@export var model_forward_offset: float = 0.0
@export var idle_animation_name: StringName = &"idle"
@export var start_move_animation_name: StringName = &"start_move"
@export var move_animation_name: StringName = &"mixamo_com_006"
@export var jump_animation_name: StringName = &"jump"
@export var climb_animation_name: StringName = &"climb"
@export var elbow_animation_name: StringName = &"elbow"
@export var run_animation_name: StringName = &"run"
@export var blend_time: float = 0.2
@export var run_animation_scale: float = 1.0
@export var start_move_max_length: float = 0.6
@export var camera_follow_speed: float = 6.0
@export var auto_rotate_camera: bool = true

@onready var model: Node3D = $animation
@onready var camera_pivot: Node3D = $CameraPivot

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var animation_player: AnimationPlayer
var is_moving := false
var is_starting_move := false
var is_jumping := false
var locked_animation: StringName = &""
var camera_manual_timer := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	model.rotation.y = model_forward_offset
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_warning("В GLB не найден AnimationPlayer")
		return

	var animation_library := animation_player.get_animation_library(&"")
	if animation_library == null:
		animation_library = AnimationLibrary.new()
		animation_player.add_animation_library(&"", animation_library)

	_import_animation("стойка.fbx", idle_animation_name, true)
	_import_animation("СТАРТ ДВИЖЕНИЕ.fbx", start_move_animation_name, false, start_move_max_length)
	_import_animation("ПРЫЖОК.fbx", jump_animation_name, false)
	_import_animation("КАРАБКАНЬЕ НА ДОМ.fbx", climb_animation_name, false)
	_import_animation("УДАР ЛОКОТЬ.fbx", elbow_animation_name, false)
	_import_animation("бег.fbx", run_animation_name, true)
	_remove_root_motion(move_animation_name)
	if animation_library.has_animation(idle_animation_name):
		_play_animation(idle_animation_name)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
	
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-40),
			deg_to_rad(60)
		)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		is_jumping = true
		is_moving = false
		is_starting_move = false

	if locked_animation.is_empty():
		if Input.is_action_just_pressed("climb"):
			_start_locked_animation(climb_animation_name)
		elif Input.is_action_just_pressed("elbow"):
			_start_locked_animation(elbow_animation_name)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera_forward := -camera_pivot.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := camera_pivot.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var direction := camera_right * input_dir.x - camera_forward * input_dir.y
	var is_running := Input.is_action_pressed("run") or Input.is_physical_key_pressed(KEY_SHIFT)
	var current_speed := run_speed if is_running else speed
	var has_movement_input := direction.length_squared() > 0.0

	if locked_animation.is_empty() and has_movement_input:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		var target_rotation := atan2(-direction.x, -direction.z) + PI + model_forward_offset
		model.rotation.y = lerp_angle(model.rotation.y, target_rotation, delta * 10.0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# Камера плавно возвращается за спину персонажа (модель повёрнута в модельке,
	# поэтому целевой yaw — rotation модели + PI). Движение мышью ставит паузу на
	# 1.5 секунды, чтобы ручной обзор не вырывался из-под контроля.
	camera_manual_timer = maxf(camera_manual_timer - delta, 0.0)
	if auto_rotate_camera and camera_manual_timer <= 0.0:
		camera_pivot.rotation.y = lerp_angle(
			camera_pivot.rotation.y,
			model.rotation.y + PI,
			delta * camera_follow_speed
		)

	if not locked_animation.is_empty():
		animation_player.speed_scale = 1.0
		if not animation_player.is_playing():
			locked_animation = &""
	elif is_jumping:
		animation_player.speed_scale = 1.0
		_play_animation(jump_animation_name)
	elif has_movement_input:
		if not is_moving:
			is_starting_move = animation_player.has_animation(start_move_animation_name)
			if is_starting_move:
				_play_animation(start_move_animation_name, 0.0)
			else:
				_play_animation(move_animation_name, 0.0)
			animation_player.speed_scale = 1.0
		elif is_starting_move:
			if not animation_player.is_playing():
				is_starting_move = false
				if is_running and animation_player.has_animation(run_animation_name):
					_play_animation(run_animation_name, 0.0)
				else:
					_play_animation(move_animation_name, 0.0)
		else:
			if is_running:
				_play_animation(run_animation_name if animation_player.has_animation(run_animation_name) else move_animation_name, 0.0)
				animation_player.speed_scale = 1.0
			else:
				_play_animation(move_animation_name, 0.0)
				animation_player.speed_scale = run_animation_scale if is_running else 1.0
		is_moving = true
	else:
		is_moving = false
		is_starting_move = false
		animation_player.speed_scale = 1.0
		_play_animation(idle_animation_name)

	move_and_slide()
	if is_jumping and is_on_floor() and velocity.y <= 0.0:
		is_jumping = false

func _import_animation(file_name: String, animation_name: StringName, loop: bool, max_length: float = 0.0) -> void:
	var packed_scene := load("res://анимки/" + file_name) as PackedScene
	if packed_scene == null:
		push_warning("Не удалось загрузить анимацию: %s" % file_name)
		return

	var source_scene := packed_scene.instantiate()
	var source_player := source_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null or source_player.get_animation_list().is_empty():
		push_warning("В файле нет AnimationPlayer: %s" % file_name)
		source_scene.free()
		return

	var source_animation := source_player.get_animation(source_player.get_animation_list()[0])
	var animation := source_animation.duplicate(true) as Animation
	animation.resource_name = String(animation_name)
	for track_index in animation.get_track_count():
		var track_path := animation.track_get_path(track_index)
		animation.track_set_path(track_index, NodePath("Armature/" + str(track_path)))
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_strip_hips_position(animation)
	if max_length > 0.0 and animation.length > max_length:
		animation.length = max_length
	var animation_library := animation_player.get_animation_library(&"")
	var error := animation_library.add_animation(animation_name, animation)
	if error != OK:
		push_warning("Не удалось зарегистрировать анимацию %s: %s" % [animation_name, error])
	source_scene.free()

func _start_locked_animation(animation_name: StringName) -> void:
	if not animation_player.has_animation(animation_name):
		return
	locked_animation = animation_name
	is_moving = false
	is_starting_move = false
	_play_animation(animation_name)

func _remove_root_motion(animation_name: StringName) -> void:
	# Только для GLB-клипа ходьбы (mixamo_com_006): треки таза в нём лежат в
	# до-импортной системе координат (Z-up), поэтому без срезания ротации
	# скелет падает на спину при входе в ходьбу.
	if not animation_player.has_animation(animation_name):
		return
	var animation := animation_player.get_animation(animation_name)
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path := animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name := track_path.get_subname(track_path.get_subname_count() - 1)
		if bone_name.to_lower().contains("hips"):
			var track_type := animation.track_get_type(track_index)
			if track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D:
				animation.remove_track(track_index)
	animation.loop_mode = Animation.LOOP_LINEAR

func _strip_hips_position(animation: Animation) -> void:
	# Убираем только позиционные треки бёдер (рут-моушен). Ротацию оставляем:
	# иначе поза таза «замирает» между анимациями и спина отгибается.
	# Matchamо-кости пишутся и как "mixamorig_Hips", и как "mixamorig:Hips",
	# а NodePath режет имя по ':' — поэтому сверяем последний субнейм.
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path := animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name := track_path.get_subname(track_path.get_subname_count() - 1)
		if bone_name.to_lower().contains("hips"):
			if animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
				animation.remove_track(track_index)

func _play_animation(animation_name: StringName, custom_blend: float = blend_time) -> void:
	if not animation_player or not animation_player.has_animation(animation_name):
		return
	if animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name, custom_blend)
