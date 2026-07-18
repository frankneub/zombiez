extends CharacterBody3D

@warning_ignore("unused_signal")
signal zombie_killed(points: int)

@export var max_health: float = 3.0
@export var move_speed: float = 2.25
@export var attack_range: float = 1.4
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 0.9
@export var aggro_range: float = 32.0
@export var kill_score: int = 100
@export var realistic_model_scene: PackedScene = preload("res://assets/models/zombie/RiggedFigure.glb")
@export var growl_stream: AudioStream = preload("res://assets/audio/Zombie Growl.ogg")
@export var growl_interval_min_ms: int = 900
@export var growl_interval_max_ms: int = 2600

@onready var body_mesh: MeshInstance3D = $Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var health: float = 0.0
var player: Node3D = null
var next_attack_time_ms: int = 0
var next_growl_time_ms: int = 0
var walk_cycle_time: float = 0.0
var realistic_model_root: Node3D = null
var hit_feedback_node: Node3D = null
var model_anim_player: AnimationPlayer = null
var anim_idle: StringName = &""
var anim_walk: StringName = &""
var anim_attack: StringName = &""
var anim_death: StringName = &""
var death_in_progress: bool = false

var arm_left_mesh: MeshInstance3D = null
var arm_right_mesh: MeshInstance3D = null
var arm_left_base_rotation: Vector3 = Vector3.ZERO
var arm_right_base_rotation: Vector3 = Vector3.ZERO
var arm_attack_tween: Tween = null

var growl_audio: AudioStreamPlayer3D = null
var fx_audio: AudioStreamPlayer3D = null

func _ready() -> void:
	health = max_health
	if not load_realistic_model():
		style_as_zombie()
		add_zombie_details()
		hit_feedback_node = body_mesh
	else:
		hit_feedback_node = realistic_model_root
	setup_model_animation()
	cache_animation_nodes()
	setup_audio_players()
	find_player()
	next_growl_time_ms = Time.get_ticks_msec() + randi_range(growl_interval_min_ms, growl_interval_max_ms)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		find_player()
		if not is_instance_valid(player):
			return

	var to_player: Vector3 = player.global_position - global_position
	var flat_to_player: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	var distance_to_player: float = flat_to_player.length()
	var is_chasing: bool = distance_to_player <= aggro_range

	if is_chasing and distance_to_player > attack_range:
		maybe_play_growl()
	if flat_to_player.length_squared() > 0.0001:
		var move_direction: Vector3 = flat_to_player.normalized()
		look_at(global_position + move_direction, Vector3.UP)
		if is_chasing:
			velocity.x = move_direction.x * move_speed
			velocity.z = move_direction.z * move_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	animate_walk(delta, is_chasing)
	update_animation_state(is_chasing, distance_to_player)

	if is_chasing and distance_to_player <= attack_range:
		attack_player()


func find_player() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var found_player := scene.get_node_or_null("Player")
	if found_player is Node3D:
		player = found_player


func attack_player() -> void:
	if not is_instance_valid(player):
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms < next_attack_time_ms:
		return
	next_attack_time_ms = now_ms + int(attack_cooldown * 1000.0)

	play_attack_animation()
	play_attack_sound()
	play_attack_growl()

	if player.has_method("apply_damage"):
		if player.has_method("apply_zombie_collision_hit"):
			player.call("apply_zombie_collision_hit", global_position)
		else:
			player.call("apply_damage", attack_damage, global_position)


func apply_damage(amount: float, attacker: Node = null) -> void:
	if death_in_progress:
		return
	health -= amount
	play_hit_sound()
	flash_on_hit()
	if health <= 0.0:
		die(attacker)


func style_as_zombie() -> void:
	if not is_instance_valid(body_mesh):
		return

	var torso_material := StandardMaterial3D.new()
	torso_material.albedo_color = Color(0.17, 0.18, 0.2, 1.0)
	torso_material.roughness = 0.86
	torso_material.metallic = 0.03
	body_mesh.material_override = torso_material
	body_mesh.scale = Vector3(0.92, 1.05, 0.88)
	body_mesh.position = Vector3(0.0, 0.92, 0.0)


func load_realistic_model() -> bool:
	if realistic_model_scene == null:
		return false

	var spawned: Node = realistic_model_scene.instantiate()
	if not (spawned is Node3D):
		return false

	realistic_model_root = spawned as Node3D
	realistic_model_root.name = "RealisticZombieModel"
	realistic_model_root.position = Vector3(0.0, 0.0, 0.0)
	realistic_model_root.scale = Vector3(1.0, 1.0, 1.0)
	add_child(realistic_model_root)

	if is_instance_valid(body_mesh):
		body_mesh.visible = false

	apply_decay_tint(realistic_model_root)
	return true


