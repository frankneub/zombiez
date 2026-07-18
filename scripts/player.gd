extends CharacterBody3D

const GUNSHOT_STREAM_PATH: String = "res://assets/audio/Gunshot.ogg"
const RELOAD_STREAM_PATH: String = "res://assets/audio/Reload.ogg"
const OUCH_STREAM_PATH: String = "res://assets/audio/Ouch.ogg"
const WALKING_STREAM_PATH: String = "res://assets/audio/Walking.ogg"

@export var move_speed: float = 8.0
@export var mouse_sensitivity: float = 0.0025
@export var jump_velocity: float = 6.0
@export var fire_rate: float = 8.0
@export var max_shoot_distance: float = 250.0
@export var bullet_visual_speed: float = 160.0
@export var max_health: float = 100.0
@export var magazine_size: int = 8
@export var reload_time: float = 1.1
@export var head_bob_frequency: float = 9.0
@export var head_bob_amount: float = 0.06
@export var weapon_sway_amount: float = 0.035
@export var flashlight_starts_on: bool = true
@export var max_energy: float = 100.0
@export var zombie_collision_energy_loss_percent: float = 10.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var gun_root: Node3D = $Head/Camera3D/GunRoot
@onready var muzzle: Marker3D = $Head/Camera3D/GunRoot/Muzzle
@onready var gun_shot_audio: AudioStreamPlayer3D = $Head/Camera3D/GunRoot/GunShotAudio
@onready var reload_audio: AudioStreamPlayer3D = $Head/Camera3D/GunRoot/ReloadAudio
@onready var ouch_audio: AudioStreamPlayer = $OuchAudio
@onready var walking_audio: AudioStreamPlayer = $WalkingAudio
@onready var damage_flash_rect: ColorRect = $DamageFlash/ColorRect
@onready var score_label: Label = $HUD/VBoxContainer/ScoreLabel
@onready var energy_label: Label = $HUD/VBoxContainer/EnergyLabel
@onready var energy_bar: ProgressBar = $HUD/VBoxContainer/EnergyBar
@onready var game_over_label: Label = $HUD/GameOverLabel

var pitch: float = 0.0
var next_shot_time_ms: int = 0
var current_health: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var current_ammo: int = 0
var is_reloading: bool = false
var bob_time: float = 0.0
var camera_rest_position: Vector3 = Vector3.ZERO
var gun_rest_position: Vector3 = Vector3.ZERO
var last_ouch_time_ms: int = -1000
var flashlight_enabled: bool = false
var score: int = 0
var current_energy: float = 0.0
var is_game_over: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	spawn_position = global_position
	current_health = max_health
	current_energy = max_energy
	score = 0
	is_game_over = false
	current_ammo = magazine_size
	camera_rest_position = camera.position
	gun_rest_position = gun_root.position
	if is_instance_valid(game_over_label):
		game_over_label.visible = false
	update_hud()
	flashlight_enabled = flashlight_starts_on
	if is_instance_valid(flashlight):
		flashlight.visible = flashlight_enabled
	var gunshot_stream: AudioStream = load_audio_stream(GUNSHOT_STREAM_PATH)
	var reload_stream: AudioStream = load_audio_stream(RELOAD_STREAM_PATH)
	var ouch_stream: AudioStream = load_audio_stream(OUCH_STREAM_PATH)
	var walking_stream: AudioStream = load_audio_stream(WALKING_STREAM_PATH)
	if is_instance_valid(gun_shot_audio):
		gun_shot_audio.stream = gunshot_stream
	if is_instance_valid(reload_audio):
		reload_audio.stream = reload_stream
	if is_instance_valid(ouch_audio):
		ouch_audio.stream = ouch_stream
	if is_instance_valid(walking_audio):
		walking_audio.stream = walking_stream
		if walking_audio.stream is AudioStreamOggVorbis:
			(walking_audio.stream as AudioStreamOggVorbis).loop = true


func load_audio_stream(path: String) -> AudioStream:
	var loaded_resource: Resource = load(path)
	if loaded_resource is AudioStream:
		return loaded_resource as AudioStream

	# Web export cannot always access packed resources via load_from_file.
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)

	return null


func apply_damage(amount: float, attacker_position: Vector3 = Vector3.ZERO) -> void:
	if is_game_over:
		return
	current_health = maxf(current_health - amount, 0.0)
	play_ouch_sound()
	play_damage_flash()

	# Quick hit reaction gives feedback when attacked.
	var hit_tween := create_tween()
	hit_tween.tween_property(camera, "fov", 73.0, 0.05)
	hit_tween.tween_property(camera, "fov", 75.0, 0.09)

	if current_health <= 0.0:
		respawn()


