extends CharacterBody2D

# ── Added this pass ───────────────────────────────────────
# - Health system: takes damage from enemy-car collisions, and from wall
#   collisions when the car is going faster than a set threshold. A short
#   invulnerability window after any hit stops repeated frames of contact
#   from draining health instantly.
# - Drift particle FX: two dust-puff emitters spawn behind the rear wheels
#   and only emit while is_drifting is true. No sound yet, on purpose.
#
# Detection relies on Godot groups rather than hard node references, so it
# works no matter how your enemy cars/walls are built:
#   - enemy cars   → add their root node to the "enemy_car" group
#   - walls/obstacles → add their root node (or TileMap) to the "wall" group
# ───────────────────────────────────────────────────────────

# ── Tunables ──────────────────────────────────────────────
@export_group("Engine")
@export var max_speed: float = 600.0
@export var acceleration: float = 900.0 # how fast you reach max speed
@export var braking: float = 1400.0 # deceleration when reversing input
@export var friction: float = 500.0 # deceleration with no input (coasting)
@export var reverse_speed_mult: float = 0.5 # reverse is slower than forward

@export_group("Steering")
@export var max_steer_angle: float = 3.2 # radians/sec at full lock, low speed
@export var min_speed_to_steer: float = 20.0 # below this, steering does nothing (no pivoting in place)
@export var steer_speed_curve: float = 0.6 # how much steering falls off as speed rises (0=no falloff, 1=heavy falloff)

@export_group("Grip / Drift")
@export var traction_normal: float = 12.0 # how fast velocity aligns to facing (higher = grippier)
@export var traction_drift: float = 2.5 # traction while handbraking/drifting
@export var drift_input: String = "drift" # action name, e.g. Shift or Space

@export_group("Health")
@export var max_health: float = 100.0
@export var enemy_collision_damage: float = 25.0
@export var wall_collision_speed_threshold: float = 300.0 # min speed for a wall hit to hurt at all
@export var wall_collision_damage: float = 15.0
@export var wall_damage_scales_with_speed: bool = true # extra damage the harder you were going
@export var invulnerability_time: float = 0.5 # seconds of i-frames after any hit

@export_group("Drift FX")
@export var rear_wheel_offset: float = 22.0 # how far behind the car's center the skid marks spawn
@export var rear_wheel_spread: float = 14.0 # distance between the left/right skid emitters
@export var skid_particle_color: Color = Color(0.05, 0.05, 0.05, 0.55)

# ── Signals ───────────────────────────────────────────────
signal health_changed(current_health: float, max_health: float)
signal died

# ── Internal state ────────────────────────────────────────
var forward_input: float = 0.0
var steer_input: float = 0.0
var is_drifting: bool = false

var health: float = 0.0
var _invuln_timer: float = 0.0

var _skid_particles_left: CPUParticles2D
var _skid_particles_right: CPUParticles2D


func _ready() -> void:
	health = max_health
	_skid_particles_left = _make_skid_particles()
	_skid_particles_right = _make_skid_particles()
	add_child(_skid_particles_left)
	add_child(_skid_particles_right)


func _physics_process(delta: float) -> void:
	_read_input()
	_apply_engine_force(delta)
	_apply_steering(delta)
	_apply_traction(delta)

	var pre_move_speed: float = velocity.length() # speed BEFORE collision response, used for wall-hit damage
	move_and_slide()

	_handle_collision_damage(pre_move_speed)
	_update_drift_fx()

	if _invuln_timer > 0.0:
		_invuln_timer -= delta


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
		var decel: float = min(friction * delta, abs(current_forward_speed))
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


# ── Health / collision damage ────────────────────────────

func _handle_collision_damage(pre_move_speed: float) -> void:
	if _invuln_timer > 0.0:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null:
			continue

		if collider.is_in_group("enemy_car"):
			_take_damage(enemy_collision_damage)
			return

		if collider.is_in_group("wall") and pre_move_speed >= wall_collision_speed_threshold:
			var dmg: float = wall_collision_damage
			if wall_damage_scales_with_speed:
				dmg *= pre_move_speed / wall_collision_speed_threshold
			_take_damage(dmg)
			return


func _take_damage(amount: float) -> void:
	health = max(health - amount, 0.0)
	_invuln_timer = invulnerability_time
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


# ── Drift particle FX ─────────────────────────────────────

func _make_skid_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.6
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false # keep marks fixed in the world instead of riding along with the car
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = skid_particle_color
	# No texture assigned, so particles render as small plain squares.
	# Assign p.texture = preload("res://your_dust_texture.png") for a nicer look.
	return p


func _update_drift_fx() -> void:
	var forward_dir := Vector2.UP.rotated(rotation)
	var side_dir := forward_dir.orthogonal()
	var rear_point: Vector2 = global_position - forward_dir * rear_wheel_offset

	_skid_particles_left.global_position = rear_point - side_dir * (rear_wheel_spread * 0.5)
	_skid_particles_right.global_position = rear_point + side_dir * (rear_wheel_spread * 0.5)

	_skid_particles_left.emitting = is_drifting
	_skid_particles_right.emitting = is_drifting
