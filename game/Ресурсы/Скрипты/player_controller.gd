@tool
extends CharacterBody3D
## Контроллер игрока v2.
## - AnimationTree (машина состояний + BlendSpace1D для idle/walk/run), собирается кодом
## - плавный разгон и торможение, coyote-time, jump buffer, переменная высота прыжка
## - подъём на невысокие ступеньки (крыльцо домов)
## - камера на SpringArm3D (не проваливается в здания), автоцентровка сзади персонажа
## - сенсорное управление (джойстик + свайп + кнопки), клавиатура и мышь работают как раньше
## - вид от первого лица (клавиша V / кнопка VIEW)
## Подключение: выбрать узел Player -> Script -> загрузить этот файл.
## Старый character_body_3d.gd остаётся в проекте на случай отката.

const STATE_LOCO := &"Locomotion"
const STATE_JUMP := &"Jump"
const STATE_FALL := &"Fall"
const STATE_LAND := &"Land"
const STATE_CLIMB := &"Climb"
const STATE_ELBOW := &"Elbow"
const STATE_AFK_A := &"AfkA"
const STATE_AFK_B := &"AfkB"

const PARAM_BLEND := "parameters/Locomotion/Blend/blend_position"
const PARAM_SCALE := "parameters/Locomotion/Scale/scale"

const EXTRA_DIR := "res://Ресурсы/Анимации/Дополнительные/"
const TOUCH_CONTROLS_SCRIPT := preload("res://Ресурсы/Скрипты/touch_controls.gd")

@export_group("Movement")
@export var speed := 3.0
@export var run_speed := 7.0
@export var jump_velocity := 4.5
@export var ground_acceleration := 22.0
@export var ground_deceleration := 28.0
@export var air_acceleration := 6.0
@export var fall_gravity_multiplier := 1.2
@export var terminal_velocity := 40.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
## 1.0 — отключить укорачивание прыжка при раннем отпускании кнопки.
@export_range(0.1, 1.0) var jump_cut_multiplier := 0.5
## Максимальная высота ступеньки, на которую персонаж заходит сам (0 — выключено).
@export var step_height := 0.35
@export var step_probe_distance := 0.45
@export var turn_speed := 12.0
@export var model_forward_offset := 0.0

@export_group("Animation")
@export var idle_animation_name: StringName = &"idle"
## Ходьба — из отдельного файла ХОДЬБА.fbx (явно подписан пользователем),
## а не из безымянного клипа модели: тот оказался анимацией падения/смерти
## из того же Mixamo-пакета (рядом лежит Standing React Death Forward.fbx),
## из-за чего персонаж заваливался на спину.
@export var move_animation_name: StringName = &"walk"
@export var run_animation_name: StringName = &"run"
@export var jump_animation_name: StringName = &"jump"
@export var climb_animation_name: StringName = &"climb"
@export var elbow_animation_name: StringName = &"elbow"
@export var fall_animation_name: StringName = &"fall"
@export var land_animation_name: StringName = &"land"
@export var afk_a_animation_name: StringName = &"afk_wave"
@export var afk_b_animation_name: StringName = &"afk_talk"
## Скорость (м/с), которой "соответствуют" ноги в клипе ходьбы/бега при масштабе 1.0.
## Если ноги скользят вперёд — уменьшите значение, если "буксуют" — увеличьте.
@export var walk_anim_speed := 3.0
@export var run_anim_speed := 7.0
@export var fall_anim_delay := 0.18
@export var hard_landing_speed := 9.0
@export var afk_delay_min := 8.0
@export var afk_delay_max := 16.0

