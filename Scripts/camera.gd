extends Camera2D

# ── FIXED CAMERA BOXES ────────────────────────────────────
# This camera no longer follows the car. Instead the level is divided into
# "camera box" regions (Area2D nodes running camera_box.gd). Whichever box
# the car is currently inside defines where the camera sits — dead center
# on that box, held completely still. The moment the car crosses into a
# different box, the camera INSTANTLY snaps to the new box's center (no
# lerping/smoothing on position at all).
#
# Zoom still reacts continuously to the car's speed (zoomed IN while slow,
# zoomed OUT while fast), and on top of that, rotation and zoom get a
# reactive "kick" while the car is drifting, driven by the car's own
# `is_drifting` flag and how far it has turned since the drift began.
#
# IMPORTANT — this camera is now expected to be a SIBLING of the car (e.g.
# directly under your level/world root), NOT a child of it. Position is
# driven entirely by camera boxes now, and rotation is driven entirely by
# the drift-kick logic below — if this node stays parented to the car, the
# car's own transform gets added on top of both and everything will drift
# and jitter. Keep "target" pointed at the car via the Inspector, same as
# before.

@export var target: Node2D

@export_group("Camera Boxes")
@export var camera_box_group: String = "camera_box" # boxes must be in this group
@export var start_at_first_box: bool = true # snap to whichever box the car starts inside

@export_group("Zoom")
@export var zoom_close: float = 0.85 # zoom value while the car is SLOW (smaller = zoomed IN)
@export var zoom_far: float = 1.4    # zoom value while the car is FAST (larger = zoomed OUT)
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
	position_smoothing_enabled = false # position now snaps between boxes, never smooths
	ignore_rotation = false            # must be false or our own rotation never reaches the screen

	_current_zoom = zoom_close
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
	global_position = box.global_position # instant teleport — no lerp, no smoothing


# ── Zoom ──────────────────────────────────────────────────

func _update_zoom(car_velocity: Vector2, is_drifting: bool, delta: float) -> void:
	var speed_ratio: float = clamp(car_velocity.length() / zoom_speed_reference, 0.0, 1.0)
	var target_zoom: float = lerp(zoom_close, zoom_far, speed_ratio)

	if is_drifting:
		target_zoom -= drift_zoom_kick

	target_zoom = clamp(target_zoom, zoom_hard_min, zoom_far)
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
