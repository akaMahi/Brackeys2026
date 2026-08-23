extends CharacterBody2D

# ── Tunables ──────────────────────────────────────────────
@export_group("Engine")
@export var max_speed: float = 600.0
@export var acceleration: float = 900.0      # how fast you reach max speed
@export var braking: float = 1400.0          # deceleration when reversing input
@export var friction: float = 500.0          # deceleration with no input (coasting)
@export var reverse_speed_mult: float = 0.5  # reverse is slower than forward

@export_group("Steering")
@export var max_steer_angle: float = 3.2     # radians/sec at full lock, low speed
@export var min_speed_to_steer: float = 20.0 # below this, steering does nothing (no pivoting in place)
@export var steer_speed_curve: float = 0.6   # how much steering falls off as speed rises (0=no falloff, 1=heavy falloff)

@export_group("Grip / Drift")
@export var traction_normal: float = 12.0    # how fast velocity aligns to facing (higher = grippier)
@export var traction_drift: float = 2.5      # traction while handbraking/drifting
@export var drift_input: String = "drift"    # action name, e.g. Shift or Space

# ── Internal state ────────────────────────────────────────
var forward_input: float = 0.0
var steer_input: float = 0.0
var is_drifting: bool = false


func _physics_process(delta: float) -> void:
	_read_input()
	_apply_engine_force(delta)
	_apply_steering(delta)
	_apply_traction(delta)
	move_and_slide()


func _read_input() -> void:
	# Replace with your own input actions ("throttle_up"/"throttle_down"/"steer_left"/"steer_right")
	forward_input = Input.get_axis("move_down", "move_up")
	steer_input = Input.get_axis("move_left", "move_right")
	is_drifting = Input.is_action_pressed(drift_input) if InputMap.has_action(drift_input) else false


func _apply_engine_force(delta: float) -> void:
	var forward_dir := Vector2.UP.rotated(rotation)
	var current_forward_speed := velocity.dot(forward_dir)

	if forward_input != 0.0:
		var target_speed := max_speed * forward_input
		if forward_input < 0:
			target_speed *= reverse_speed_mult

		var accel_rate: float = acceleration if forward_input > 0 else braking
		var new_forward_speed: float = move_toward(current_forward_speed, target_speed, accel_rate * delta)
		velocity += forward_dir * (new_forward_speed - current_forward_speed)
	else:
		# Coast to a stop with friction
		var decel : float = min(friction * delta, abs(current_forward_speed))
		velocity -= forward_dir * decel * sign(current_forward_speed)


func _apply_steering(delta: float) -> void:
	var speed := velocity.length()
	if speed < min_speed_to_steer:
		return

	# Steering authority falls off at higher speed so it doesn't feel twitchy/spinny
	var speed_factor: float = clamp(speed / max_speed, 0.0, 1.0)
	var steer_falloff: float = 1.0 - (speed_factor * steer_speed_curve)

	# Reverse flips steering direction (like a real car backing up)
	var forward_dir := Vector2.UP.rotated(rotation)
	var moving_forward: float = sign(velocity.dot(forward_dir)) if velocity.length() > 5.0 else 1.0

	rotation += steer_input * max_steer_angle * steer_falloff * moving_forward * delta


func _apply_traction(delta: float) -> void:
	# This is THE key to good car feel: blend current velocity toward
	# the direction the car is facing. High traction = grippy arcade car.
	# Low traction (while drifting) = velocity keeps its old direction
	# while the car rotates, creating a slide.
	var forward_dir := Vector2.UP.rotated(rotation)
	var speed := velocity.length()
	if speed < 1.0:
		return

	var current_traction := traction_drift if is_drifting else traction_normal
	var target_velocity := forward_dir * speed
	velocity = velocity.lerp(target_velocity, clamp(current_traction * delta, 0.0, 1.0))