@export_group("Camera & Input")
@export var camera_distance := 5.0
@export var camera_shoulder_offset := 0.4
@export var pitch_min_degrees := -40.0
@export var pitch_max_degrees := 60.0
## Вид от первого лица (переключение: клавиша V или кнопка VIEW на экране).
@export var first_person_height := 1.62
@export var first_person_fov := 78.0
@export var first_person_pitch_min_degrees := -80.0
@export var first_person_pitch_max_degrees := 80.0
@export var view_transition_time := 0.25
@export var mouse_sensitivity := 0.003
@export var touch_look_sensitivity := 0.005
## Для джойстика: при отклонении больше этого порога персонаж бежит.
@export_range(0.5, 1.0) var touch_run_threshold := 0.92
## Включить сенсорный интерфейс на ПК (для тестов).
@export var force_touch_mode := false
## Камера плавно возвращается за спину персонажа, когда её не вращают вручную.
@export var auto_rotate_camera := true
@export var camera_follow_speed := 6.0

@onready var model: Node3D = $animation
@onready var camera_pivot: Node3D = $CameraPivot

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _touch_mode := false
var _touch = null
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _first_person := false
var _view_tween: Tween
var _third_person_pivot_y := 1.35
var _third_person_fov := 75.0
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _available_states: Array[StringName] = []
var _camera_manual_timer := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0
var _air_time := 0.0
var _jump_length := 1.0

var _oneshot_state: StringName = &""
var _oneshot_length := 0.0
var _oneshot_age := 0.0
var _oneshot_min_age := 0.0
var _oneshot_interruptible := false

var _afk_timer := 0.0
var _afk_threshold := 10.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_editor_preview_pose.call_deferred()
		return
	add_to_group(&"player")
	_touch_mode = DisplayServer.is_touchscreen_available() or force_touch_mode

	# Настройки физики персонажа против залипаний на зданиях и декорациях.
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	slide_on_ceiling = true
	safe_margin = 0.01

	model.rotation.y = model_forward_offset
	_ensure_input_actions()
	_setup_camera()
	_setup_touch()
	_setup_animation()
	_reset_afk_timer()

	if not _touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



## В редакторе применяем ту же вертикальную rest-позу таза, которую игра
## выставляет при запуске. Это только предпросмотр: физика и коллайдер не меняются.
func _apply_editor_preview_pose() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var model_node := get_node_or_null("animation") as Node3D
	if model_node == null:
		return
	var skeleton := model_node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var source_scene := load("res://анимки/стойка.fbx") as PackedScene
	if source_scene == null:
		return
	var source := source_scene.instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	if source_player == null or source_skeleton == null:
		source.free()
		return
	var clip: Animation
	for anim_name in source_player.get_animation_list():
		if anim_name != &"RESET":
			clip = source_player.get_animation(anim_name)
			break
	if clip == null:
		source.free()
		return
	var bone_map := _build_bone_map()
	for track_index in clip.get_track_count():
		if clip.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path := clip.track_get_path(track_index)
		if track_path.get_subname_count() == 0 or clip.track_get_key_count(track_index) == 0:
			continue
		var source_bone := String(track_path.get_subname(track_path.get_subname_count() - 1))
		var target_bone: String = bone_map.get(source_bone.trim_prefix("mixamorig_"), "")
		if target_bone != "pelvis":
			continue
		var bone_index := skeleton.find_bone(target_bone)
		if bone_index < 0:
			continue
		var rest := skeleton.get_bone_rest(bone_index)
		rest.basis = Basis(clip.track_get_key_value(track_index, 0) as Quaternion)
		skeleton.set_bone_rest(bone_index, rest)
		skeleton.reset_bone_pose(bone_index)
		break
	source.free()


# ------------------------------------------------------------------ Камера / ввод

func _setup_camera() -> void:
	_spring_arm = camera_pivot.get_node_or_null("SpringArm3D") as SpringArm3D
	if _spring_arm == null:
		var camera := camera_pivot.get_node_or_null("Camera3D") as Camera3D
		_spring_arm = SpringArm3D.new()
		_spring_arm.name = "SpringArm3D"
		_spring_arm.spring_length = camera_distance
		_spring_arm.margin = 0.2
		var probe := SphereShape3D.new()
		probe.radius = 0.25
		_spring_arm.shape = probe
		camera_pivot.add_child(_spring_arm)
		if camera != null:
			camera.reparent(_spring_arm, false)
			camera.transform = Transform3D.IDENTITY
			camera.v_offset = camera_shoulder_offset
	_spring_arm.add_excluded_object(get_rid())
	camera_pivot.rotation.x = deg_to_rad(-8.0)
	_camera = _spring_arm.get_node_or_null("Camera3D") as Camera3D
	_third_person_pivot_y = camera_pivot.position.y
	if _camera != null:
		_third_person_fov = _camera.fov
		_camera.near = 0.05
		_camera.far = 300.0


