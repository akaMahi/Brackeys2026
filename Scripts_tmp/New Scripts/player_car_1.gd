extends CarBase

# ── Player-specific: input, engine/steering/traction, drift marks, and
# sound (engine + drift). Health, collision damage, knockback, and crash
# sound all live in car_base.gd — see that file for those.
#
# The player's "detection radius" that spawners react to now lives in its
# own script (player_detection_area.gd), on a child node you place and
# size yourself in the editor with a real CollisionShape2D — it used to
# be built here from a plain number at runtime, which meant you couldn't
# see or directly edit it. See player_detection_area.gd for setup.

@export_group("Engine")
@export var max_speed: float = 600.0
@export var acceleration: float = 900.0
@export var reverse_max_speed: float = 300.0
@export var reverse_acceleration: float = 600.0
@export var braking: float = 1400.0
@export var friction: float = 500.0

@export_group("Steering")
@export var max_steer_angle: float = 3.2 # radians/sec at full lock, low speed
@export var min_speed_to_steer: float = 20.0 # below this, steering does nothing (no pivoting in place)
@export var steer_speed_curve: float = 0.6 # how much steering falls off as speed rises (0=no falloff, 1=heavy falloff)

@export_group("Grip / Drift")
@export var traction_normal: float = 12.0 # how fast velocity aligns to facing (higher = grippier)
@export var traction_drift: float = 2.5 # traction while handbraking/drifting
@export var drift_input: String = "drift" # action name, e.g. Shift or Space

@export_group("Drift Marks")
@export var rear_wheel_offset: float = 22.0 # how far behind the car's center the marks spawn
@export var rear_wheel_spread: float = 14.0 # distance between the left/right skid trails
@export var skid_mark_color: Color = Color(0.05, 0.05, 0.05, 0.55)
@export var skid_mark_width: float = 6.0
@export var skid_mark_min_point_distance: float = 4.0 # skip points closer together than this
@export var skid_mark_z_index: int = 1 # must be above your TileMap's z_index
@export var max_skid_marks: int = 40 # oldest mark lines are freed once this many exist

@export_group("Sound")
@export var engine_sound: AudioStream # a short, seamless loop — enable Loop in its Import settings
@export var engine_min_pitch: float = 0.8
@export var engine_max_pitch: float = 1.6
@export var engine_min_volume_db: float = -10.0
@export var engine_max_volume_db: float = 0.0
@export var drift_sound: AudioStream # a short, seamless loop (tire squeal) — enable Loop in Import settings
@export var drift_volume_db: float = 0.0

var forward_input: float = 0.0
var steer_input: float = 0.0
var is_drifting: bool = false

var _skid_marks: Array[Line2D] = []
var _active_left_mark: Line2D = null
var _active_right_mark: Line2D = null

var _engine_player: AudioStreamPlayer2D
var _drift_player: AudioStreamPlayer2D


func _ready() -> void:
	group_tag = "player"
	car_ready()
	_setup_sound()


func _physics_process(delta: float) -> void:
	_read_input()
	_apply_engine_force(delta)
	_apply_steering(delta)
	_apply_traction(delta)

	var pre_move_speed: float = velocity.length() # speed BEFORE collision response, used for wall-hit damage
	move_and_slide()

	car_physics_update(delta, pre_move_speed)
	_update_drift_marks()
	_update_engine_sound()
	_update_drift_sound()


func _read_input() -> void:
	# Replace with your own input actions ("throttle_up"/"throttle_down"/"steer_left"/"steer_right")
	forward_input = Input.get_axis("move_down", "move_up")
	steer_input = Input.get_axis("move_left", "move_right")
	is_drifting = Input.is_action_pressed(drift_input) if InputMap.has_action(drift_input) else false


func _apply_engine_force(delta: float) -> void:
	var forward_dir: Vector2 = Vector2.UP.rotated(rotation)
	var current_forward_speed: float = velocity.dot(forward_dir)

	if forward_input > 0.0:
		# -------------------------
		# FORWARD
		# -------------------------
		var target_speed: float = max_speed * forward_input

		# If currently moving backwards, brake toward 0 first.
		if current_forward_speed < 0.0:
			var new_speed: float = move_toward(
				current_forward_speed,
				0.0,
				braking * delta
			)
			velocity += forward_dir * (new_speed - current_forward_speed)
		else:
			var new_speed: float = move_toward(
				current_forward_speed,
				target_speed,
				acceleration * delta
			)
			velocity += forward_dir * (new_speed - current_forward_speed)

	elif forward_input < 0.0:
		# -------------------------
		# REVERSE
		# -------------------------
		var target_speed: float = -reverse_max_speed * abs(forward_input)

		# If currently moving forward, brake toward 0 first.
		if current_forward_speed > 0.0:
			var new_speed: float = move_toward(
				current_forward_speed,
				0.0,
				braking * delta
			)
			velocity += forward_dir * (new_speed - current_forward_speed)
		else:
			# Once stopped or already moving backwards,
			# use the dedicated reverse acceleration.
			var new_speed: float = move_toward(
				current_forward_speed,
				target_speed,
				reverse_acceleration * delta
			)
			velocity += forward_dir * (new_speed - current_forward_speed)

	else:
		# -------------------------
		# NO INPUT — COAST
		# -------------------------
		var decel: float = min(
			friction * delta,
			abs(current_forward_speed)
		)

		velocity -= (
			forward_dir
			* decel
			* sign(current_forward_speed)
		)

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
	# Align velocity with the direction the car is facing while
	# preserving whether the car is moving FORWARD or BACKWARD.

	var forward_dir := Vector2.UP.rotated(rotation)

	# Signed speed:
	#   positive = moving forward
	#   negative = moving backward
	var signed_speed := velocity.dot(forward_dir)

	if abs(signed_speed) < 1.0:
		# Remove tiny residual movement.
		velocity = Vector2.ZERO
		return

	var current_traction := traction_drift if is_drifting else traction_normal

	# IMPORTANT:
	# Keep the sign of signed_speed.
	# This allows traction to align the car backward when reversing.
	var target_velocity := forward_dir * signed_speed

	velocity = velocity.lerp(
		target_velocity,
		clamp(current_traction * delta, 0.0, 1.0)
	)

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


# ── Sound ──────────────────────────────────────────────────

func _setup_sound() -> void:
	_engine_player = AudioStreamPlayer2D.new()
	add_child(_engine_player)

	_drift_player = AudioStreamPlayer2D.new()
	add_child(_drift_player)


func _update_engine_sound() -> void:
	if engine_sound == null:
		return
	if _engine_player.stream != engine_sound:
		_engine_player.stream = engine_sound
	if not _engine_player.playing:
		_engine_player.play()

	var speed_ratio: float = clamp(velocity.length() / max_speed, 0.0, 1.0)
	_engine_player.pitch_scale = lerp(engine_min_pitch, engine_max_pitch, speed_ratio)
	_engine_player.volume_db = lerp(engine_min_volume_db, engine_max_volume_db, speed_ratio)


func _update_drift_sound() -> void:
	if drift_sound == null:
		return

	if is_drifting and not _drift_player.playing:
		_drift_player.stream = drift_sound
		_drift_player.volume_db = drift_volume_db
		_drift_player.play()
	elif not is_drifting and _drift_player.playing:
		_drift_player.stop()
