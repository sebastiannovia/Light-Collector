extends RefCounted

const TEXTURE_SIZE := 256

static var _radial_texture: GradientTexture2D


static func make_light(radius: float, tint: Color, intensity: float) -> PointLight2D:
	if not _radial_texture:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0, 0.22, 0.58, 1.0])
		falloff.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.78), Color(1.0, 1.0, 1.0, 0.23), Color(1.0, 1.0, 1.0, 0.0)])
		_radial_texture = GradientTexture2D.new()
		_radial_texture.width = TEXTURE_SIZE
		_radial_texture.height = TEXTURE_SIZE
		_radial_texture.gradient = falloff
		_radial_texture.fill = GradientTexture2D.FILL_RADIAL
		_radial_texture.fill_from = Vector2(0.5, 0.5)
		_radial_texture.fill_to = Vector2(1.0, 0.5)
	var light := PointLight2D.new()
	light.texture = _radial_texture
	light.texture_scale = radius * 2.0 / TEXTURE_SIZE
	light.color = tint
	light.energy = intensity
	return light
