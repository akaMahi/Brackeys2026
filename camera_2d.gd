extends Camera2D

# Attach this to a Camera2D that is a CHILD of your car node,
# or a standalone Camera2D that calls set_target(car) below.

@export var target: Node2D

@export_group("Zoom")
@export var zoom_min: float = 1.4          # zoomed IN at low speed (more detail)
@export var zoom_max: float = 0.85         # zoomed OUT at high speed (more visibility)
@export var zoom_speed_reference: float = 600.0  # speed at which zoom_max is reached (match your car's max_speed)
@export var zoom_smoothing: float = 3.0    # how fast zoom transitions

@export_group("Look-ahead")
@export var lookahead_max: float = 220.0   # pixels the camera pushes toward travel direction at full speed
@export var lookahead_smoothing: float = 4.0
@export var lookahead_vertical_bias: float = 1.3  # push extra bias upward since vertical games need forward sight more than side sight

var _current_zoom: float = 1.0
var _current_lookahead: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Camera2D already has these built in — just set them directly.
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	_current_zoom = zoom_min
	zoom = Vector2(_current_zoom, _current_zoom)


func _process(delta: float) -> void:
	if target == null:
		return

	var velocity: Vector2 = Vector2.ZERO
	if target.has_method("get_velocity"):
		velocity = target.get_velocity()
	elif "velocity" in target:
		velocity = target.velocity

	var speed: float = velocity.length()
	var speed_ratio: float = clamp(speed / zoom_speed_reference, 0.0, 1.0)

	# ── Zoom ──
	var target_zoom: float = lerp(zoom_min, zoom_max, speed_ratio)
	_current_zoom = lerp(_current_zoom, target_zoom, clamp(zoom_smoothing * delta, 0.0, 1.0))
	zoom = Vector2(_current_zoom, _current_zoom)

	# ── Look-ahead offset ──
	var travel_dir: Vector2 = velocity.normalized() if speed > 10.0 else Vector2.ZERO
	var target_lookahead: Vector2 = travel_dir * lookahead_max * speed_ratio
	target_lookahead.y *= lookahead_vertical_bias  # bias toward seeing what's ahead vertically

	_current_lookahead = _current_lookahead.lerp(target_lookahead, clamp(lookahead_smoothing * delta, 0.0, 1.0))
	offset = _current_lookahead