func _setup_touch() -> void:
	_touch = get_tree().get_first_node_in_group(&"touch_controls")
	if _touch == null and _touch_mode:
		_touch = TOUCH_CONTROLS_SCRIPT.new()
		_touch.show_on_desktop = force_touch_mode
		get_parent().add_child.call_deferred(_touch)
	if _touch != null:
		_touch.look_delta.connect(_on_touch_look)


func _on_touch_look(relative: Vector2) -> void:
	_rotate_camera(relative * touch_look_sensitivity)


func _rotate_camera(relative: Vector2) -> void:
	_camera_manual_timer = 1.5
	var pitch_min := first_person_pitch_min_degrees if _first_person else pitch_min_degrees
	var pitch_max := first_person_pitch_max_degrees if _first_person else pitch_max_degrees
	camera_pivot.rotation.y -= relative.x
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x - relative.y,
		deg_to_rad(pitch_min),
		deg_to_rad(pitch_max)
	)


## Камера мягко доворачивается за спину персонажа (модель повёрнута по +PI,
## поэтому целевой yaw — rotation модели + PI). Ручной обзор ставит паузу в
## _rotate_camera, после 1.5 с тишины камера возвращается.
func _follow_camera(delta: float) -> void:
	_camera_manual_timer = maxf(_camera_manual_timer - delta, 0.0)
	if not auto_rotate_camera or _first_person or _camera_manual_timer > 0.0:
		return
	camera_pivot.rotation.y = lerp_angle(
		camera_pivot.rotation.y,
		model.rotation.y + PI,
		delta * camera_follow_speed
	)


func _unhandled_input(event: InputEvent) -> void:
	if _touch_mode:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera((event as InputEventMouseMotion).relative * mouse_sensitivity)


func _read_move_input() -> Vector2:
	if _touch != null:
		var stick: Vector2 = _touch.move_vector
		if stick.length_squared() > 0.0001:
			return stick

	# Сначала используем InputMap. Прямое чтение физических клавиш оставлено
	# как резерв: это помогает при несовпадении device ID клавиатуры между
	# версиями Godot (в 4.7 клавиатура получила отдельный ID 16).
	var mapped := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mapped.length_squared() > 0.0001:
		return mapped

	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	return keyboard.limit_length(1.0)


func _wants_run(input_dir: Vector2) -> bool:
	if Input.is_action_pressed("run") or Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	return _touch != null and _touch.stick_active and input_dir.length() >= touch_run_threshold


func _camera_direction(input_dir: Vector2) -> Vector3:
	var forward := -camera_pivot.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_pivot.global_basis.x
	right.y = 0.0
	right = right.normalized()
	return right * input_dir.x - forward * input_dir.y