func play_ouch_sound() -> void:
	if not is_instance_valid(ouch_audio):
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - last_ouch_time_ms < 250:
		return
	last_ouch_time_ms = now_ms
	if ouch_audio.stream == null:
		ouch_audio.stream = load_audio_stream(OUCH_STREAM_PATH)
		if ouch_audio.stream == null:
			return
		
	ouch_audio.pitch_scale = randf_range(0.97, 1.03)
	ouch_audio.volume_db = -3.0
	ouch_audio.play()


func play_damage_flash() -> void:
	if not is_instance_valid(damage_flash_rect):
		return

	var flash_color: Color = damage_flash_rect.color
	flash_color.a = 0.0
	damage_flash_rect.color = flash_color

	var flash_tween := create_tween()
	flash_tween.tween_property(damage_flash_rect, "color:a", 0.26, 0.06)
	flash_tween.tween_property(damage_flash_rect, "color:a", 0.0, 0.18)


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	current_health = max_health


func _unhandled_input(event: InputEvent) -> void:
	if is_game_over:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		head.rotation.x = pitch
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		shoot()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		start_reload()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		toggle_flashlight()


func apply_zombie_collision_hit(attacker_position: Vector3 = Vector3.ZERO) -> void:
	if is_game_over:
		return

	current_energy = maxf(current_energy - zombie_collision_energy_loss_percent, 0.0)
	play_ouch_sound()
	play_damage_flash()
	update_hud()

	if current_energy <= 0.0:
		trigger_game_over()


func add_score(points: int) -> void:
	if points <= 0:
		return
	score += points
	update_hud()


func trigger_game_over() -> void:
	if is_game_over:
		return

	is_game_over = true
	velocity = Vector3.ZERO
	if is_instance_valid(game_over_label):
		game_over_label.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func update_hud() -> void:
	if is_instance_valid(score_label):
		score_label.text = "Score: %d" % score

	if is_instance_valid(energy_bar):
		energy_bar.max_value = max_energy
		energy_bar.value = current_energy

	if is_instance_valid(energy_label):
		var energy_percent: int = int(round((current_energy / maxf(max_energy, 0.001)) * 100.0))
		energy_label.text = "Energy: %d%%" % energy_percent


func toggle_flashlight() -> void:
	if not is_instance_valid(flashlight):
		return
	flashlight_enabled = not flashlight_enabled
	flashlight.visible = flashlight_enabled


func shoot() -> void:
	if is_game_over:
		return
	if is_reloading:
		return
	if current_ammo <= 0:
		start_reload()
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms < next_shot_time_ms:
		return
	next_shot_time_ms = now_ms + int(1000.0 / fire_rate)
	current_ammo -= 1

	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z * max_shoot_distance)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	var tracer_start := muzzle.global_position if is_instance_valid(muzzle) else from
	var tracer_end := to
	var did_hit := false
	var hit_normal := Vector3.UP
	if result:
		did_hit = true
		tracer_end = result.position
		hit_normal = result.normal
		var collider: Object = result.collider
		if collider != null and collider.has_method("apply_damage"):
			collider.call("apply_damage", 1.0, self)

	spawn_bullet_tracer(tracer_start, tracer_end, did_hit, hit_normal)
	play_shot_sound()

	apply_gun_recoil()

	if current_ammo <= 0:
		start_reload()


