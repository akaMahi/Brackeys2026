extends Camera2D

# ── FIXED CAMERA BOXES, WITH FOLLOW-INSIDE-THE-BOX ────────
# The level is divided into "camera box" regions (Area2D nodes running
# camera_box.gd). Whichever box the car is currently inside defines this
# camera's home turf:
#   - The moment the car crosses into a DIFFERENT box, the camera
#     INSTANTLY snaps to that box's center — no smoothing, no lerping.
#   - WHILE inside a box, the camera smoothly follows the car, but its
#     position is clamped so it never shows anything outside that box's
#     bounds. If the box is smaller than what's currently visible on
#     screen (at the current zoom), the camera just holds at the box's
#     center on that axis instead of jittering at the clamp limit.
#
# Zoom reacts continuously to the car's speed. Named explicitly by speed
# rather than "close/far" so the direction can never get ambiguous again:
#   zoom_at_low_speed  → applies when the car is slow/stopped
#   zoom_at_high_speed → applies when the car is at max speed
# Remember Godot's Camera2D convention: zoom < 1.0 = zoomed IN, zoom >
# 1.0 = zoomed OUT (opposite of how a real camera lens is described).
#
# On top of the speed-based zoom, rotation and zoom get a reactive
# "kick" while the car is drifting.
#
# IMPORTANT — this camera is expected to be a SIBLING of the car (e.g.
# directly under your level/world root), NOT a child of it.

@export var target: Node2D

@export_group("Camera Boxes")
@export var camera_box_group: String = "camera_box" # boxes must be in this group
@export var start_at_first_box: bool = true # snap to whichever box the car starts inside
@export var follow_smoothing: float = 5.0 # how quickly the camera catches up to the car inside a box

@export_group("Zoom")
@export var zoom_at_low_speed: float = 1.4   # zoom while SLOW/STOPPED (larger number = zoomed OUT)
@export var zoom_at_high_speed: float = 0.85 # zoom while at MAX SPEED (smaller number = zoomed IN)
@export var zoom_speed_reference: float = 600.0
@export var zoom_smoothing: float = 3.0
@export var zoom_hard_min: float = 0.4 # safety floor so the drift kick can't zoom in too far

@export_group("Drift Reaction")
@export var drift_zoom_kick: float = 0.15      # extra zoom-in applied while drifting
@export var drift_rotation_follow: float = 0.5 # 0 = camera ignores the car's turn, 1 = matches it fully
@export var drift_rotation_smoothing: float = 6.0
@export var drift_recover_smoothing: float = 4.0

var _current_zoom: float = 1.0
var _current_box: Node2D = null

var _drift_start_car_rotation: float = 0.0
var _was_drifting: bool = false


func _ready() -> void:
	position_smoothing_enabled = false # we do our own clamped smoothing in _update_camera_position
	ignore_rotation = false            # must be false or our own rotation never reaches the screen

	_current_zoom = zoom_at_low_speed
	zoom = Vector2(_current_zoom, _current_zoom)
	rotation = 0.0

	for box in get_tree().get_nodes_in_group(camera_box_group):
		if box.has_signal("player_entered"):
			box.player_entered.connect(_on_camera_box_entered)

	if start_at_first_box:
		await get_tree().physics_frame # give physics one tick to register starting overlaps
		_snap_to_starting_box()


func _physics_process(delta: float) -> void:
	if target == null or delta <= 0.0:
		return

	var car_velocity: Vector2 = _get_target_velocity()
	var is_drifting: bool = _get_target_drifting()

	_update_zoom(car_velocity, is_drifting, delta)
	_update_drift_rotation(is_drifting, delta)
	_update_camera_position(delta)


func _get_target_velocity() -> Vector2:
	if target.has_method("get_velocity"):
		return target.get_velocity()
	elif "velocity" in target:
		return target.velocity
	return Vector2.ZERO


func _get_target_drifting() -> bool:
	if "is_drifting" in target:
		return target.is_drifting
	return false


# ── Camera boxes ──────────────────────────────────────────

func _snap_to_starting_box() -> void:
	if target == null:
		return
	for box in get_tree().get_nodes_in_group(camera_box_group):
		if box.has_method("get_overlapping_bodies") and target in box.get_overlapping_bodies():
			_snap_to_box(box)
			return


func _on_camera_box_entered(box: Node2D) -> void:
	_snap_to_box(box)


func _snap_to_box(box: Node2D) -> void:
	if box == null:
		return
	_current_box = box
	global_position = box.global_position # instant teleport — only happens when switching boxes


func _update_camera_position(delta: float) -> void:
	if _current_box == null:
		return

	var bounds: Rect2 = _current_box.get_bounds() if _current_box.has_method("get_bounds") \
		else Rect2(_current_box.global_position, Vector2.ZERO)

	var visible_half_extent: Vector2 = (get_viewport_rect().size / _current_zoom) * 0.5
	var min_pos: Vector2 = bounds.position + visible_half_extent
	var max_pos: Vector2 = bounds.position + bounds.size - visible_half_extent
	var box_center: Vector2 = bounds.position + bounds.size * 0.5

	var desired: Vector2 = target.global_position
	var clamped: Vector2 = Vector2(
		_clamp_or_center(desired.x, min_pos.x, max_pos.x, box_center.x),
		_clamp_or_center(desired.y, min_pos.y, max_pos.y, box_center.y)
	)

	global_position = global_position.lerp(clamped, clamp(follow_smoothing * delta, 0.0, 1.0))


func _clamp_or_center(value: float, lo: float, hi: float, center_fallback: float) -> float:
	if lo > hi:
		return center_fallback # box is smaller than the current view on this axis — just hold center
	return clamp(value, lo, hi)


# ── Zoom ──────────────────────────────────────────────────

func _update_zoom(car_velocity: Vector2, is_drifting: bool, delta: float) -> void:
	var speed_ratio: float = clamp(car_velocity.length() / zoom_speed_reference, 0.0, 1.0)
	var target_zoom: float = lerp(zoom_at_low_speed, zoom_at_high_speed, speed_ratio)

	if is_drifting:
		target_zoom -= drift_zoom_kick

	var zoom_ceiling: float = max(zoom_at_low_speed, zoom_at_high_speed)
	target_zoom = clamp(target_zoom, zoom_hard_min, zoom_ceiling)
	_current_zoom = lerp(_current_zoom, target_zoom, clamp(zoom_smoothing * delta, 0.0, 1.0))
	zoom = Vector2(_current_zoom, _current_zoom)


# ── Drift rotation kick ───────────────────────────────────

func _update_drift_rotation(is_drifting: bool, delta: float) -> void:
	if is_drifting:
		if not _was_drifting:
			_drift_start_car_rotation = target.rotation
		var rotation_delta: float = wrapf(target.rotation - _drift_start_car_rotation, -PI, PI)
		var target_rotation: float = rotation_delta * drift_rotation_follow
		rotation = lerp_angle(rotation, target_rotation, clamp(drift_rotation_smoothing * delta, 0.0, 1.0))
	else:
		rotation = lerp_angle(rotation, 0.0, clamp(drift_recover_smoothing * delta, 0.0, 1.0))

	_was_drifting = is_drifting