# ------------------------------------------------------------------ Физика

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_view"):
		_toggle_view()

	var on_floor := is_on_floor()

	if on_floor:
		_coyote = coyote_time
		_air_time = 0.0
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		_air_time += delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	var locked := _is_locked()
	var input_dir := _read_move_input()
	if locked:
		input_dir = Vector2.ZERO
	var has_input := input_dir.length_squared() > 0.01

	# Вертикаль: гравитация, прыжок, укорачивание прыжка.
	if not on_floor:
		var g := gravity * (fall_gravity_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -terminal_velocity)

	var just_jumped := false
	if _jump_buffer > 0.0 and _coyote > 0.0 and not locked:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		just_jumped = true
	if Input.is_action_just_released("jump") and velocity.y > 0.0 and not on_floor:
		velocity.y *= jump_cut_multiplier

	# Горизонталь: плавный разгон и торможение.
	var direction := _camera_direction(input_dir)
	var top_speed := run_speed if _wants_run(input_dir) else speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var accel := air_acceleration
	if on_floor:
		accel = ground_acceleration if has_input else ground_deceleration
	horizontal = horizontal.move_toward(direction * top_speed, accel * delta)

	if _first_person:
		# В первом лице тело всегда смотрит туда же, куда камера.
		var look := -camera_pivot.global_basis.z
		var look_yaw := atan2(-look.x, -look.z) + PI + model_forward_offset
		model.rotation.y = lerp_angle(model.rotation.y, look_yaw, 1.0 - exp(-turn_speed * 2.0 * delta))
	elif has_input:
		var target_yaw := atan2(-direction.x, -direction.z) + PI + model_forward_offset
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	_follow_camera(delta)
	_step_up(horizontal)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var vertical_before := velocity.y
	move_and_slide()
	var now_on_floor := is_on_floor()
	var just_landed := now_on_floor and not on_floor

	# Одноразовые действия (только с земли и не во время другого действия).
	if not locked and now_on_floor and _oneshot_state == &"":
		if Input.is_action_just_pressed("climb"):
			_start_oneshot(STATE_CLIMB, climb_animation_name, false, 0.0)
		elif Input.is_action_just_pressed("elbow"):
			_start_oneshot(STATE_ELBOW, elbow_animation_name, false, 0.0)

	_update_afk(delta, has_input, now_on_floor)
	_tick_oneshot(delta, has_input)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_update_animation(now_on_floor, just_jumped, just_landed, -vertical_before, horizontal_speed)


## Подъём на невысокие препятствия (ступеньки крыльца), чтобы не упираться в них.
func _step_up(horizontal: Vector3) -> void:
	if step_height <= 0.0 or not is_on_floor() or velocity.y > 0.1:
		return
	if horizontal.length_squared() < 0.01:
		return
	var probe := horizontal.normalized() * step_probe_distance
	if not test_move(global_transform, probe):
		return
	var lift := Vector3.UP * step_height
	if test_move(global_transform, lift):
		return
	var raised := global_transform.translated(lift)
	if test_move(raised, probe):
		return
	var ground := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), Vector3.DOWN * (step_height + 0.05), ground):
		return
	if ground.get_normal().y < cos(floor_max_angle):
		return
	var rise := step_height - ground.get_travel().length()
	if rise > 0.01:
		global_position.y += rise + 0.01


# ------------------------------------------------------------------ Одноразовые состояния

func _ensure_input_actions() -> void:
	if InputMap.has_action(&"toggle_view"):
		return
	InputMap.add_action(&"toggle_view")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	InputMap.action_add_event(&"toggle_view", key)


## Переключение вида от третьего лица к первому и обратно с плавным переходом.
func _toggle_view() -> void:
	if _camera == null or _spring_arm == null:
		return
	_first_person = not _first_person
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()

	var arm_length := 0.0 if _first_person else camera_distance
	var pivot_y := first_person_height if _first_person else _third_person_pivot_y
	var fov := first_person_fov if _first_person else _third_person_fov
	var shoulder := 0.0 if _first_person else camera_shoulder_offset
	if not _first_person:
		_set_body_visible(true)

	var pitch_min := first_person_pitch_min_degrees if _first_person else pitch_min_degrees
	var pitch_max := first_person_pitch_max_degrees if _first_person else pitch_max_degrees
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, deg_to_rad(pitch_min), deg_to_rad(pitch_max))

	_view_tween = create_tween()
	_view_tween.set_parallel(true)
	_view_tween.set_trans(Tween.TRANS_SINE)
	_view_tween.set_ease(Tween.EASE_OUT)
	_view_tween.tween_property(_spring_arm, "spring_length", arm_length, view_transition_time)
	_view_tween.tween_property(camera_pivot, "position:y", pivot_y, view_transition_time)
	_view_tween.tween_property(_camera, "fov", fov, view_transition_time)
	_view_tween.tween_property(_camera, "v_offset", shoulder, view_transition_time)
	if _first_person:
		# Когда камера уже внутри головы, прячем тело (тень остаётся).
		_view_tween.chain().tween_callback(_set_body_visible.bind(false))


