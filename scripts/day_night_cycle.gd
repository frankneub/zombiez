extends Node3D

@export var sun_path: NodePath = NodePath("../Sun")
@export var sun_visual_path: NodePath = NodePath("../SunVisual")
@export var star_field_path: NodePath = NodePath("../StarField")
@export var world_environment_path: NodePath = NodePath("../WorldEnvironment")
@export var daylight_duration_seconds: float = 300.0
@export var night_duration_seconds: float = 300.0
@export var day_sun_energy: float = 1.2
@export var night_sun_energy: float = 0.0
@export var day_ambient_energy: float = 0.5
@export var night_ambient_energy: float = 0.0
@export var sun_azimuth_degrees: float = -35.0

var sun: DirectionalLight3D = null
var sun_visual: MeshInstance3D = null
var star_field: MeshInstance3D = null
var world_environment: WorldEnvironment = null
var cycle_time: float = 0.0
var sky_material: ProceduralSkyMaterial = null
var star_instances: MultiMeshInstance3D = null
var star_material: StandardMaterial3D = null

func _ready() -> void:
	sun = get_node_or_null(sun_path) as DirectionalLight3D
	sun_visual = get_node_or_null(sun_visual_path) as MeshInstance3D
	star_field = get_node_or_null(star_field_path) as MeshInstance3D
	world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	setup_star_field_meshes()
	if world_environment != null and world_environment.environment != null:
		var sky: Sky = world_environment.environment.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			sky_material = sky.sky_material as ProceduralSkyMaterial
	# Start one minute before dawn (night-to-day transition).
	var total_duration: float = daylight_duration_seconds + night_duration_seconds
	cycle_time = maxf(daylight_duration_seconds, total_duration - 30.0)
	set_process(true)
	update_cycle(cycle_time)


func setup_star_field_meshes() -> void:
	if star_field == null:
		return

	star_material = StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_material.no_depth_test = true
	star_material.disable_fog = true
	star_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	star_material.albedo_color = Color(0.9, 0.95, 1.0, 1.0)
	star_material.emission_enabled = true
	star_material.emission = Color(0.9, 0.95, 1.0, 1.0)
	star_material.emission_energy_multiplier = 0.0

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)

	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.instance_count = 700
	multi_mesh.mesh = quad

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 987654321
	for i in multi_mesh.instance_count:
		var direction := Vector3.ZERO
		while direction.length_squared() < 0.001 or direction.y < -0.12:
			direction = Vector3(
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)
			).normalized()
		var distance: float = rng.randf_range(170.0, 230.0)
		var star_scale: float = rng.randf_range(0.35, 1.05)
		var star_transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * star_scale), direction * distance)
		multi_mesh.set_instance_transform(i, star_transform)

	star_instances = MultiMeshInstance3D.new()
	star_instances.name = "StarsMultiMesh"
	star_instances.multimesh = multi_mesh
	star_instances.material_override = star_material
	star_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_field.add_child(star_instances)


func _process(delta: float) -> void:
	cycle_time += delta
	update_cycle(cycle_time)


func update_cycle(elapsed: float) -> void:
	if not is_instance_valid(sun) or not is_instance_valid(world_environment):
		return
	if world_environment.environment == null:
		return

	var total_duration: float = daylight_duration_seconds + night_duration_seconds
	var local_time: float = fposmod(elapsed, total_duration)
	var is_daytime: bool = local_time < daylight_duration_seconds

	if is_daytime:
		var day_progress: float = local_time / daylight_duration_seconds
		var orbit_angle: float = lerpf(0.0, PI, day_progress)
		var sun_direction: Vector3 = apply_sun_orbit(orbit_angle)
		var height_factor: float = clampf(sun_direction.y, 0.0, 1.0)
		var sun_warmth: float = 1.0 - pow(height_factor, 0.6)
		var sunrise_color := Color(1.0, 0.64, 0.42, 1.0)
		var noon_color := Color(1.0, 0.97, 0.92, 1.0)
		sun.light_energy = lerpf(0.06, day_sun_energy, height_factor)
		sun.light_color = sunrise_color.lerp(noon_color, 1.0 - sun_warmth)
		world_environment.environment.ambient_light_energy = lerpf(0.04, day_ambient_energy, height_factor)
		world_environment.environment.background_energy_multiplier = lerpf(0.03, 1.0, height_factor)
		update_sun_visual(height_factor, sunrise_color.lerp(noon_color, 1.0 - sun_warmth), sun_direction)
		update_star_field(sun_direction.y, true)
		apply_sky_colors(height_factor, sun_warmth, false)
	else:
		var night_progress: float = (local_time - daylight_duration_seconds) / night_duration_seconds
		var orbit_angle: float = lerpf(PI, TAU, night_progress)
		var sun_direction: Vector3 = apply_sun_orbit(orbit_angle)
		sun.light_energy = night_sun_energy
		sun.light_color = Color(0.12, 0.16, 0.24, 1.0)
		world_environment.environment.ambient_light_energy = night_ambient_energy
		world_environment.environment.background_energy_multiplier = 0.0
		update_sun_visual(0.0, Color(0, 0, 0, 1), sun_direction)
		update_star_field(sun_direction.y, false)
		apply_sky_colors(0.0, 1.0, true)


