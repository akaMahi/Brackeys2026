extends Camera2D

# ── Auto-scrolling camera for the endless-runner car game.
# Moves at a constant (optionally ramping) speed independent of the
# player. runner_car.gd reads `scroll_speed` to know the pace the
# player's own speed is measured against, and uses this camera's
# position + viewport size to know when the car has drifted off-screen.

signal scroll_speed_changed(new_speed: float)

@export var scroll_speed: float = 500.0 # world px/sec — the "camera speed" the car's cruise speed compares against
@export var direction: Vector2 = Vector2.UP # must match forward_direction on runner_car.gd
@export var autoscroll: bool = true

@export_group("Difficulty Ramp (optional)")
@export var ramp_enabled: bool = false
@export var ramp_per_second: float = 5.0 # how much scroll_speed increases per second
@export var max_scroll_speed: float = 1200.0

var _direction_normalized: Vector2


func _ready() -> void:
	_direction_normalized = direction.normalized()


func _physics_process(delta: float) -> void:
	if ramp_enabled and scroll_speed < max_scroll_speed:
		set_scroll_speed(min(scroll_speed + ramp_per_second * delta, max_scroll_speed))

	if autoscroll:
		global_position += _direction_normalized * scroll_speed * delta


func set_scroll_speed(new_speed: float) -> void:
	scroll_speed = new_speed
	scroll_speed_changed.emit(scroll_speed)