extends Camera2D

# This camera is expected to be a CHILD of the car node.
# Because it's a child, it automatically inherits the car's rotation
# through the scene tree — so "freezing" the camera means actively
# CANCELING the car's rotation via this node's own local `rotation`,
# and "syncing" means letting that local rotation return to 0 so the
# inherited parent rotation shows through again.
#
# Everything here runs in _physics_process so it reads the car's
# rotation on the exact same tick the car updates it — mixing this
# with _process caused the detection to misfire, which is why the
# camera was just passively following before.

@export var target: Node2D

@export_group("Zoom")
@export var zoom_min: float = 1.4
@export var zoom_max: float = 0.85
@export var zoom_speed_reference: float = 600.0
@export var zoom_smoothing: float = 3.0

@export_group("Look-ahead")
@export var lookahead_max: float = 220.0
@export var lookahead_smoothing: float = 4.0
@export var lookahead_vertical_bias: float = 1.3

@export_group("Rotation Sync")
@export var rotation_sync_enabled: bool = true
@export var turn_threshold: float = 0.15 # rad/sec — above this counts as "turning"
@export var straight_hold_time: float = 0.25 # seconds of straight driving before syncing starts
@export var rotation_sync_speed: float = 3.0 # rad/sec — how fast rotation eases back once syncing

var _current_zoom: float = 1.0
var _current_lookahead: Vector2 = Vector2.ZERO

var _prev_car_rotation: float = 0.0
var _is_turning: bool = false
var _straight_timer: float = 0.0
var _locked_local_rotation: float = 0.0 # camera's local rotation, held constant while turning


func _ready() -> void:
	ignore_rotation = false # Camera2D ignores rotation by default in Godot 4 — must disable
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0

	_current_zoom = zoom_min
	zoom = Vector2(_current_zoom, _current_zoom)

	if target:
		_prev_car_rotation = target.rotation
	rotation = 0.0
	_locked_local_rotation = 0.0


func _physics_process(delta: float) -> void:
	if target == null or delta <= 0.0:
		return

	var car_velocity: Vector2 = _get_target_velocity()
	_update_zoom(car_velocity, delta)
	_update_lookahead(car_velocity, delta)

	if rotation_sync_enabled:
		_update_rotation_sync(delta)


func _get_target_velocity() -> Vector2:
	if target.has_method("get_velocity"):
		return target.get_velocity()
	elif "velocity" in target:
		return target.velocity
	return Vector2.ZERO


func _update_zoom(car_velocity: Vector2, delta: float) -> void:
	var speed_ratio: float = clamp(car_velocity.length() / zoom_speed_reference, 0.0, 1.0)
	var target_zoom: float = lerp(zoom_min, zoom_max, speed_ratio)
	_current_zoom = lerp(_current_zoom, target_zoom, clamp(zoom_smoothing * delta, 0.0, 1.0))
	zoom = Vector2(_current_zoom, _current_zoom)


func _update_lookahead(car_velocity: Vector2, delta: float) -> void:
	var speed: float = car_velocity.length()
	var speed_ratio: float = clamp(speed / zoom_speed_reference, 0.0, 1.0)
	var travel_dir: Vector2 = car_velocity.normalized() if speed > 10.0 else Vector2.ZERO

	var target_lookahead: Vector2 = travel_dir * lookahead_max * speed_ratio
	target_lookahead.y *= lookahead_vertical_bias

	_current_lookahead = _current_lookahead.lerp(target_lookahead, clamp(lookahead_smoothing * delta, 0.0, 1.0))
	offset = _current_lookahead


func _update_rotation_sync(delta: float) -> void:
	var car_rotation: float = target.rotation
	print("turning: ", _is_turning, " | rotation: ", rotation, " | car rotation: ", car_rotation)
	var delta_rotation: float = wrapf(car_rotation - _prev_car_rotation, -PI, PI)
	var angular_speed: float = abs(delta_rotation) / delta
	_prev_car_rotation = car_rotation

	var was_turning: bool = _is_turning
	_is_turning = angular_speed > turn_threshold

	if _is_turning:
		if not was_turning:
			# Turn just started this tick — lock the camera's current local rotation.
			_locked_local_rotation = rotation
		_straight_timer = 0.0
		# Actively cancel the car's rotation change so the camera's LOCAL rotation
		# stays pinned, which keeps the GLOBAL (visual) rotation frozen too.
		_locked_local_rotation -= delta_rotation
		rotation = _locked_local_rotation
	else:
		_straight_timer += delta
		if _straight_timer >= straight_hold_time:
			# Driving straight long enough — ease local rotation back to 0,
			# letting the inherited parent (car) rotation show through.
			rotation = lerp_angle(rotation, 0.0, clamp(rotation_sync_speed * delta, 0.0, 1.0))
		# else: still in the grace window, hold rotation exactly where it is (no change).