## Скрывает модель для камеры, но оставляет её тень.
func _set_body_visible(body_visible: bool) -> void:
	var setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not body_visible:
		setting = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = setting


func _is_locked() -> bool:
	return _oneshot_state != &"" and not _oneshot_interruptible


func _start_oneshot(state: StringName, clip: StringName, interruptible: bool, min_age: float) -> bool:
	if _playback == null or not _available_states.has(state):
		return false
	var animation := _animation_player.get_animation(clip)
	if animation == null:
		return false
	_oneshot_state = state
	_oneshot_length = maxf(animation.length - 0.15, 0.1)
	_oneshot_age = 0.0
	_oneshot_min_age = min_age
	_oneshot_interruptible = interruptible
	_travel(state)
	return true


func _tick_oneshot(delta: float, has_input: bool) -> void:
	if _oneshot_state == &"":
		return
	_oneshot_age += delta
	var finished := _oneshot_age >= _oneshot_length
	var cancelled := _oneshot_interruptible and has_input and _oneshot_age >= _oneshot_min_age
	if finished or cancelled:
		_oneshot_state = &""
		_travel(STATE_LOCO)
		_reset_afk_timer()


func _update_afk(delta: float, has_input: bool, on_floor: bool) -> void:
	if has_input or not on_floor or _oneshot_state != &"":
		_afk_timer = 0.0
		return
	_afk_timer += delta
	if _afk_timer < _afk_threshold:
		return
	var options: Array[StringName] = []
	if _available_states.has(STATE_AFK_A):
		options.append(STATE_AFK_A)
	if _available_states.has(STATE_AFK_B):
		options.append(STATE_AFK_B)
	_reset_afk_timer()
	if options.is_empty():
		return
	var state: StringName = options.pick_random()
	var clip := afk_a_animation_name if state == STATE_AFK_A else afk_b_animation_name
	_start_oneshot(state, clip, true, 0.0)


func _reset_afk_timer() -> void:
	_afk_timer = 0.0
	_afk_threshold = randf_range(afk_delay_min, afk_delay_max)


# ------------------------------------------------------------------ Анимации

func _travel(state: StringName) -> void:
	if _playback == null or not _available_states.has(state):
		return
	if _playback.get_current_node() != state:
		_playback.travel(state)


func _update_animation(on_floor: bool, just_jumped: bool, just_landed: bool, impact_speed: float, horizontal_speed: float) -> void:
	if _playback == null:
		return
	_apply_locomotion_params(horizontal_speed)

	if just_jumped:
		_oneshot_state = &""
		_travel(STATE_JUMP)
		return
	if _oneshot_state != &"":
		return

	var current := _playback.get_current_node()
	if not on_floor:
		if current == STATE_JUMP:
			if velocity.y < 0.0 and _air_time >= _jump_length * 0.9:
				_travel(STATE_FALL)
		elif current != STATE_FALL and _air_time > fall_anim_delay and velocity.y < -1.0:
			_travel(STATE_FALL)
		return

	if just_landed:
		var played := false
		if impact_speed >= hard_landing_speed:
			played = _start_oneshot(STATE_LAND, land_animation_name, true, 0.35)
		if not played:
			_travel(STATE_LOCO)
	elif current == STATE_JUMP or current == STATE_FALL:
		_travel(STATE_LOCO)


func _apply_locomotion_params(horizontal_speed: float) -> void:
	_animation_tree.set(PARAM_BLEND, horizontal_speed)
	var run_t := clampf(inverse_lerp(speed, run_speed, horizontal_speed), 0.0, 1.0)
	var ratio := lerpf(
		speed / maxf(walk_anim_speed, 0.01),
		run_speed / maxf(run_anim_speed, 0.01),
		run_t
	)
	var weight := clampf(horizontal_speed / maxf(speed, 0.01), 0.0, 1.0)
	_animation_tree.set(PARAM_SCALE, lerpf(1.0, ratio, weight))