func apply_decay_tint(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var source_material: Material = mesh_node.get_active_material(0)
		if source_material is StandardMaterial3D:
			var styled_material: StandardMaterial3D = (source_material as StandardMaterial3D).duplicate()
			styled_material.albedo_color = styled_material.albedo_color.lerp(Color(0.42, 0.56, 0.4, 1.0), 0.34)
			styled_material.roughness = clampf(styled_material.roughness + 0.2, 0.0, 1.0)
			mesh_node.material_override = styled_material
		else:
			var fallback_material := StandardMaterial3D.new()
			fallback_material.albedo_color = Color(0.42, 0.56, 0.4, 1.0)
			fallback_material.roughness = 0.82
			fallback_material.metallic = 0.03
			mesh_node.material_override = fallback_material

	for child in node.get_children():
		apply_decay_tint(child)


func add_zombie_details() -> void:
	if get_node_or_null("Head") != null:
		return

	var skin_tint: float = randf_range(-0.05, 0.05)
	var skin_material := StandardMaterial3D.new()
	skin_material.albedo_color = Color(0.43 + skin_tint, 0.58 + skin_tint * 0.7, 0.36 + skin_tint * 0.5, 1.0)
	skin_material.roughness = 0.78
	skin_material.metallic = 0.01

	var cloth_material := StandardMaterial3D.new()
	cloth_material.albedo_color = Color(0.12, 0.13, 0.15, 1.0)
	cloth_material.roughness = 0.9

	var dirty_cloth_material := StandardMaterial3D.new()
	dirty_cloth_material.albedo_color = Color(0.2, 0.2, 0.16, 1.0)
	dirty_cloth_material.roughness = 0.92

	var wound_material := StandardMaterial3D.new()
	wound_material.albedo_color = Color(0.25, 0.05, 0.05, 1.0)
	wound_material.roughness = 0.58

	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(0.82, 0.84, 0.74, 1.0)
	eye_material.roughness = 0.2

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.67, -0.03)
	head.material_override = skin_material
	add_child(head)

	var jaw := MeshInstance3D.new()
	jaw.name = "Jaw"
	var jaw_mesh := BoxMesh.new()
	jaw_mesh.size = Vector3(0.22, 0.09, 0.17)
	jaw.mesh = jaw_mesh
	jaw.position = Vector3(0.0, 1.52, -0.08)
	jaw.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	jaw.material_override = skin_material
	add_child(jaw)

	var eye_left := MeshInstance3D.new()
	eye_left.name = "EyeLeft"
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.03
	eye_left.mesh = eye_mesh
	eye_left.position = Vector3(-0.07, 1.7, -0.2)
	eye_left.material_override = eye_material
	add_child(eye_left)

	var eye_right := MeshInstance3D.new()
	eye_right.name = "EyeRight"
	eye_right.mesh = eye_mesh
	eye_right.position = Vector3(0.07, 1.7, -0.2)
	eye_right.material_override = eye_material
	add_child(eye_right)

	var neck := MeshInstance3D.new()
	neck.name = "Neck"
	var neck_mesh := BoxMesh.new()
	neck_mesh.size = Vector3(0.12, 0.1, 0.12)
	neck.mesh = neck_mesh
	neck.position = Vector3(0.0, 1.49, -0.02)
	neck.material_override = skin_material
	add_child(neck)

	var arm_upper_mesh := BoxMesh.new()
	arm_upper_mesh.size = Vector3(0.11, 0.34, 0.12)
	var arm_fore_mesh := BoxMesh.new()
	arm_fore_mesh.size = Vector3(0.1, 0.3, 0.11)

	var arm_left := MeshInstance3D.new()
	arm_left.name = "ArmLeft"
	arm_left.mesh = arm_upper_mesh
	arm_left.position = Vector3(-0.28, 1.27, -0.05)
	arm_left.rotation_degrees = Vector3(34.0, 0.0, -17.0)
	arm_left.material_override = skin_material
	add_child(arm_left)

	var forearm_left := MeshInstance3D.new()
	forearm_left.name = "ForearmLeft"
	forearm_left.mesh = arm_fore_mesh
	forearm_left.position = Vector3(-0.3, 1.0, -0.13)
	forearm_left.rotation_degrees = Vector3(45.0, 0.0, -12.0)
	forearm_left.material_override = skin_material
	add_child(forearm_left)

	var arm_right := MeshInstance3D.new()
	arm_right.name = "ArmRight"
	arm_right.mesh = arm_upper_mesh
	arm_right.position = Vector3(0.28, 1.27, -0.05)
	arm_right.rotation_degrees = Vector3(34.0, 0.0, 17.0)
	arm_right.material_override = skin_material
	add_child(arm_right)

	var forearm_right := MeshInstance3D.new()
	forearm_right.name = "ForearmRight"
	forearm_right.mesh = arm_fore_mesh
	forearm_right.position = Vector3(0.3, 1.0, -0.13)
	forearm_right.rotation_degrees = Vector3(45.0, 0.0, 12.0)
	forearm_right.material_override = skin_material
	add_child(forearm_right)

	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.16, 0.52, 0.16)
	var shin_mesh := BoxMesh.new()
	shin_mesh.size = Vector3(0.15, 0.44, 0.14)

	var leg_left := MeshInstance3D.new()
	leg_left.name = "LegLeft"
	leg_left.mesh = leg_mesh
	leg_left.position = Vector3(-0.16, 0.48, 0.0)
	leg_left.material_override = dirty_cloth_material
	add_child(leg_left)

	var shin_left := MeshInstance3D.new()
	shin_left.name = "ShinLeft"
	shin_left.mesh = shin_mesh
	shin_left.position = Vector3(-0.16, 0.08, 0.03)
	shin_left.material_override = dirty_cloth_material
	add_child(shin_left)

	var leg_right := MeshInstance3D.new()
	leg_right.name = "LegRight"
	leg_right.mesh = leg_mesh
	leg_right.position = Vector3(0.16, 0.48, 0.0)
	leg_right.material_override = dirty_cloth_material
	add_child(leg_right)

	var shin_right := MeshInstance3D.new()
	shin_right.name = "ShinRight"
	shin_right.mesh = shin_mesh
	shin_right.position = Vector3(0.16, 0.08, 0.03)
	shin_right.material_override = dirty_cloth_material
	add_child(shin_right)

	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.17, 0.08, 0.29)
	var foot_left := MeshInstance3D.new()
	foot_left.name = "FootLeft"
	foot_left.mesh = foot_mesh
	foot_left.position = Vector3(-0.16, -0.15, -0.07)
	foot_left.material_override = cloth_material
	add_child(foot_left)

	var foot_right := MeshInstance3D.new()
	foot_right.name = "FootRight"
	foot_right.mesh = foot_mesh
	foot_right.position = Vector3(0.16, -0.15, -0.07)
	foot_right.material_override = cloth_material
	add_child(foot_right)

	var torso_cloth := MeshInstance3D.new()
	torso_cloth.name = "TorsoCloth"
	var cloth_mesh := BoxMesh.new()
	cloth_mesh.size = Vector3(0.6, 0.72, 0.34)
	torso_cloth.mesh = cloth_mesh
	torso_cloth.position = Vector3(0.0, 1.0, 0.01)
	torso_cloth.material_override = cloth_material
	add_child(torso_cloth)

	var wound_patch := MeshInstance3D.new()
	wound_patch.name = "WoundPatch"
	var wound_mesh := BoxMesh.new()
	wound_mesh.size = Vector3(0.14, 0.1, 0.03)
	wound_patch.mesh = wound_mesh
	wound_patch.position = Vector3(0.19, 1.09, -0.17)
	wound_patch.material_override = wound_material
	add_child(wound_patch)


