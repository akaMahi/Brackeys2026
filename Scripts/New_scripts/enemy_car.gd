extends CharacterBody2D
class_name EnemyCar

# Drives forward in a straight line at a constant speed. Every so often
# (a randomized interval) it looks up the player car's CURRENT position
# and smoothly turns to aim at it — once aligned, it goes back to simply
# driving straight in whatever direction that left it facing. It does NOT
# continuously home in on the player; it's a periodic "course correction,"
# which gives it a straight-line-with-occasional-swerve feel rather than
# a heat-seeking one.
#
# Waypoint/path following can replace the "drive straight" part later
# without touching the retarget logic below.
#
# Self-registers into the "enemy_car" group on ready, so the player's
# collision-damage system picks it up automatically — no manual tagging
# needed. You DO still need to make sure this node's collision layer/mask
# actually makes it SOLID to the player's car (that's separate from
# groups) or move_and_slide will just let them pass through each other.

@export var speed: float = 260.0
@export var player_group: String = "player"

@export_group("Retargeting")
@export var can_retarget: bool = true # turn off for an enemy that only ever drives straight
@export var retarget_interval_min: float = 2.0 # seconds
@export var retarget_interval_max: float = 5.0 # seconds
@export var turn_speed: float = 2.5 # rad/sec while correcting course
@export var alignment_threshold: float = 0.05 # rad — how close counts as "aligned"

var _player: Node2D = null
var _retarget_timer: float = 0.0
var _is_correcting: bool = false
var _target_rotation: float = 0.0


func _ready() -> void:
	add_to_group("enemy_car")
	_player = get_tree().get_first_node_in_group(player_group)
	_queue_next_retarget()


func _physics_process(delta: float) -> void:
	if can_retarget:
		_update_retarget_timer(delta)
		if _is_correcting:
			_turn_toward_target(delta)

	velocity = Vector2.UP.rotated(rotation) * speed
	move_and_slide()


func _update_retarget_timer(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 and not _is_correcting:
		_start_retarget()


func _start_retarget() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(player_group)

	if _player == null:
		_queue_next_retarget()
		return

	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() < 1.0:
		_queue_next_retarget()
		return

	# Vector2.UP is "forward" at rotation 0 (same convention as the player's
	# car), so angle_to() gives exactly the rotation that points us at them.
	_target_rotation = Vector2.UP.angle_to(to_player)
	_is_correcting = true


func _turn_toward_target(delta: float) -> void:
	rotation = rotate_toward(rotation, _target_rotation, turn_speed * delta)
	if abs(wrapf(_target_rotation - rotation, -PI, PI)) <= alignment_threshold:
		_is_correcting = false
		_queue_next_retarget()


func _queue_next_retarget() -> void:
	_retarget_timer = randf_range(retarget_interval_min, retarget_interval_max)