func _setup_animation() -> void:
	_animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("Player: AnimationPlayer не найден в модели.")
		return

	var library := _animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library(&"", library)

	_import_clip("res://анимки/стойка.fbx", idle_animation_name, true)
	_import_clip(EXTRA_DIR + "ХОДЬБА.fbx", move_animation_name, true)
	_import_clip("res://анимки/бег.fbx", run_animation_name, true)
	_import_clip("res://анимки/ПРЫЖОК.fbx", jump_animation_name, false)
	_import_clip("res://анимки/КАРАБКАНЬЕ НА ДОМ.fbx", climb_animation_name, false)
	_import_clip("res://анимки/УДАР ЛОКОТЬ.fbx", elbow_animation_name, false)
	_import_clip(EXTRA_DIR + "ПРЫЖОК НИЗ.fbx", fall_animation_name, false)
	_import_clip(EXTRA_DIR + "Hard Landing.fbx", land_animation_name, false)
	_import_clip(EXTRA_DIR + "Waving.fbx", afk_a_animation_name, false)
	_import_clip(EXTRA_DIR + "Talking.fbx", afk_b_animation_name, false)
	_fix_hips_rest()

	if _animation_player.has_animation(jump_animation_name):
		_jump_length = _animation_player.get_animation(jump_animation_name).length
	_build_animation_tree()


func _build_animation_tree() -> void:
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(STATE_LOCO, _make_locomotion_node(), Vector2(0, 0))
	_available_states = [STATE_LOCO]

	var oneshots := {
		STATE_JUMP: jump_animation_name,
		STATE_FALL: fall_animation_name,
		STATE_LAND: land_animation_name,
		STATE_CLIMB: climb_animation_name,
		STATE_ELBOW: elbow_animation_name,
		STATE_AFK_A: afk_a_animation_name,
		STATE_AFK_B: afk_b_animation_name,
	}
	var row := 1
	for state in oneshots:
		var clip: StringName = oneshots[state]
		if not _animation_player.has_animation(clip):
			push_warning("Player: нет анимации '%s', состояние %s пропущено." % [clip, state])
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		machine.add_node(state, node, Vector2(280, 90 * row))
		_available_states.append(state)
		row += 1

	# Полный граф переходов: из любого состояния в любое, без лишних промежуточных клипов.
	for from_state in _available_states:
		for to_state in _available_states:
			if from_state == to_state:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = _xfade_for(to_state)
			machine.add_transition(from_state, to_state, transition)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(&"Start", STATE_LOCO, start)

	_animation_tree = AnimationTree.new()
	_animation_tree.name = "AnimationTree"
	_animation_player.get_parent().add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)
	_animation_tree.root_node = _animation_tree.get_path_to(_animation_player.get_node(_animation_player.root_node))
	# Анимация обновляется каждый кадр (плавно на 120 Гц), логика — в физике.
	_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_animation_tree.tree_root = machine
	_animation_player.stop()
	_animation_tree.active = true
	_playback = _animation_tree.get("parameters/playback")
	_playback.start(STATE_LOCO)


func _make_locomotion_node() -> AnimationNodeBlendTree:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = run_speed
	space.sync = true
	_add_blend_point(space, idle_animation_name, 0.0)
	_add_blend_point(space, move_animation_name, speed)
	_add_blend_point(space, run_animation_name, run_speed)

	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(&"Blend", space, Vector2(0, 0))
	blend_tree.add_node(&"Scale", AnimationNodeTimeScale.new(), Vector2(260, 0))
	blend_tree.connect_node(&"Scale", 0, &"Blend")
	blend_tree.connect_node(&"output", 0, &"Scale")
	return blend_tree


