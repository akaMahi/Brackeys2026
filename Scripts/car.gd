extends CharacterBody2D

# ── Endless-runner car: lane-based left/right movement (Subway Surfers
# style) instead of free steering. The car never turns — it only slides
# between a fixed set of lanes — and its forward speed is measured
# relative to an auto-scrolling camera. Speed up to pull ahead on screen,
# slow down to fall back, but drift too far past either edge of the
# camera's view and you die.
#
# ASSUMPTIONS (swap the math below if yours differ):
#   - The level scrolls vertically: `forward_direction` is Vector2.UP.
#   - Lanes run horizontally (perpendicular to scroll), spaced along X.
#   - This node's parent/road is positioned so lane 0..lane_count-1 line
#     up correctly — lane_to_x() below is relative to THIS node's start
#     position, not world (0,0).
#
# Wire up `camera` to your ScrollCamera (see scroll_camera.gd) so the
# car knows what "relative speed" and "off-screen" mean.

signal lane_changed(new_lane: int)
signal speed_changed(new_speed: float)
signal died

@export_group("Lanes")
@export var lane_count: int = 4 # how many lanes exist right now; call set_lane_count() to change mid-run (road narrows/widens)
@export var lane_width: float = 140.0
@export var lane_change_speed: float = 1400.0 # px/sec HARD CAP on lateral speed — keeps the ease below from ever feeling like a teleport on wide lanes
@export var lane_change_ease: float = 8.0 # how snappy the lerp toward the target lane is; higher = reaches the lane faster (this is what actually shapes the motion — lane_change_speed is just a safety cap)
@export var starting_lane: int = -1 # -1 = start in the middle lane
@export var lane_left_action: String = "lane_left"
@export var lane_right_action: String = "lane_right"

@export_group("Lane Change Feel")
@export var visual: Node2D # assign a CHILD node that holds your sprite (pivot at the car's center) — rotate this, never the CharacterBody2D itself, or the collision shape rotates with it
@export var lane_tilt_angle: float = 0.3 # radians the visual leans into a lane change, roughly 17°
@export var lane_tilt_lerp_speed: float = 10.0 # how quickly the tilt eases in/out

@export_group("Forward Speed")
@export var min_speed: float = 150.0
@export var max_speed: float = 1000.0
@export var starting_speed: float = 500.0
@export var accelerate_rate: float = 500.0 # px/sec^2 while holding accelerate
@export var brake_rate: float = 700.0 # px/sec^2 while holding brake
@export var coast_rate: float = 150.0 # px/sec^2 the speed drifts back toward the camera's pace with no input; 0 disables coasting
@export var accelerate_action: String = "accelerate"
@export var brake_action: String = "brake"

@export_group("Camera Boundary")
@export var camera: Camera2D # assign your ScrollCamera (scroll_camera.gd) here in the editor
@export var forward_direction: Vector2 = Vector2.UP # must match the camera's scroll direction
@export var kill_margin_ahead: float = 40.0 # world px past the camera's top edge before dying for outrunning it
@export var kill_margin_behind: float = 40.0 # world px past the camera's bottom edge before dying for falling behind

var current_lane: int
var current_speed: float

var _forward_dir: Vector2
var _target_x: float
var _lane_origin_x: float
var _is_dead: bool = false


func _ready() -> void:
	_forward_dir = forward_direction.normalized()
	_lane_origin_x = global_position.x
	current_lane = starting_lane if starting_lane >= 0 else lane_count / 2
	current_speed = starting_speed
	_target_x = _lane_to_x(current_lane)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_read_lane_input()
	_read_speed_input(delta)
	_move(delta)
	_check_camera_bounds()


# ── Lanes ──────────────────────────────────────────────────

func _read_lane_input() -> void:
	if Input.is_action_just_pressed(lane_left_action):
		change_lane(-1)
	elif Input.is_action_just_pressed(lane_right_action):
		change_lane(1)