func start_reload() -> void:
	if is_reloading:
		return
	if current_ammo >= magazine_size:
		return

	is_reloading = true
	play_reload_sound()

	var reload_tween := create_tween()
	reload_tween.tween_property(gun_root, "rotation_degrees:z", -12.0, reload_time * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	reload_tween.tween_property(gun_root, "rotation_degrees:z", 0.0, reload_time * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	reload_tween.tween_callback(finish_reload)


func finish_reload() -> void:
	current_ammo = magazine_size
	is_reloading = false


func spawn_bullet_tracer(start_pos: Vector3, end_pos: Vector3, did_hit: bool, hit_normal: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var tracer_mesh := SphereMesh.new()
	tracer_mesh.radius = 0.026
	tracer_mesh.height = 0.052
	tracer.mesh = tracer_mesh

	var tracer_material := StandardMaterial3D.new()
	tracer_material.albedo_color = Color(1.0, 0.86, 0.52, 1.0)
	tracer_material.emission_enabled = true
	tracer_material.emission = Color(1.0, 0.72, 0.3, 1.0)
	tracer_material.emission_energy_multiplier = 1.8
	tracer.material_override = tracer_material

	tracer.global_position = start_pos
	get_tree().current_scene.add_child(tracer)

	var distance := start_pos.distance_to(end_pos)
	var travel_time: float = maxf(distance / bullet_visual_speed, 0.03)
	var tracer_tween := create_tween()
	tracer_tween.tween_property(tracer, "global_position", end_pos, travel_time).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tracer_tween.tween_callback(Callable(self, "_finish_bullet_tracer").bind(tracer, did_hit, end_pos, hit_normal))


func _finish_bullet_tracer(tracer: MeshInstance3D, did_hit: bool, hit_position: Vector3, hit_normal: Vector3) -> void:
	if is_instance_valid(tracer):
		tracer.queue_free()

	if did_hit:
		spawn_impact_marker(hit_position, hit_normal)


func play_shot_sound() -> void:
	if not is_instance_valid(gun_shot_audio):
		return
	if gun_shot_audio.stream == null:
		gun_shot_audio.stream = load_audio_stream(GUNSHOT_STREAM_PATH)
		if gun_shot_audio.stream == null:
			return
	gun_shot_audio.pitch_scale = randf_range(0.98, 1.03)
	gun_shot_audio.volume_db = -2.0
	gun_shot_audio.play()


func play_reload_sound() -> void:
	if not is_instance_valid(reload_audio):
		return
	if reload_audio.stream == null:
		reload_audio.stream = load_audio_stream(RELOAD_STREAM_PATH)
		if reload_audio.stream == null:
			return
	reload_audio.pitch_scale = randf_range(0.98, 1.02)
	reload_audio.volume_db = -4.0
	reload_audio.play()


func spawn_impact_marker(hit_position: Vector3, hit_normal: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.65, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.4, 1.0)
	material.emission_energy_multiplier = 0.7
	marker.material_override = material

	marker.global_position = hit_position + hit_normal * 0.03
	get_tree().current_scene.add_child(marker)

	var fade_tween := create_tween()
	fade_tween.tween_property(marker, "scale", Vector3.ZERO, 0.2)
	fade_tween.tween_callback(marker.queue_free)


func apply_gun_recoil() -> void:
	if not is_instance_valid(gun_root):
		return

	var rest_position: Vector3 = gun_rest_position
	gun_root.position = rest_position + Vector3(0.0, -0.01, 0.05)

	var recoil_tween := create_tween()
	recoil_tween.tween_property(gun_root, "position", rest_position, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func update_walking_motion(delta: float, move_dir: Vector3) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_walking: bool = is_on_floor() and horizontal_speed > 0.05 and move_dir.length_squared() > 0.0
	update_walking_sound(is_walking, horizontal_speed)

	if is_walking:
		bob_time += delta * head_bob_frequency * (horizontal_speed / move_speed)
	else:
		bob_time = lerpf(bob_time, 0.0, delta * 8.0)

	var bob_offset := Vector3.ZERO
	var sway_offset := Vector3.ZERO
	if is_walking:
		bob_offset.y = sin(bob_time) * head_bob_amount
		bob_offset.x = cos(bob_time * 0.5) * head_bob_amount * 0.55
		sway_offset.x = cos(bob_time * 0.5) * weapon_sway_amount
		sway_offset.y = abs(sin(bob_time)) * weapon_sway_amount * 0.35
		sway_offset.z = sin(bob_time) * weapon_sway_amount * 0.45

	camera.position = camera.position.lerp(camera_rest_position + bob_offset, clampf(delta * 12.0, 0.0, 1.0))
	if not is_reloading:
		gun_root.position = gun_root.position.lerp(gun_rest_position + sway_offset, clampf(delta * 10.0, 0.0, 1.0))


func update_walking_sound(is_walking: bool, horizontal_speed: float) -> void:
	if not is_instance_valid(walking_audio):
		return
	if walking_audio.stream == null:
		walking_audio.stream = load_audio_stream(WALKING_STREAM_PATH)
		if walking_audio.stream is AudioStreamOggVorbis:
			(walking_audio.stream as AudioStreamOggVorbis).loop = true
		if walking_audio.stream == null:
			return

	if is_walking:
		walking_audio.pitch_scale = lerpf(0.92, 1.08, clampf(horizontal_speed / move_speed, 0.0, 1.0))
		walking_audio.volume_db = lerpf(-14.0, -9.0, clampf(horizontal_speed / move_speed, 0.0, 1.0))
		if not walking_audio.playing:
			walking_audio.play()
	elif walking_audio.playing:
		walking_audio.stop()


func _physics_process(delta: float) -> void:
	if is_game_over:
		velocity = Vector3.ZERO
		return

	var move_dir := Vector3.ZERO
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x

	if Input.is_key_pressed(KEY_W):
		move_dir += forward
	if Input.is_key_pressed(KEY_S):
		move_dir -= forward
	if Input.is_key_pressed(KEY_A):
		move_dir -= right
	if Input.is_key_pressed(KEY_D):
		move_dir += right

	move_dir.y = 0.0
	if move_dir.length_squared() > 0.0:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed

	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
	elif not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	update_walking_motion(delta, move_dir)
	move_and_slide()
