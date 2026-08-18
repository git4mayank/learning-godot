extends CharacterBody2D

class_name FollowingPet

@export_category("Pet Configuration")
@export var pet_name: String = "ShadowBuddy"
@export var target_path: NodePath = NodePath("../Player")
@export var movement_speed: float = 240.0
@export var acceleration: float = 8.5
@export var stopping_distance: float = 64.0
@export var teleport_threshold: float = 1200.0

@export_category("Visual & Animation")
@export var float_amplitude: float = 8.0
@export var float_frequency: float = 4.0
@export var sprite_path: NodePath = NodePath("Sprite2D")
@export var particle_trail_path: NodePath = NodePath("CPUParticles2D")

@export_category("AI Debug & State")
@export var enable_random_wander: bool = true
@export var wander_interval: float = 5.0
@export var debug_mode: bool = false

# Internal state variables
enum State { IDLE, FOLLOWING, WANDERING, TELEPORTING }
var current_state: State = State.IDLE
var target_node: Node2D = null
var time_accumulator: float = 0.0
var wander_timer: float = 0.0
var wander_target: Vector2 = Vector2.ZERO
var base_y_offset: float = 0.0

@onready var sprite: Sprite2D = get_node_or_null(sprite_path) as Sprite2D
@onready var particle_trail: CPUParticles2D = get_node_or_null(particle_trail_path) as CPUParticles2D

func _ready() -> void:
	if not Engine.is_editor_hint():
		randomize()
		
	if not target_path.is_empty():
		target_node = get_node_or_null(target_path) as Node2D
		
	if target_node == null:
		# Fallback to finding player by group if path is invalid
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target_node = players[0] as Node2D
			
	if sprite:
		base_y_offset = sprite.position.y

	if debug_mode:
		print("[%s] Initialized successfully. Target: %s" % [pet_name, target_node])

func _physics_process(delta: float) -> void:
	if target_node == null:
		_handle_missing_target(delta)
		return

	_update_state_machine(delta)
	_execute_behavior(delta, current_state)
	_apply_visual_effects(delta)
	
	move_and_slide()

func _update_state_machine(delta: float) -> void:
	var distance_to_target: float = global_position.distance_to(target_node.global_position)

	# Check for emergency teleport if player gets too far away
	if distance_to_target > teleport_threshold:
		current_state = State.TELEPORTING
		return

	if distance_to_target > stopping_distance:
		current_state = State.FOLLOWING
	else:
		if enable_random_wander:
			wander_timer -= delta
			if wander_timer <= 0.0:
				_pick_new_wander_target()
				current_state = State.WANDERING
			elif current_state != State.WANDERING:
				current_state = State.IDLE
		else:
			current_state = State.IDLE

func _execute_behavior(delta: float, state: State) -> void:
	match state:
		State.FOLLOWING:
			var direction: Vector2 = (target_node.global_position - global_position).normalized()
			var target_velocity: Vector2 = direction * movement_speed
			velocity = velocity.lerp(target_velocity, acceleration * delta)
			_update_facing(direction.x)

		State.WANDERING:
			var direction: Vector2 = (wander_target - global_position).normalized()
			var target_velocity: Vector2 = direction * (movement_speed * 0.4)
			velocity = velocity.lerp(target_velocity, acceleration * delta * 0.5)
			if global_position.distance_to(wander_target) < 16.0:
				current_state = State.IDLE
				wander_timer = randf_range(2.0, wander_interval)

		State.IDLE:
			velocity = velocity.lerp(Vector2.ZERO, acceleration * delta)

		State.TELEPORTING:
			_perform_teleport()

func _perform_teleport() -> void:
	if target_node == null:
		return
	
	var offset = Vector2(randf_range(-40, 40), randf_range(-40, 40))
	global_position = target_node.global_position + offset
	velocity = Vector2.ZERO
	
	if particle_trail:
		particle_trail.emitting = true
		
	if debug_mode:
		print("[%s] Teleported to player position due to distance threshold." % pet_name)
		
	current_state = State.IDLE
	wander_timer = wander_interval

func _pick_new_wander_target() -> void:
	var random_offset = Vector2(
		randf_range(-80.0, 80.0),
		randf_range(-80.0, 80.0)
	)
	if target_node:
		wander_target = target_node.global_position + random_offset
	else:
		wander_target = global_position + random_offset

func _apply_visual_effects(delta: float) -> void:
	time_accumulator += delta
	
	if sprite:
		# Floating sine-wave effect
		var float_offset = sin(time_accumulator * float_frequency) * float_amplitude
		sprite.position.y = base_y_offset + float_offset

func _update_facing(dir_x: float) -> void:
	if sprite:
		if abs(dir_x) > 0.05:
			sprite.flip_h = dir_x < 0

func _handle_missing_target(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, acceleration * delta)
	if debug_mode and Engine.get_frames_drawn() % 120 == 0:
		warn_target_missing()

func warn_target_missing() -> void:
	push_warning("[%s] Warning: Target node reference is missing or null!" % pet_name)

func set_custom_pet_name(new_name: String) -> void:
	pet_name = new_name
	if debug_mode:
		print("Pet name updated to: ", pet_name)