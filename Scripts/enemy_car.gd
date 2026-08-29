extends CarBase
class_name EnemyCar

# Drives forward continuously at a constant speed.
# Periodically enters a homing phase and continuously re-aims toward
# the player's current position.
#
# When the enemy collides with ANY physical body (wall, player, or
# another enemy car), it stops moving for a configurable amount of
# time, then resumes its normal behavior.

@export var speed: float = 260.0
@export var traction: float = 6.0
@export var player_group: String = "player"

@export_group("Collision Stop")
@export var stop_after_collision: bool = true
@export var collision_stop_time: float = 1.0

@export_group("Homing")
@export var can_retarget: bool = true
@export var retarget_interval_min: float = 2.0
@export var retarget_interval_max: float = 5.0
@export var turn_speed: float = 2.5
@export var alignment_threshold: float = 0.05

var _player: Node2D = null
var _retarget_timer: float = 0.0
var _is_correcting: bool = false
var _target_rotation: float = 0.0
var _collision_stop_timer: float = 0.0


func _ready() -> void:
	group_tag = "enemy_car"
	car_ready()

	_player = get_tree().get_first_node_in_group(player_group)
	_queue_next_retarget()


func _physics_process(delta: float) -> void:
	# ---------------------------------------------------------
	# STOPPED AFTER COLLISION
	# ---------------------------------------------------------
	if _collision_stop_timer > 0.0:
		_collision_stop_timer -= delta

		# Completely stop movement while stunned.
		velocity = Vector2.ZERO

		# Still allow CarBase to handle invulnerability timers,
		# health, etc.
		car_physics_update(delta, 0.0)

		if _collision_stop_timer <= 0.0:
			_collision_stop_timer = 0.0
			_queue_next_retarget()

		return

	# ---------------------------------------------------------
	# NORMAL HOMING / RETARGETING
	# ---------------------------------------------------------
	if can_retarget:
		_update_retarget_timer(delta)

		if _is_correcting:
			_home_toward_player(delta)

	# ---------------------------------------------------------
	# NORMAL FORWARD MOVEMENT
	# ---------------------------------------------------------
	var desired_velocity: Vector2 = Vector2.UP.rotated(rotation) * speed

	velocity = velocity.lerp(
		desired_velocity,
		clamp(traction * delta, 0.0, 1.0)
	)

	var pre_move_speed: float = velocity.length()

	move_and_slide()

	# ---------------------------------------------------------
	# CHECK FOR COLLISION
	# ---------------------------------------------------------
	if stop_after_collision and get_slide_collision_count() > 0:
		_start_collision_stop()

	# Let CarBase handle damage, knockback, sound, etc.
	car_physics_update(delta, pre_move_speed)


func _start_collision_stop() -> void:
	_collision_stop_timer = collision_stop_time

	# Stop all movement immediately.
	velocity = Vector2.ZERO

	# Stop homing while stunned.
	_is_correcting = false

	# Reset retarget timer so it doesn't immediately start
	# homing again on the exact same frame it wakes up.
	_queue_next_retarget()


func _update_retarget_timer(delta: float) -> void:
	_retarget_timer -= delta

	if _retarget_timer <= 0.0 and not _is_correcting:
		_start_retarget()


func _start_retarget() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group)

	if _player == null:
		_queue_next_retarget()
		return

	_is_correcting = true


func _home_toward_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_is_correcting = false
		_queue_next_retarget()
		return

	var to_player: Vector2 = _player.global_position - global_position

	if to_player.length() > 1.0:
		# Continuously aim at the player's CURRENT position.
		_target_rotation = Vector2.UP.angle_to(to_player)

		rotation = rotate_toward(
			rotation,
			_target_rotation,
			turn_speed * delta
		)

		if abs(
			wrapf(_target_rotation - rotation, -PI, PI)
		) <= alignment_threshold:
			_is_correcting = false
			_queue_next_retarget()


func _queue_next_retarget() -> void:
	_retarget_timer = randf_range(
		retarget_interval_min,
		retarget_interval_max
	)
