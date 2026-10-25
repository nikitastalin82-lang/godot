extends Node3D
## Расстановка множества одинаковых моделей (лес, бамбук, камни) через MultiMesh.
## Одна модель = один draw call на поверхность, а не по одному на каждое дерево.
## Коллизия (если нужна) — один StaticBody3D с тонкими цилиндрами под стволы.
## Узел нужно держать в начале координат: позиции задаются в локальных координатах.

@export var scene: PackedScene
## Имя узла внутри набора моделей. Пусто — берётся вся модель.
@export var piece_name: String = ""
## Прямоугольник на земле: x, z, ширина, глубина.
@export var area := Rect2(-50, -50, 100, 100)
## Зоны, где ничего не ставим (например, центр деревни).
@export var exclude: Array[Rect2] = []
@export var count := 10
@export var height_min := 6.0
@export var height_max := 9.0
@export var min_spacing := 3.0
@export var random_seed := 1
## 0 — без коллизии.
@export var collision_radius := 0.0
@export var collision_height := 3.0

var _parts: Array[Dictionary] = []
var _bounds := AABB()
var _has_bounds := false


func _ready() -> void:
	if scene == null:
		push_warning("Scatter '%s': не задана сцена." % name)
		return

	var instance := scene.instantiate()
	var root := instance as Node3D
	if root == null:
		instance.free()
		return
	if piece_name != "":
		var piece := instance.find_child(piece_name, true, false) as Node3D
		if piece == null:
			push_warning("Scatter '%s': в модели нет узла '%s'." % [name, piece_name])
			instance.free()
			return
		piece.get_parent().remove_child(piece)
		piece.owner = null
		instance.free()
		piece.transform = Transform3D.IDENTITY
		root = piece

	_collect(root, Transform3D.IDENTITY)
	root.free()
	if not _has_bounds or _bounds.size.y < 0.0001:
		push_warning("Scatter '%s': у модели нет геометрии." % name)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var centre := _bounds.get_center()
	var pivot_offset := Vector3(-centre.x, -_bounds.position.y, -centre.z)

	var spots: Array[Vector2] = []
	var transforms: Array[Transform3D] = []
	var attempts := 0
	while spots.size() < count and attempts < count * 40:
		attempts += 1
		var p := Vector2(
			rng.randf_range(area.position.x, area.end.x),
			rng.randf_range(area.position.y, area.end.y)
		)
		if _is_excluded(p) or _too_close(p, spots):
			continue
		spots.append(p)
		var height := rng.randf_range(height_min, height_max)
		var factor := height / _bounds.size.y
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3.ONE * factor)
		var placed := Transform3D(basis, Vector3(p.x, 0.0, p.y))
		transforms.append(placed * Transform3D(Basis.IDENTITY, pivot_offset))

	if transforms.is_empty():
		return

	var terrain := get_tree().get_first_node_in_group(&"terrain")
	if terrain != null:
		for i in transforms.size():
			var t: Transform3D = transforms[i]
			var world := global_position + Vector3(t.origin.x, 0.0, t.origin.z)
			t.origin.y += terrain.sample_height(world.x, world.z)
			transforms[i] = t

	for part in _parts:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part["mesh"]
		multimesh.instance_count = transforms.size()
		var local_xf: Transform3D = part["xf"]
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i] * local_xf)
		var instance_node := MultiMeshInstance3D.new()
		instance_node.multimesh = multimesh
		if part["material"] != null:
			instance_node.material_override = part["material"]
		add_child(instance_node)

	if collision_radius > 0.0:
		var shape := CylinderShape3D.new()
		shape.radius = collision_radius
		shape.height = collision_height
		var body := StaticBody3D.new()
		for i in spots.size():
			var p := spots[i]
			var ground_y := 0.0
			if terrain != null:
				ground_y = terrain.sample_height(global_position.x + p.x, global_position.z + p.y)
			var shape_node := CollisionShape3D.new()
			shape_node.shape = shape
			shape_node.position = Vector3(p.x, ground_y + collision_height * 0.5, p.y)
			body.add_child(shape_node)
		add_child(body)


func _collect(node: Node, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			_parts.append({"mesh": mesh_node.mesh, "xf": xf, "material": mesh_node.material_override})
			var box := xf * mesh_node.get_aabb()
			if _has_bounds:
				_bounds = _bounds.merge(box)
			else:
				_bounds = box
				_has_bounds = true
	for child in node.get_children():
		_collect(child, xf)


func _is_excluded(p: Vector2) -> bool:
	for rect in exclude:
		if rect.has_point(p):
			return true
	return false


func _too_close(p: Vector2, spots: Array[Vector2]) -> bool:
	var limit := min_spacing * min_spacing
	for other in spots:
		if p.distance_squared_to(other) < limit:
			return true
	return false
