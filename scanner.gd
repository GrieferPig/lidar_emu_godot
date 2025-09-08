# LidarScanner.gd
extends Node3D

## Number of points in a full horizontal sweep.
@export var horizontal_resolution = 256
## Number of vertical laser layers.
@export var vertical_resolution = 64
## Maximum range of the scanner in meters.
@export var max_range = 120.0
## Sensitivity of the mouse for camera rotation.
@export var mouse_sensitivity = 0.15
## Speed of the camera flight controls.
@export var move_speed = 8.0
@export var min_color_dist = 0.0
@export var max_color_dist = 5.0

# --- Node References ---
@onready var camera_3d: Camera3D = $Camera
@onready var multi_mesh_instance: MultiMeshInstance3D = $RaysHitVisualizer
@onready var front_indicator: MeshInstance3D = $FrontIndicator
# HUD Labels
@onready var cam_facing_label: Label = $"../Hud/CamFacing"
@onready var cam_pos_label: Label = $"../Hud/CamPos"
@onready var scan_log_label: Label = $"../Hud/ScanLog"


# --- Scan Saving ---
const SCAN_FOLDER = "scans"
var scan_counter = 0

var point_cloud_data: Array = []
var instance_count: int = 0


func _ready():
	# IMPORTANT: For color to work, you MUST select the MultiMesh resource
	# in the Inspector and set its "Use Colors" property to true.
	instance_count = horizontal_resolution * vertical_resolution
	multi_mesh_instance.multimesh.instance_count = instance_count
	
	# Create the scans directory if it doesn't exist.
	DirAccess.make_dir_recursive_absolute(SCAN_FOLDER)
	
	# [cite_start]Find the latest scan counter from existing files. [cite: 1]
	_initialize_scan_counter()

	# Generate an initial scan.
	generate_and_visualize_scan()
	_draw_front_indicator()
	_update_hud() # Initial HUD update
	scan_log_label.text = "Press Space/Enter to scan and save."


func _initialize_scan_counter():
	# Scans the directory to find the highest existing scan number.
	var max_num = 0
	var dir = DirAccess.open(SCAN_FOLDER)
	if dir:
		var regex = RegEx.new()
		# Regex to find one or more digits (\d+) in the filename.
		regex.compile("point_cloud_categorized_(\\d+)\\.txt")
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var result = regex.search(file_name)
				if result:
					var num = result.get_string(1).to_int()
					if num > max_num:
						max_num = num
			file_name = dir.get_next()
		
		scan_counter = max_num
		print("Initialized scan counter from latest file: %d" % scan_counter)
	else:
		print("Error: Could not open scan directory to check for existing files.")


func _physics_process(delta: float):
	var moved = false
	# Handle 6-axis camera flight movement only when mouse is captured.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	var basis = camera_3d.global_transform.basis
	var direction = Vector3.ZERO
	
	# Forward/Backward (W/S) relative to where the camera is looking.
	if Input.is_action_pressed("move_forward"):
		direction -= basis.z
	if Input.is_action_pressed("move_backward"):
		direction += basis.z
	
	# Left/Right (A/D) relative to the camera's side.
	if Input.is_action_pressed("move_left"):
		direction -= basis.x
	if Input.is_action_pressed("move_right"):
		direction += basis.x
	
	# Up/Down (E/Q) on the global Y-axis.
	if Input.is_action_pressed("move_up"):
		direction += Vector3.UP
	if Input.is_action_pressed("move_down"):
		direction -= Vector3.UP
	
	# Apply movement if there was any input.
	if direction != Vector3.ZERO:
		global_position += direction.normalized() * move_speed * delta
		moved = true
	
	if moved:
		_update_hud()
	
func _input(event: InputEvent):
	if event is InputEventMouseButton and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Handle mouse motion for camera rotation only.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Horizontal rotation (yaw) affects the parent Node3D (self).
		self.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		
		# Vertical rotation (pitch) affects the camera directly.
		camera_3d.rotate_x(deg_to_rad(event.relative.y * mouse_sensitivity))
		
		# Clamp vertical rotation to prevent flipping over (-90 to 90 degrees).
		var camera_rot = camera_3d.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, 0, 90)
		camera_3d.rotation_degrees = camera_rot
		_update_hud() # Update HUD on rotation

	# Press Escape to release the mouse cursor.
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Press the "Accept" key (Enter/Space) to generate a new scan and save it.
	if Input.is_action_just_pressed("ui_accept"):
		# The scan is performed from the scanner's current location after moving.
		generate_and_visualize_scan()

		# Increment counter and create a new filename.
		scan_counter += 1
		var file_name = "point_cloud_categorized_%d.txt" % scan_counter
		var full_path = SCAN_FOLDER.path_join(file_name)
		save_to_file(full_path)


