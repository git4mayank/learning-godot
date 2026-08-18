extends CharacterBody3D
class_name PlayerController

# --- ENUMS & STATES ---
enum MovementState { IDLE, WALKING, SPRINTING, CROUCHING, IN_AIR }
enum PetFollowMode { STRICT, LOOSE, PATROL, FORMATION }

signal state_changed(old_state: MovementState, new_state: MovementState)
signal stamina_depleted
signal footstep_triggered(surface_type: String, volume: float)

# --- CONSTANTS & CONFIGURATION ---
const SENSISIVITY := 0.0025
const WALK_SPEED := 5.0
const SPRINT_SPEED := 10.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 4.5
const GRAVITY_MULTIPLIER := 1.25

const BOB_FREQ := 2.0
const BOB_AMP := 0.08
const TILT_STRENGTH := 0.05
const BASE_FOV := 75.0
const FOV_CHANGE := 1.5

const MAX_STAMINA := 100.0
const STAMINA_DRAIN := 20.0
const STAMINA_RECOVERY := 15.0

# --- EXPORT VARIABLES ---
@export_category("Node References")
@export var pet_node: Node3D
@export var pet_script_ref: Resource
@export var footstep_audio_player: AudioStreamPlayer3D

@export_category("Pet Integration")
@export var pet_follow_distance := 2.5
@export var pet_catchup_speed := 12.0
@export var pet_teleport_distance := 15.0
@export var active_pet_mode: PetFollowMode = PetFollowMode.STRICT

@export_category("Advanced Mechanics")
@export var enable_procedural_lean := true
@export var enable_stamina_system := true
@export var air_control_modifier := 3.0
@export var ground_friction := 7.0

# --- PRIVATE STATE VARIABLES ---
var SPEED := 0.0
var t_bob := 0.0
var current_stamina := MAX_STAMINA
var current_state: MovementState = MovementState.IDLE
var is_stamina_exhausted := false
var target_cam_tilt := 0.0
var last_position := Vector3.ZERO
var calculated_velocity := Vector3.ZERO
var step_timer := 0.0

# --- ONREADY NODES ---
@onready var head := $Head as Node3D
@onready var camera := $Head/Camera3D as Camera3D
@onready var raycast_floor := $FloorRayCast as RayCast3D if has_node("FloorRayCast") else null

# --- INITIALIZATION ---
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_pet_connection()
	_initialize_telemetry()

func _setup_pet_connection() -> void:
	if not pet_node:
		pet_node = get_node_or_null("../Pet")
	if pet_node and pet_node.has_method("bind_to_master"):
		pet_node.call("bind_to_master", self)

func _initialize_telemetry() -> void:
	last_position = global_position
	print("[PlayerController] Systems initialized successfully.")

# --- INPUT HANDLING ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSISIVITY)
		camera.rotate_x(-event.relative.y * SENSISIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40.0), deg_to_rad(60.0))
		
		if enable_procedural_lean:
			target_cam_tilt = clamp(-event.relative.x * SENSISIVITY * TILT_STRENGTH, deg_to_rad(-5.0), deg_to_rad(5.0))

# --- MAIN PHYSICS LOOP ---
func _physics_process(delta: float) -> void:
	_update_stamina(delta)
	_evaluate_movement_state()
	_apply_gravity_and_jump(delta)
	
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	_handle_translation(direction, delta)
	_handle_camera_effects(delta, input_dir)
	_update_pet_coordination(delta)
	
	move_and_slide()
	_post_physics_update(delta)

# --- MOVEMENT & STAMINA LOGIC ---
func _evaluate_movement_state() -> void:
	var previous_state = current_state
	
	if not is_on_floor():
		current_state = MovementState.IN_AIR
	elif Input.is_action_pressed("crouch"):
		current_state = MovementState.CROUCHING
	elif Input.is_action_pressed("sprint") and not is_stamina_exhausted and velocity.length() > 0.1:
		current_state = MovementState.SPRINTING
	elif velocity.length() > 0.1:
		current_state = MovementState.WALKING
	else:
		current_state = MovementState.IDLE
		
	if previous_state != current_state:
		emit_signal("state_changed", previous_state, current_state)