func _add_blend_point(space: AnimationNodeBlendSpace1D, clip: StringName, position: float) -> void:
	if not _animation_player.has_animation(clip):
		push_warning("Player: нет анимации '%s' для Locomotion." % clip)
		return
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	space.add_blend_point(node, position)


func _xfade_for(state: StringName) -> float:
	if state == STATE_JUMP or state == STATE_LAND:
		return 0.08
	if state == STATE_ELBOW:
		return 0.06
	if state == STATE_CLIMB:
		return 0.12
	if state == STATE_AFK_A or state == STATE_AFK_B:
		return 0.3
	return 0.2


# ------------------------------------------------------------------ Импорт клипов

func _import_clip(path: String, clip_name: StringName, loop: bool) -> void:
	var library := _animation_player.get_animation_library(&"")
	if library.has_animation(clip_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("Player: файл анимации не найден: %s" % path)
		return
	var source := load(path) as PackedScene
	if source == null:
		return
	var instance := source.instantiate()
	var source_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		instance.queue_free()
		return
	var found: Animation = null
	for animation_name in source_player.get_animation_list():
		if animation_name == &"RESET":
			continue
		found = source_player.get_animation(animation_name)
		break
	if found != null:
		var clip := found.duplicate(true) as Animation
		clip.resource_name = String(clip_name)
		_prefix_tracks(clip)
		_strip_hips_tracks(clip, false)
		clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		library.add_animation(clip_name, clip)
	instance.free()


## Подстраховка: если у какого-то клипа в библиотеке треки таза срезаны или
## отсутствуют, таз остаётся в rest-позе скелета. Если эта rest-поза лежачая
## (так бывает у некоторых экспортов), персонаж будет выглядеть падающим
## в любом состоянии без собственного трека таза. Берём вертикальную
## ориентацию таза из первого кадра анимации "стойка" (она заведомо верна,
## раз персонаж в ней стоит) и прописываем её в rest скелета.
func _fix_hips_rest() -> void:
	var skeleton := _animation_player.get_node(_animation_player.root_node).find_child(&"Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var library := _animation_player.get_animation_library(&"")
	if not library.has_animation(idle_animation_name):
		return
	var idle_clip := library.get_animation(idle_animation_name)
	var hips_bone_idx := -1
	var upright := Quaternion.IDENTITY
	for track_index in idle_clip.get_track_count():
		var path := idle_clip.track_get_path(track_index)
		if path.get_subname_count() == 0:
			continue
		var bone_name := path.get_subname(path.get_subname_count() - 1)
		if not bone_name.to_lower().contains("hips"):
			continue
		if idle_clip.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		if idle_clip.track_get_key_count(track_index) == 0:
			continue
		hips_bone_idx = skeleton.find_bone(bone_name)
		if hips_bone_idx < 0:
			continue
		upright = idle_clip.track_get_key_value(track_index, 0)
		break
	if hips_bone_idx < 0:
		return
	var rest := skeleton.get_bone_rest(hips_bone_idx)
	rest.basis = Basis(upright)
	skeleton.set_bone_rest(hips_bone_idx, rest)
	skeleton.reset_bone_pose(hips_bone_idx)


func _prefix_tracks(clip: Animation) -> void:
	for i in clip.get_track_count():
		clip.track_set_path(i, NodePath("Armature/" + str(clip.track_get_path(i))))


## Убирает позиционные треки бёдер, чтобы движением персонажа управлял код
## физики, а не сама анимация (иначе клипы «едут» вперёд сами по себе).
## Кости Mixamo бывают "mixamorig_Hips" и "mixamorig:Hips", а NodePath режет
## имя по ':', поэтому сверяем последний subname через contains().
func _strip_hips_tracks(clip: Animation, include_rotation: bool) -> void:
	for i in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var bone_name := path.get_subname(path.get_subname_count() - 1)
		if not bone_name.to_lower().contains("hips"):
			continue
		var track_type := clip.track_get_type(i)
		if track_type == Animation.TYPE_POSITION_3D or (include_rotation and track_type == Animation.TYPE_ROTATION_3D):
			clip.remove_track(i)
