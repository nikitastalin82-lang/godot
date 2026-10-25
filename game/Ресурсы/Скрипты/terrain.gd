@tool
extends Node3D
## Процедурный рельеф: холмы по краям карты, ровная площадка под деревней
## и дорожками. Сетка строится один раз в _ready() — @tool оставлен специально,
## чтобы рельеф был виден и прямо в редакторе, а не только после нажатия Play
## (до этого земля была статичным боксом прямо в сцене, и была видна всегда).
## Other скрипты (PropFit, Scatter) находят этот узел через группу "terrain"
## и вызывают sample_height(world_x, world_z), чтобы класть объекты на рельеф,
## а не на условную высоту 0. Эти скрипты не @tool, поэтому дома/деревья
## появляются только по Play — это не баг, так было и до рельефа.

@export var size := Vector2(240.0, 240.0)
## Шаг сетки в метрах. Меньше — плавнее рельеф, но дороже построить и отрисовать.
@export var cell_size := 2.5
@export var height_amplitude := 8.0
@export var noise_scale := 0.025
@export var noise_seed := 1337
## Область деревни, которую нужно оставить ровной (как в outskirts.tscn: Rect2(-48,-52,96,62)).
@export var flat_area := Rect2(-50, -54, 100, 64)
## Ширина плавного перехода от ровной площадки к холмам, в метрах.
@export var flat_falloff := 18.0
## Оттенки, на которые умножается текстура земли (белый = без изменений).
## ground_color — холмы, path_color — утоптанная земля в деревне.
@export var ground_color := Color(1.0, 1.0, 1.0):
	set(value):
		ground_color = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild()
@export var path_color := Color(1.0, 0.9, 0.76):
	set(value):
		path_color = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild()
## Сколько метров занимает один повтор текстуры земли.
@export var texture_tile_size := 6.0
## Размер процедурной текстуры в пикселях (степень двойки, 128–512).
@export var texture_resolution := 256

var _cols: int
var _rows: int
var _heights := PackedFloat32Array()
var _noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group(&"terrain")
	if Engine.is_editor_hint() and get_child_count() > 0:
		# Уже построено раньше (сцена уже открыта в редакторе) — не дублируем.
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_cols = int(size.x / cell_size) + 1
	_rows = int(size.y / cell_size) + 1
	_noise.seed = noise_seed
	_noise.frequency = noise_scale
	_noise.fractal_octaves = 4
	_build_heights()
	_build_mesh()
	_build_collision()


## 0 у центра (деревня), 1 далеко за её пределами — плавный Hermite-переход,
## чтобы не было видимого шва между площадкой и холмами.
func _flatness(x: float, z: float) -> float:
	var dx := maxf(flat_area.position.x - x, x - flat_area.end.x)
	var dz := maxf(flat_area.position.y - z, z - flat_area.end.y)
	var dist := maxf(maxf(dx, dz), 0.0)
	if flat_falloff <= 0.0:
		return 1.0 if dist > 0.0 else 0.0
	return smoothstep(0.0, flat_falloff, dist)


func _height_at(x: float, z: float) -> float:
	var base := (_noise.get_noise_2d(x, z) * 0.5 + 0.5)
	# Добавляем мелкие детали для более интересного рельефа
	var detail := (_noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5) * 0.15
	var hill := (base + detail) * height_amplitude
	return hill * _flatness(x, z)


func _build_heights() -> void:
	_heights.resize(_cols * _rows)
	var half := size * 0.5
	for row in _rows:
		var z := -half.y + row * cell_size
		for col in _cols:
			var x := -half.x + col * cell_size
			_heights[row * _cols + col] = _height_at(x, z)


## Высота рельефа в мировых координатах (билинейная интерполяция по сетке).
func sample_height(world_x: float, world_z: float) -> float:
	var half := size * 0.5
	var gx := clampf((world_x + half.x) / cell_size, 0.0, float(_cols - 1))
	var gz := clampf((world_z + half.y) / cell_size, 0.0, float(_rows - 1))
	var x0 := int(gx)
	var z0 := int(gz)
	var x1 := mini(x0 + 1, _cols - 1)
	var z1 := mini(z0 + 1, _rows - 1)
	var fx := gx - x0
	var fz := gz - z0
	var h00 := _heights[z0 * _cols + x0]
	var h10 := _heights[z0 * _cols + x1]
	var h01 := _heights[z1 * _cols + x0]
	var h11 := _heights[z1 * _cols + x1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5

	for row in _rows:
		for col in _cols:
			var x := -half.x + col * cell_size
			var z := -half.y + row * cell_size
			var h := _heights[row * _cols + col]
			# Оттенок: утоптанная земля в деревне, чистая трава на холмах.
			st.set_color(path_color.lerp(ground_color, _flatness(x, z)))
			# UV считаем от мировых координат: масштаб текстуры одинаков
			# по всей карте и не зависит от шага сетки.
			st.set_uv(Vector2(x, z) / maxf(texture_tile_size, 0.1))
			st.add_vertex(Vector3(x, h, z))

	# Godot считает лицевой стороной грань с обходом вершин ПО ЧАСОВОЙ
	# стрелке (если смотреть на неё). Сверху (x вправо, z вниз по экрану)
	# порядок (i0, i1, i2) — по часовой, нормаль смотрит вверх. Раньше стоял
	# порядок (i0, i2, i1): земля была повёрнута наизнанку, при CULL_BACK её
	# не было видно сверху, а снизу — было.
	for row in _rows - 1:
		for col in _cols - 1:
			var i0 := row * _cols + col
			var i1 := i0 + 1
			var i2 := i0 + _cols
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)

	st.generate_normals()
	var mesh := st.commit()

	var material := StandardMaterial3D.new()
	material.albedo_texture = _make_ground_texture()
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 0.95
	material.metallic = 0.0
	material.metallic_specular = 0.15
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)


## Бесшовная текстура земли: крупные пятна травы и голой земли плюс мелкое
## зерно. Строится кодом, поэтому не требует внешних файлов.
func _make_ground_texture() -> ImageTexture:
	var pixels := clampi(texture_resolution, 64, 1024)

	var patches := FastNoiseLite.new()
	patches.seed = noise_seed
	patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patches.frequency = 0.012
	patches.fractal_octaves = 3

	var grain := FastNoiseLite.new()
	grain.seed = noise_seed + 7
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.12

	var patch_image := patches.get_seamless_image(pixels, pixels)
	var grain_image := grain.get_seamless_image(pixels, pixels)

	var grass_dark := Color(0.20, 0.34, 0.12)
	var grass_light := Color(0.38, 0.54, 0.21)
	var soil := Color(0.40, 0.31, 0.20)

	var image := Image.create(pixels, pixels, true, Image.FORMAT_RGB8)
	for y in pixels:
		for x in pixels:
			var patch := patch_image.get_pixel(x, y).r
			var detail := grain_image.get_pixel(x, y).r
			var colour := grass_dark.lerp(grass_light, patch)
			colour = colour.lerp(soil, clampf((0.35 - patch) * 2.0, 0.0, 0.5))
			colour *= 0.85 + 0.3 * detail
			image.set_pixel(x, y, Color(colour.r, colour.g, colour.b, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _cols
	shape.map_depth = _rows
	shape.map_data = _heights

	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	# HeightMapShape3D всегда с шагом 1 между точками, поэтому растягиваем
	# узел масштабом до реального шага сетки; сама форма уже отцентрована.
	shape_node.scale = Vector3(cell_size, 1.0, cell_size)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.add_child(shape_node)
	add_child(body)
