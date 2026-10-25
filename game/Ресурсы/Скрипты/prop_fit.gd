extends Node3D
## Универсальная обёртка для моделей окружения.
## Берёт PackedScene (целую модель или один узел из набора моделей),
## подгоняет высоту, ставит основанием на землю и при необходимости
## добавляет коллизию. Все параметры настраиваются в инспекторе.

enum Collision { NONE, BOX, TRUNK, TRIMESH }

@export var scene: PackedScene
## Имя узла внутри набора моделей. Пусто — берётся вся модель целиком.
@export var piece_name: String = ""
## Нужная высота в метрах. 0 — оставить исходный масштаб.
@export var target_height: float = 0.0
## Поставить нижнюю точку модели на y = 0 и отцентрировать по x/z.
@export var ground_snap: bool = true
## NONE — без коллизии, BOX — по габаритам, TRUNK — тонкий цилиндр
## (для деревьев), TRIMESH — точная по мешу (для зданий).
@export var collision: Collision = Collision.NONE

var _bounds := AABB()
var _has_bounds := false


func _ready() -> void:
	if scene == null:
		push_warning("PropFit '%s': не задана сцена." % name)
		return

	var terrain := get_tree().get_first_node_in_group(&"terrain")
	if terrain != null:
		position.y += terrain.sample_height(global_position.x, global_position.z)

	var instance := scene.instantiate()
	var model := instance as Node3D
	if model == null:
		push_warning("PropFit '%s': корень сцены не Node3D." % name)
		instance.free()
		return

	if piece_name != "":
		var piece := instance.find_child(piece_name, true, false) as Node3D
		if piece == null:
			push_warning("PropFit '%s': в модели нет узла '%s'." % [name, piece_name])
			instance.free()
			return
		piece.get_parent().remove_child(piece)
		piece.owner = null
		instance.free()
		piece.transform = Transform3D.IDENTITY
		model = piece

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	pivot.add_child(model)

	_measure(model, Transform3D.IDENTITY)
	if not _has_bounds:
		return

	var factor := 1.0
	if target_height > 0.0 and _bounds.size.y > 0.0001:
		factor = target_height / _bounds.size.y
	pivot.scale = Vector3.ONE * factor
	if ground_snap:
		var c := _bounds.get_center()
		pivot.position = Vector3(-c.x, -_bounds.position.y, -c.z) * factor

	_apply_collision(model, pivot, factor)


func _measure(node: Node, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var b := xf * mi.get_aabb()
			if _has_bounds:
				_bounds = _bounds.merge(b)
			else:
				_bounds = b
				_has_bounds = true
	for child in node.get_children():
		_measure(child, xf)


func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, out)


func _apply_collision(model: Node3D, pivot: Node3D, factor: float) -> void:
	if collision == Collision.NONE:
		return

	if collision == Collision.TRIMESH:
		var meshes: Array[MeshInstance3D] = []
		_gather_meshes(model, meshes)
		for mi in meshes:
			mi.create_trimesh_collision()
		return

	var size := _bounds.size * factor
	var center := pivot.transform * _bounds.get_center()
	var shape_node := CollisionShape3D.new()
	if collision == Collision.TRUNK:
		var cyl := CylinderShape3D.new()
		cyl.radius = clampf(minf(size.x, size.z) * 0.04, 0.2, 0.5)
		cyl.height = size.y * 0.6
		shape_node.shape = cyl
		shape_node.position = Vector3(center.x, center.y - size.y * 0.5 + cyl.height * 0.5, center.z)
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		shape_node.position = center

	var body := StaticBody3D.new()
	body.add_child(shape_node)
	add_child(body)
