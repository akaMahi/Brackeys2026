extends CharacterBody2D

# ── Added/changed this pass ───────────────────────────────
# - Health system: takes damage from enemy-car collisions, and from wall
#   collisions when going faster than a set threshold. A short
#   invulnerability window after any hit stops repeated frames of contact
#   from draining health instantly. grant_invulnerability() below is the
#   public entry point the invulnerability pickup uses.
# - Drift marks: two Line2D trails spawn behind the rear wheels while
#   is_drifting is true — actual persistent lines, not particles. They're
#   parented under the current scene (not the car) with top_level = true,
#   so they stay put in world space once drawn instead of dragging along
#   with the car. z_index is set explicitly so they draw above a TileMap.
# - Self-registers into the "player" group on ready, so camera_box.gd and
#   the pickup scripts all recognize this car with no manual tagging.
#
# Detection relies on Godot groups rather than hard node references:
#   - enemy cars      → self-register into "enemy_car" (see enemy_car.gd)
#   - walls/obstacles → add their root node (or TileMap) to the "wall" group
# ───────────────────────────────────────────────────────────

# ── Tunables ──────────────────────────────────────────────
@export_group("Engine")
@export var max_speed: float = 600.0
@export var acceleration: float = 900.0 # how fast you reach max speed
@export var braking: float = 1400.0 # deceleration when reversing input
@export var friction: float = 500.0 # deceleration with no input (coasting)
@export var reverse_speed_mult: float = 0.8 # reverse is slower than forward

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

@export_group("Drift Marks")
@export var rear_wheel_offset: float = 22.0 # how far behind the car's center the marks spawn
@export var rear_wheel_spread: float = 14.0 # distance between the left/right skid trails
@export var skid_mark_color: Color = Color(0.05, 0.05, 0.05, 0.55)
@export var skid_mark_width: float = 6.0
@export var skid_mark_min_point_distance: float = 4.0 # skip points closer together than this
@export var skid_mark_z_index: int = 1 # must be above your TileMap's z_index; if your car has its own z_index, keep it higher than this so the car visually drives over its own marks
@export var max_skid_marks: int = 40 # oldest mark lines are freed once this many exist

# ── Signals ───────────────────────────────────────────────
signal health_changed(current_health: float, max_health: float)
signal died

# ── Internal state ────────────────────────────────────────
var forward_input: float = 0.0
var steer_input: float = 0.0
var is_drifting: bool = false

var health: float = 0.0
var _invuln_timer: float = 0.0

var _skid_marks: Array[Line2D] = []
var _active_left_mark: Line2D = null
var _active_right_mark: Line2D = null


func _ready() -> void:
	add_to_group("player")
	health = max_health


func _physics_process(delta: float) -> void:
	_read_input()
	_apply_engine_force(delta)
	_apply_steering(delta)
	_apply_traction(delta)

	var pre_move_speed: float = velocity.length() # speed BEFORE collision response, used for wall-hit damage
	move_and_slide()

	_handle_collision_damage(pre_move_speed)
	_update_drift_marks()

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


func grant_invulnerability(duration: float) -> void:
	# Public entry point used by invulnerability_pickup.gd. Reuses the same
	# i-frame timer that collision damage already respects, so no damage
	# gets calculated at all for the duration. Never SHORTENS an already
	# longer invulnerability window in progress.
	_invuln_timer = max(_invuln_timer, duration)


func heal(amount: float) -> void:
	# Public entry point used by health_pickup.gd.
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)


# ── Drift marks (Line2D, not particles) ──────────────────

func _update_drift_marks() -> void:
	var forward_dir := Vector2.UP.rotated(rotation)
	var side_dir := forward_dir.orthogonal()
	var rear_point: Vector2 = global_position - forward_dir * rear_wheel_offset
	var left_wheel: Vector2 = rear_point - side_dir * (rear_wheel_spread * 0.5)
	var right_wheel: Vector2 = rear_point + side_dir * (rear_wheel_spread * 0.5)

	if is_drifting:
		if _active_left_mark == null:
			_active_left_mark = _start_new_mark()
			_active_right_mark = _start_new_mark()
		_add_mark_point(_active_left_mark, left_wheel)
		_add_mark_point(_active_right_mark, right_wheel)
	else:
		# Stop appending to the current pair — they stay behind as finished marks.
		_active_left_mark = null
		_active_right_mark = null


func _start_new_mark() -> Line2D:
	var line := Line2D.new()
	line.width = skid_mark_width
	line.default_color = skid_mark_color
	line.z_index = skid_mark_z_index
	line.z_as_relative = false
	line.top_level = true # ignore whatever parent transform it ends up under — points are plain world coordinates

	get_tree().current_scene.add_child(line)

	_skid_marks.append(line)
	if _skid_marks.size() > max_skid_marks:
		var oldest: Line2D = _skid_marks.pop_front()
		oldest.queue_free()

	return line


func _add_mark_point(line: Line2D, world_point: Vector2) -> void:
	if line.get_point_count() > 0:
		var last_point: Vector2 = line.get_point_position(line.get_point_count() - 1)
		if last_point.distance_to(world_point) < skid_mark_min_point_distance:
			return
	line.add_point(world_point)


func _on_health_changed(current_health: float, max_health: float) -> void:
	print("took damage")


func _on_died() -> void:
	print("ded")