func cache_animation_nodes() -> void:
	if model_anim_player != null:
		return

	var left_node := get_node_or_null("ArmLeft")
	if left_node is MeshInstance3D:
		arm_left_mesh = left_node
		arm_left_base_rotation = arm_left_mesh.rotation_degrees

	var right_node := get_node_or_null("ArmRight")
	if right_node is MeshInstance3D:
		arm_right_mesh = right_node
		arm_right_base_rotation = arm_right_mesh.rotation_degrees


func animate_walk(delta: float, is_chasing: bool) -> void:
	if model_anim_player != null:
		return

	if not is_instance_valid(arm_left_mesh) or not is_instance_valid(arm_right_mesh):
		return

	var move_amount: float = velocity.length()
	if is_chasing and move_amount > 0.01:
		walk_cycle_time += delta * 7.0
		var swing: float = sin(walk_cycle_time) * 18.0
		arm_left_mesh.rotation_degrees.x = arm_left_base_rotation.x + swing
		arm_right_mesh.rotation_degrees.x = arm_right_base_rotation.x - swing
	else:
		walk_cycle_time += delta * 2.5
		var idle_sway: float = sin(walk_cycle_time) * 4.0
		arm_left_mesh.rotation_degrees.x = arm_left_base_rotation.x + idle_sway
		arm_right_mesh.rotation_degrees.x = arm_right_base_rotation.x - idle_sway


