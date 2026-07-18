extends Node3D

@export var zombie_scene: PackedScene
@export var enemies_root_path: NodePath = NodePath("../Enemies")
@export var spawn_points_path: NodePath = NodePath("../SpawnPoints")
@export var initial_delay: float = 4.0
@export var time_between_waves: float = 5.0
@export var first_wave_size: int = 4
@export var wave_growth: int = 2
@export var max_alive_zombies: int = 24

var enemies_root: Node3D = null
var spawn_points_root: Node3D = null
var spawn_points: Array[Marker3D] = []
var wave_index: int = 0
var next_wave_due_time: float = 0.0

func _ready() -> void:
	randomize()
	enemies_root = get_node_or_null(enemies_root_path) as Node3D
	spawn_points_root = get_node_or_null(spawn_points_path) as Node3D
	cache_spawn_points()
	next_wave_due_time = Time.get_unix_time_from_system() + initial_delay


func _process(_delta: float) -> void:
	if zombie_scene == null or enemies_root == null or spawn_points.is_empty():
		return

	var alive_count: int = count_alive_zombies()
	if alive_count > 0:
		return

	var now: float = Time.get_unix_time_from_system()
	if now < next_wave_due_time:
		return

	spawn_next_wave()
	wave_index += 1
	next_wave_due_time = now + time_between_waves


func cache_spawn_points() -> void:
	spawn_points.clear()
	if spawn_points_root == null:
		return

	for child in spawn_points_root.get_children():
		if child is Marker3D:
			spawn_points.append(child)


func count_alive_zombies() -> int:
	if enemies_root == null:
		return 0

	var count: int = 0
	for child in enemies_root.get_children():
		if child is CharacterBody3D:
			count += 1
	return count


func spawn_next_wave() -> void:
	var wave_size: int = first_wave_size + wave_index * wave_growth
	var alive_count: int = count_alive_zombies()
	var available_slots: int = maxi(max_alive_zombies - alive_count, 0)
	wave_size = mini(wave_size, available_slots)
	if wave_size <= 0:
		return

	for i in range(wave_size):
		var spawn_point: Marker3D = spawn_points[randi() % spawn_points.size()]
		spawn_zombie(spawn_point.global_position)


func spawn_zombie(world_position: Vector3) -> void:
	var spawned: Node = zombie_scene.instantiate()
	if not (spawned is CharacterBody3D):
		return

	var zombie := spawned as CharacterBody3D
	enemies_root.add_child(zombie)
	zombie.global_position = world_position