func change_lane(lane_delta: int) -> void:
	var new_lane: int = clampi(current_lane + lane_delta, 0, lane_count - 1)
	if new_lane != current_lane:
		current_lane = new_lane
		_target_x = _lane_to_x(current_lane)
		lane_changed.emit(current_lane)


func set_lane_count(new_count: int) -> void:
	# Call this if the road's width changes mid-run. Clamps the car into
	# the new range instead of leaving it stranded off the road.
	lane_count = maxi(1, new_count)
	current_lane = clampi(current_lane, 0, lane_count - 1)
	_target_x = _lane_to_x(current_lane)


func _lane_to_x(lane_index: int) -> float:
	return _lane_origin_x + (lane_index - (lane_count - 1) / 2.0) * lane_width


# ── Forward speed ──────────────────────────────────────────

func _read_speed_input(delta: float) -> void:
	var previous_speed: float = current_speed

	if Input.is_action_pressed(accelerate_action):
		current_speed = move_toward(current_speed, max_speed, accelerate_rate * delta)
	elif Input.is_action_pressed(brake_action):
		current_speed = move_toward(current_speed, min_speed, brake_rate * delta)
	elif coast_rate > 0.0 and camera:
		current_speed = move_toward(current_speed, camera.scroll_speed, coast_rate * delta)

	if current_speed != previous_speed:
		speed_changed.emit(current_speed)


# ── Movement ───────────────────────────────────────────────

func _move(delta: float) -> void:
	# Sideways: ease toward the target lane (lerp, so it starts fast and
	# settles in smoothly) rather than sliding at a constant rate, with
	# lane_change_speed as a hard cap so it never looks instantaneous.
	var lateral_velocity: float = 0.0
	if delta > 0.0:
		var eased_x: float = lerpf(global_position.x, _target_x, clampf(lane_change_ease * delta, 0.0, 1.0))
		var max_step: float = lane_change_speed * delta
		eased_x = clampf(eased_x, global_position.x - max_step, global_position.x + max_step)
		lateral_velocity = (eased_x - global_position.x) / delta

	velocity = (_forward_dir * current_speed) + Vector2(lateral_velocity, 0.0)
	move_and_slide()
	_update_tilt(lateral_velocity, delta)


func _update_tilt(lateral_velocity: float, delta: float) -> void:
	# Leans the visual into the direction of the lane change, like a bike
	# or a car's nose dipping into a turn, then eases back to upright
	# once the lateral motion stops. Purely cosmetic — the body stays flat.
	if visual == null:
		return

	var lean_ratio: float = clampf(lateral_velocity / lane_change_speed, -1.0, 1.0)
	var target_rotation: float = lean_ratio * lane_tilt_angle
	visual.rotation = lerp_angle(visual.rotation, target_rotation, clampf(lane_tilt_lerp_speed * delta, 0.0, 1.0))


# ── Camera boundary / death ────────────────────────────────

func _check_camera_bounds() -> void:
	if camera == null:
		return

	# Signed distance of the car from the camera's center, along the
	# scroll axis. Positive = ahead of the camera, negative = behind it.
	var offset: float = (global_position - camera.global_position).dot(_forward_dir)
	var half_extent: float = _camera_half_extent_along_forward()

	if offset > half_extent + kill_margin_ahead:
		die() # outran the camera
	elif offset < - (half_extent + kill_margin_behind):
		die() # got left behind


func _camera_half_extent_along_forward() -> float:
	# Assumes forward_direction is vertical (UP/DOWN); use viewport width
	# and camera.zoom.x instead if your game scrolls horizontally.
	var viewport_size: Vector2 = get_viewport_rect().size
	return (viewport_size.y * 0.5) * camera.zoom.y


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	velocity = Vector2.ZERO
	died.emit()
	# Hook your game-over flow here (restart, ragdoll, particles, etc.)
	# left unimplemented since it depends on the rest of your game.