func play_attack_animation() -> void:
	if model_anim_player != null and anim_attack != &"":
		model_anim_player.play(String(anim_attack), 0.06, 1.15)
		return

	if not is_instance_valid(arm_left_mesh) or not is_instance_valid(arm_right_mesh):
		return

	if arm_attack_tween != null:
		arm_attack_tween.kill()

	arm_attack_tween = create_tween()
	arm_attack_tween.tween_property(arm_left_mesh, "rotation_degrees:x", arm_left_base_rotation.x + 58.0, 0.08)
	arm_attack_tween.parallel().tween_property(arm_right_mesh, "rotation_degrees:x", arm_right_base_rotation.x + 58.0, 0.08)
	arm_attack_tween.tween_property(arm_left_mesh, "rotation_degrees:x", arm_left_base_rotation.x, 0.12)
	arm_attack_tween.parallel().tween_property(arm_right_mesh, "rotation_degrees:x", arm_right_base_rotation.x, 0.12)


func setup_audio_players() -> void:
	growl_audio = AudioStreamPlayer3D.new()
	growl_audio.name = "GrowlAudio"
	growl_audio.unit_size = 5.5
	growl_audio.max_distance = 50.0
	growl_audio.pitch_scale = 0.62
	growl_audio.stream = growl_stream
	add_child(growl_audio)

	fx_audio = AudioStreamPlayer3D.new()
	fx_audio.name = "ZombieFxAudio"
	fx_audio.unit_size = 4.5
	fx_audio.max_distance = 38.0
	add_child(fx_audio)


func maybe_play_growl() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms < next_growl_time_ms:
		return

	next_growl_time_ms = now_ms + randi_range(growl_interval_min_ms, growl_interval_max_ms)
	play_zombie_growl(0.72, false)


func play_attack_growl() -> void:
	play_zombie_growl(1.0, true)


func play_zombie_growl(intensity: float, short_burst: bool) -> void:
	if play_external_growl(intensity, short_burst):
		return

	if not is_instance_valid(growl_audio):
		return

	var clamped_intensity: float = clampf(intensity, 0.25, 1.25)
	var duration: float = 0.3 if short_burst else 0.62

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 32000.0
	stream.buffer_length = duration + 0.05
	growl_audio.stream = stream
	growl_audio.play()

	var playback := growl_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	var sample_count: int = int(stream.mix_rate * duration)
	for i in range(sample_count):
		var t: float = float(i) / stream.mix_rate
		var progress: float = t / duration
		var envelope: float = pow(1.0 - progress, 1.25)

		var base_freq: float = lerpf(82.0, 48.0, progress)
		var vibrato: float = sin(TAU * 5.6 * t) * 4.2
		var base: float = sin(TAU * (base_freq + vibrato) * t)
		var sub: float = sin(TAU * (base_freq * 0.52) * t)
		var rasp_carrier: float = sin(TAU * (base_freq * 3.7) * t)
		var rasp: float = sign(rasp_carrier) * 0.42
		var noise: float = randf_range(-1.0, 1.0) * (0.22 + 0.16 * clamped_intensity)

		var raw: float = (base * 0.58) + (sub * 0.34) + (rasp * 0.24) + noise
		var driven: float = tanh(raw * (1.7 + clamped_intensity * 0.45))
		var sample: float = clampf(driven * envelope * (0.58 + clamped_intensity * 0.2), -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))


func play_external_growl(intensity: float, short_burst: bool) -> bool:
	if not is_instance_valid(growl_audio):
		return false
	if growl_stream == null:
		return false

	growl_audio.stream = growl_stream
	growl_audio.pitch_scale = randf_range(0.82, 0.96) - (0.06 if short_burst else 0.0)
	var length: float = growl_stream.get_length()
	var window: float = 0.85 if short_burst else 1.8
	var start_max: float = maxf(length - window, 0.0)
	var start_time: float = randf_range(0.0, start_max) if start_max > 0.0 else 0.0
	growl_audio.volume_db = lerpf(-3.0, 1.5, clampf(intensity, 0.0, 1.0))
	growl_audio.play(start_time)

	var stop_timer := get_tree().create_timer(window)
	stop_timer.timeout.connect(func() -> void:
		if is_instance_valid(growl_audio) and growl_audio.playing:
			growl_audio.stop()
	)
	return true