func apply_sun_orbit(orbit_angle: float) -> Vector3:
	var azimuth_radians: float = deg_to_rad(sun_azimuth_degrees)
	var horizontal_x: float = cos(azimuth_radians)
	var horizontal_z: float = sin(azimuth_radians)
	var horizontal_scale: float = cos(orbit_angle)
	var direction := Vector3(horizontal_x * horizontal_scale, sin(orbit_angle), horizontal_z * horizontal_scale).normalized()
	sun.look_at(sun.global_position + direction, Vector3.UP)
	return direction


func update_sun_visual(height_factor: float, sun_color: Color, sun_direction: Vector3) -> void:
	if sun_visual == null:
		return

	# Hide the disc only once it goes below the horizon.
	if sun_direction.y <= 0.0:
		sun_visual.visible = false
		return

	sun_visual.visible = true
	sun_visual.global_position = sun_direction * 220.0
	var sun_scale: float = lerpf(0.8, 1.6, 1.0 - height_factor)
	sun_visual.scale = Vector3.ONE * sun_scale
	if sun_visual.material_override is StandardMaterial3D:
		var material := sun_visual.material_override as StandardMaterial3D
		material.albedo_color = sun_color
		material.emission = sun_color
		material.emission_energy_multiplier = lerpf(2.4, 5.0, 1.0 - height_factor)


func update_star_field(sun_elevation: float, is_daytime: bool) -> void:
	if star_field == null:
		return

	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if active_camera != null:
		star_field.global_position = active_camera.global_position
	var star_visibility: float = 0.0
	if is_daytime:
		# During daytime keep stars effectively off, with a tiny tail near horizon.
		star_visibility = clampf(pow(clampf(-sun_elevation, 0.0, 1.0), 1.5), 0.0, 0.15)
	else:
		# At night keep a visible baseline and ramp to full brightness as sun drops.
		star_visibility = 0.45 + 0.55 * clampf(pow(clampf(-sun_elevation, 0.0, 1.0), 0.55), 0.0, 1.0)
	star_field.visible = star_visibility > 0.01
	if star_material != null:
		var star_color: Color = star_material.albedo_color
		star_color.a = star_visibility
		star_material.albedo_color = star_color
		star_material.emission_energy_multiplier = lerpf(0.0, 6.0, star_visibility)


func apply_sky_colors(height_factor: float, sun_warmth: float, is_night: bool) -> void:
	if sky_material == null:
		return

	if is_night:
		sky_material.sky_top_color = Color(0.01, 0.02, 0.05, 1.0)
		sky_material.sky_horizon_color = Color(0.02, 0.03, 0.06, 1.0)
		sky_material.ground_horizon_color = Color(0.015, 0.015, 0.02, 1.0)
		sky_material.ground_bottom_color = Color(0.0, 0.0, 0.0, 1.0)
		return

	var dawn_top := Color(0.28, 0.42, 0.72, 1.0)
	var noon_top := Color(0.15, 0.5, 0.95, 1.0)
	var dawn_horizon := Color(1.0, 0.62, 0.36, 1.0)
	var noon_horizon := Color(0.72, 0.86, 1.0, 1.0)
	var ground_dawn := Color(0.26, 0.22, 0.2, 1.0)
	var ground_day := Color(0.34, 0.34, 0.38, 1.0)

	sky_material.sky_top_color = dawn_top.lerp(noon_top, height_factor)
	sky_material.sky_horizon_color = dawn_horizon.lerp(noon_horizon, 1.0 - sun_warmth)
	sky_material.ground_horizon_color = ground_dawn.lerp(ground_day, height_factor)
	sky_material.ground_bottom_color = Color(0.04, 0.04, 0.05, 1.0)