func _update_hud():
	# Update camera position label
	var pos = self.global_position
	cam_pos_label.text = "Camera Pos: x %.2f, y %.2f, z %.2f" % [pos.x, pos.y, pos.z]

	# Update camera facing label (Yaw from self, Pitch from camera)
	var yaw_deg = rad_to_deg(self.rotation.y)
	var pitch_deg = camera_3d.rotation_degrees.x
	cam_facing_label.text = "Camera Facing: angleH %.2f, angleV %.2f" % [yaw_deg, pitch_deg]


func _draw_front_indicator():
	# This function creates a simple red line mesh programmatically.
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	# Make the line bright and ignore lighting.
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(Vector3(0,-1,0)) # Start at origin.
	# End point stretching out along the local +Z axis (front).
	mesh.surface_add_vertex(Vector3(0, -1, 1 * max_range))
	mesh.surface_end()
	
	front_indicator.mesh = mesh


func generate_and_visualize_scan():
	front_indicator.rotation.y = self.rotation.y
	front_indicator.transform = self.transform
	point_cloud_data.clear()
	var space_state = get_world_3d().direct_space_state
	var v_angle_step = (PI / 2.0) / vertical_resolution
	var instance_index = 0

	# The basis of 'self' correctly contains the horizontal rotation (yaw)
	# but not the camera's vertical rotation (pitch), as requested.
	var basis = self.global_transform.basis
	
	for i in range(vertical_resolution):
		var v_angle = i * v_angle_step
		for j in range(horizontal_resolution):
			var h_angle = (2.0 * PI / horizontal_resolution) * j

			var local_dir = Vector3(
				cos(v_angle) * sin(h_angle),
				sin(v_angle),
				cos(v_angle) * cos(h_angle)
			).normalized()

			var global_dir = basis * local_dir
			var query = PhysicsRayQueryParameters3D.create(self.global_position, self.global_position + global_dir * max_range)
			var result = space_state.intersect_ray(query)

			if result:
				var distance = self.global_position.distance_to(result.position)
				var t = remap(distance, min_color_dist, max_color_dist, 0.0, 1.0)
				var point_color = Color.GREEN.lerp(Color.RED, t)
				multi_mesh_instance.multimesh.set_instance_color(instance_index, point_color)

				var collider = result.collider
				var object_name = collider.name if collider else "Unknown"
				point_cloud_data.append({"pos": result.position, "name": object_name})
				
				var local_hit_pos = multi_mesh_instance.to_local(result.position)
				var hit_transform = Transform3D(Basis(), local_hit_pos)
				multi_mesh_instance.multimesh.set_instance_transform(instance_index, hit_transform)
			else:
				# Hide points that don't hit anything.
				var hidden_transform = Transform3D(Basis(), Vector3(0, -1000, 0))
				multi_mesh_instance.multimesh.set_instance_transform(instance_index, hidden_transform)
				multi_mesh_instance.multimesh.set_instance_color(instance_index, Color.TRANSPARENT)
			
			instance_index += 1


func save_to_file(file_path: String):
	if point_cloud_data.is_empty():
		var msg = "Point cloud data is empty. Nothing to save."
		print(msg)
		scan_log_label.text = msg
		return

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		var msg = "Error: Could not open file '%s' for writing." % file_path
		print(msg)
		scan_log_label.text = msg
		return

	# --- Write Header ---
	var pos = self.global_position
	var yaw_rad = self.rotation.y
	# Use camera's rotation for pitch, since it's separate
	var pitch_rad = camera_3d.rotation.x
	file.store_line("# SCANNER_POS: %f %f %f" % [pos.x, pos.y, pos.z])
	file.store_line("# SCANNER_ROT: %f %f" % [yaw_rad, pitch_rad])
	
	# --- Write Points ---
	for point_data in point_cloud_data:
		file.store_line("%f %f %f %s" % [point_data.pos.x, point_data.pos.y, point_data.pos.z, point_data.name])

	var success_msg = "Successfully saved %d points to %s" % [point_cloud_data.size(), file_path.get_file()]
	print(success_msg)
	scan_log_label.text = success_msg