func _update_stamina(delta: float) -> void:
	if not enable_stamina_system:
		return
		
	if current_state == MovementState.SPRINTING:
		current_stamina = max(0.0, current_stamina - STAMINA_DRAIN * delta)
		if current_stamina <= 0.0 and not is_stamina_exhausted:
			is_stamina_exhausted = true
			emit_signal("stamina_depleted")
	else:
		current_stamina = min(MAX_STAMINA, current_stamina + STAMINA_RECOVERY * delta)
		if is_stamina_exhausted and current_stamina >= MAX_STAMINA * 0.3:
			is_stamina_exhausted = false

func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * GRAVITY_MULTIPLIER * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

func _handle_translation(direction: Vector3, delta: float) -> void:
	match current_state:
		MovementState.CROUCHING:
			SPEED = CROUCH_SPEED
		MovementState.SPRINTING:
			SPEED = SPRINT_SPEED
		_:
			SPEED = WALK_SPEED

	var lerp_weight := ground_friction if is_on_floor() else air_control_modifier
	
	if direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, direction.x * SPEED, delta * lerp_weight)
		velocity.z = lerp(velocity.z, direction.z * SPEED, delta * lerp_weight)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * lerp_weight)
		velocity.z = lerp(velocity.z, 0.0, delta * lerp_weight)

# --- CAMERA PROCEDURAL ANIMATION ---
func _handle_camera_effects(delta: float, input_dir: Vector2) -> void:
	# Headbob calculations
	if is_on_floor() and velocity.length() > 0.1:
		t_bob += delta * velocity.length() * float(is_on_floor())
		head.transform.origin = _calculate_headbob(t_bob)
		_process_footstep_audio(delta)
	else:
		head.transform.origin = head.transform.origin.lerp(Vector3.ZERO, delta * 5.0)
	
	# FOV dynamics
	var velocity_clamped := clamp(velocity.length(), 0.5, SPRINT_SPEED * 2.0)
	var target_fov := BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	# Procedural camera roll/tilt
	if enable_procedural_lean:
		var target_z := -input_dir.x * TILT_STRENGTH
		camera.rotation.z = lerp(camera.rotation.z, target_z + target_cam_tilt, delta * 6.0)
		target_cam_tilt = lerp(target_cam_tilt, 0.0, delta * 4.0)

func _calculate_headbob(time: float) -> Vector3:
	var pos := Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2.0) * BOB_AMP
	return pos

func _process_footstep_audio(delta: float) -> void:
	step_timer += delta * velocity.length()
	if step_timer >= 2.5:
		step_timer = 0.0
		var surface = _detect_surface_type()
		emit_signal("footstep_triggered", surface, randf_range(0.8, 1.2))

func _detect_surface_type() -> String:
	if raycast_floor and raycast_floor.is_colliding():
		var collider = raycast_floor.get_collider()
		if collider.has_meta("surface_type"):
			return collider.get_meta("surface_type")
	return "default"

# --- PET SUBSYSTEM COORDINATION ---
func _update_pet_coordination(delta: float) -> void:
	if not pet_node:
		return
		
	var dist_to_pet := global_position.distance_to(pet_node.global_position)
	
	# Teleport if pet is out of bounds
	if dist_to_pet > pet_teleport_distance:
		_teleport_pet_to_owner()
		return
		
	# Call update function on pet if script exists
	if pet_node.has_method("process_follow_behavior"):
		var target_pos := global_position - (head.transform.basis.z * pet_follow_distance)
		pet_node.call("process_follow_behavior", target_pos, SPEED, delta, active_pet_mode)

func _teleport_pet_to_owner() -> void:
	if pet_node:
		var spawn_offset := -head.transform.basis.z * 1.5
		pet_node.global_position = global_position + spawn_offset
		if pet_node.has_method("reset_navigation_agent"):
			pet_node.call("reset_navigation_agent")

func _post_physics_update(delta: float) -> void:
	calculated_velocity = (global_position - last_position) / delta
	last_position = global_position

# --- PUBLIC INTERFACE API ---
func get_stamina_ratio() -> float:
	return current_stamina / MAX_STAMINA

func set_pet_mode(mode: PetFollowMode) -> void:
	active_pet_mode = mode

func apply_external_impulse(impulse: Vector3) -> void:
	velocity += impulse