func play_attack_sound() -> void:
	play_synth_sound(fx_audio, 0.15, 145.0, 34.0, 0.22, 0.52)


func play_hit_sound() -> void:
	play_synth_sound(fx_audio, 0.11, 180.0, 45.0, 0.18, 0.45)


func play_death_sound() -> void:
	play_synth_sound(fx_audio, 0.28, 72.0, 18.0, 0.3, 0.5)


func play_synth_sound(
	audio_player: AudioStreamPlayer3D,
	duration: float,
	base_frequency: float,
	wobble_frequency: float,
	noise_amount: float,
	gain: float
) -> void:
	if not is_instance_valid(audio_player):
		return

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 32000.0
	stream.buffer_length = maxf(duration + 0.03, 0.08)
	audio_player.stream = stream
	audio_player.play()

	var playback := audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	var sample_count: int = int(stream.mix_rate * duration)
	for i in range(sample_count):
		var t: float = float(i) / stream.mix_rate
		var envelope: float = exp(-9.5 * t)
		var wobble: float = sin(TAU * wobble_frequency * t) * 0.35
		var tone: float = sin(TAU * (base_frequency + wobble) * t)
		var noise: float = randf_range(-1.0, 1.0) * noise_amount
		var sample: float = clampf((tone * 0.72 + noise) * envelope * gain, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))


func flash_on_hit() -> void:
	var visual_target: Node3D = hit_feedback_node
	if not is_instance_valid(visual_target):
		if is_instance_valid(body_mesh):
			visual_target = body_mesh
		else:
			return

	var original_scale: Vector3 = visual_target.scale
	visual_target.scale = original_scale * Vector3(1.04, 1.04, 1.04)
	var hit_tween := create_tween()
	hit_tween.tween_property(visual_target, "scale", original_scale, 0.08)


func die(attacker: Node = null) -> void:
	if death_in_progress:
		return
	death_in_progress = true
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true
	set_collision_layer(0)
	set_collision_mask(0)
	emit_signal("zombie_killed", kill_score)
	if attacker != null and attacker.has_method("add_score"):
		attacker.call("add_score", kill_score)

	set_physics_process(false)
	play_death_sound()

	if model_anim_player != null and anim_death != &"":
		model_anim_player.play(String(anim_death), 0.05, 1.0)
		var death_length: float = 0.6
		var death_anim: Animation = model_anim_player.get_animation(String(anim_death))
		if death_anim != null:
			death_length = maxf(death_anim.length, 0.35)
		var cleanup_timer := get_tree().create_timer(death_length + 0.05)
		cleanup_timer.timeout.connect(queue_free)
		return

	var death_tween := create_tween()
	death_tween.tween_property(self, "scale", Vector3.ZERO, 0.28)
	death_tween.tween_callback(queue_free)


func setup_model_animation() -> void:
	if not is_instance_valid(realistic_model_root):
		return

	model_anim_player = find_animation_player(realistic_model_root)
	if model_anim_player == null:
		return

	var animation_names: PackedStringArray = model_anim_player.get_animation_list()
	anim_idle = find_animation_by_keywords(animation_names, ["idle", "stand", "breath"])
	anim_walk = find_animation_by_keywords(animation_names, ["walk", "run", "move"])
	anim_attack = find_animation_by_keywords(animation_names, ["attack", "hit", "melee", "punch"])
	anim_death = find_animation_by_keywords(animation_names, ["death", "die", "dead", "fall"])

	if anim_idle == &"" and animation_names.size() > 0:
		anim_idle = StringName(animation_names[0])

	if anim_walk == &"":
		anim_walk = anim_idle

	if anim_idle != &"":
		model_anim_player.play(String(anim_idle), 0.1, 1.0)


func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found

	return null


func find_animation_by_keywords(animation_names: PackedStringArray, keywords: Array[String]) -> StringName:
	for animation_name in animation_names:
		var lower_name: String = String(animation_name).to_lower()
		for keyword in keywords:
			if lower_name.contains(keyword):
				return StringName(animation_name)

	return &""


func update_animation_state(is_chasing: bool, distance_to_player: float) -> void:
	if model_anim_player == null:
		return

	if death_in_progress:
		return

	if is_chasing and distance_to_player <= attack_range and anim_attack != &"":
		return

	if is_chasing and velocity.length() > 0.08 and anim_walk != &"":
		if model_anim_player.current_animation != String(anim_walk):
			model_anim_player.play(String(anim_walk), 0.15, 1.0)
	elif anim_idle != &"":
		if model_anim_player.current_animation != String(anim_idle):
			model_anim_player.play(String(anim_idle), 0.2, 1.0)
