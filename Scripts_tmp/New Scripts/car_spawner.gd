extends Area2D
class_name CarSpawner

# Sits in the level doing nothing until the player's detection area
# reaches it. Once activated, spawns immediately, then keeps spawning
# at randomized intervals if continuous_spawning is on.
#
# SETUP:
# 1. Attach to an Area2D with a small CollisionShape2D.
# 2. Set this Area2D's collision mask to include the player's
#    detection area layer.
# 3. Assign a full scene (.tscn) to what_to_spawn.

@export var what_to_spawn: PackedScene
@export var player_detection_group: String = "player_detection"
@export var continuous_spawning: bool = true
@export var spawn_interval_min: float = 3.0
@export var spawn_interval_max: float = 8.0
@export var spawn_offset: Vector2 = Vector2.ZERO
@export var max_concurrent_spawns: int = -1


var _activated: bool = false
var _spawn_timer: float = 0.0
var _live_spawns: Array[Node] = []
var _spawn_queued: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if not _activated or not continuous_spawning:
		return

	_prune_live_spawns()

	_spawn_timer -= delta

	if _spawn_timer <= 0.0:
		_queue_spawn()
		_queue_next_spawn()


func _on_area_entered(area: Area2D) -> void:
	if _activated:
		return

	if not area.is_in_group(player_detection_group):
		return

	_activated = true

	# We are currently inside a physics query, so defer the spawn.
	_queue_spawn()

	if continuous_spawning:
		_queue_next_spawn()


func _queue_spawn() -> void:
	if _spawn_queued:
		return

	_spawn_queued = true
	call_deferred("_spawn")


func _spawn() -> void:
	_spawn_queued = false

	if not is_inside_tree():
		return

	if what_to_spawn == null:
		push_warning(
			"CarSpawner '%s' activated but has no what_to_spawn scene assigned."
			% name
		)
		return

	_prune_live_spawns()

	if max_concurrent_spawns >= 0:
		if _live_spawns.size() >= max_concurrent_spawns:
			return

	var instance := what_to_spawn.instantiate()

	if instance == null:
		push_warning("CarSpawner '%s' failed to instantiate what_to_spawn." % name)
		return

	get_tree().current_scene.add_child(instance)

	if instance is Node2D:
		instance.global_position = global_position + spawn_offset

	_live_spawns.append(instance)


func _queue_next_spawn() -> void:
	_spawn_timer = randf_range(
		spawn_interval_min,
		spawn_interval_max
	)


func _prune_live_spawns() -> void:
	_live_spawns = _live_spawns.filter(
		func(n): return is_instance_valid(n)
	)
