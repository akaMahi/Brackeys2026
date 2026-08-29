extends CharacterBody2D
class_name CarBase

# Shared health / collision-damage / knockback / crash-sound logic for any
# car in the game — both player_car.gd and enemy_car.gd extend this and
# add their own movement/input/AI on top.
#
# HOW TO USE FROM A SUBCLASS:
#   func _ready() -> void:
#       group_tag = "player"      # or "enemy_car" — whatever group this car should join
#       car_ready()
#       ...your own setup...
#
#   func _physics_process(delta: float) -> void:
#       ...your own movement, ending with:
#       var pre_move_speed := velocity.length()   # captured right before move_and_slide()
#       move_and_slide()
#       car_physics_update(delta, pre_move_speed)
#       ...anything else...
#
# Collisions are resolved independently by EACH car's own script — when
# two cars hit each other, both sides detect the same contact from their
# own move_and_slide() results and push themselves apart, which is what
# gives the "both get knocked back" effect without any direct
# node-to-node calls between them.

@export_group("Health")
@export var max_health: float = 100.0
@export var collision_damage: float = 25.0 # damage dealt when hitting another car (player or enemy)
@export var wall_collision_speed_threshold: float = 300.0
@export var wall_collision_damage: float = 15.0
@export var wall_damage_scales_with_speed: bool = true
@export var invulnerability_time: float = 0.5

@export_group("Knockback")
@export var knockback_strength: float = 0.6 # fraction of impact speed converted into a push-back
@export var knockback_max_speed: float = 400.0 # impact speed is capped to this before knockback math runs, so a fast drift-collision can't fling you across the map
@export var knockback_rotation_kick: float = 0.6 # radians of "spin" per 1000 units/sec of (capped) impact speed
@export var min_knockback_speed: float = 40.0 # softer impacts than this don't knock back at all

@export_group("Sound")
@export var crash_sound: AudioStream
@export var crash_volume_db: float = 0.0
@export var min_crash_impact_speed: float = 80.0

signal health_changed(current_health: float, max_health: float)
signal died

var health: float = 0.0
var group_tag: String = "" # set by the subclass before calling car_ready()

var _invuln_timer: float = 0.0
var _crash_player: AudioStreamPlayer2D


func car_ready() -> void:
	# GROUNDED is Godot's default motion_mode and assumes gravity/a floor,
	# which doesn't exist in a top-down game — it can make a CharacterBody2D
	# behave like it's stuck against invisible floor/ceiling logic,
	# especially right after spawning near a wall or another body. FLOATING
	# treats all collisions uniformly, which is what a top-down car needs.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	health = max_health
	if group_tag != "":
		add_to_group(group_tag)

	_crash_player = AudioStreamPlayer2D.new()
	add_child(_crash_player)


func car_physics_update(delta: float, pre_move_speed: float) -> void:
	_handle_collisions(pre_move_speed)
	if _invuln_timer > 0.0:
		_invuln_timer -= delta


func _handle_collisions(pre_move_speed: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null:
			continue

		if collider.is_in_group("wall"):
			_handle_wall_collision(collision, pre_move_speed)
		elif collider.is_in_group("player") or collider.is_in_group("enemy_car"):
			_handle_car_collision(collision)


func _handle_wall_collision(collision: KinematicCollision2D, pre_move_speed: float) -> void:
	_apply_knockback(collision.get_normal(), pre_move_speed)
	_play_crash_sound(pre_move_speed)

	if pre_move_speed < wall_collision_speed_threshold or _invuln_timer > 0.0:
		return

	var dmg: float = wall_collision_damage
	if wall_damage_scales_with_speed:
		dmg *= pre_move_speed / wall_collision_speed_threshold
	_take_damage(dmg)
	print("took damage")


func _handle_car_collision(collision: KinematicCollision2D) -> void:
	var other_velocity: Vector2 = collision.get_collider_velocity()
	var impact_speed: float = (velocity - other_velocity).length()

	_apply_knockback(collision.get_normal(), impact_speed)
	_play_crash_sound(impact_speed)

	if _invuln_timer > 0.0:
		return
	_take_damage(collision_damage)


func _apply_knockback(collision_normal: Vector2, impact_speed: float) -> void:
	if impact_speed < min_knockback_speed:
		return

	# Capped BEFORE the multiply — this is what stops a high-speed drift
	# collision from injecting an enormous velocity that then lingers even
	# longer than usual since drift traction is weak and slow to reabsorb it.
	var effective_speed: float = min(impact_speed, knockback_max_speed)

	velocity += collision_normal * effective_speed * knockback_strength

	var spin_direction: float = sign(collision_normal.x) if collision_normal.x != 0.0 else 1.0
	rotation += spin_direction * knockback_rotation_kick * (effective_speed / 1000.0)


func _play_crash_sound(impact_speed: float) -> void:
	if crash_sound == null or impact_speed < min_crash_impact_speed or _crash_player.playing:
		return
	_crash_player.stream = crash_sound
	_crash_player.volume_db = crash_volume_db
	_crash_player.pitch_scale = clamp(impact_speed / 600.0, 0.8, 1.4)
	_crash_player.play()


func _take_damage(amount: float) -> void:
	health = max(health - amount, 0.0)
	_invuln_timer = invulnerability_time
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()
	print("took damage")


func grant_invulnerability(duration: float) -> void:
	_invuln_timer = max(_invuln_timer, duration)


func heal(amount: float) -> void:
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)

func apply_wall_knockback(push_direction: Vector2, strength: float) -> void:
	if strength <= 0.0:
		return

	var direction := push_direction.normalized()

	if direction == Vector2.ZERO:
		return

	velocity += direction * strength
