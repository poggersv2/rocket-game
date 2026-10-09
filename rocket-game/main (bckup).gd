extends Node3D

# First-person cockpit rocket launch simulator for Godot 4.
# All geometry and UI are built from native Godot nodes and meshes.

const TARGET_ALTITUDE := 1000.0
const ROCKET_START := Vector3(0.0, 0.0, -24.0)
const COCKPIT_START := Vector3(0.0, 2.55, 2.55)

var rocket: Node3D
var launch_site: Node3D
var ground_plane: MeshInstance3D
var camera_home: Vector3 = Vector3.ZERO
var thrust_puzzle_seconds := 0.0
var thrust_puzzle_complete := false
var cockpit_rig: Node3D
var cockpit_visuals: Node3D
var flight_velocity := Vector3.ZERO
var rocket_body: MeshInstance3D
var flame: MeshInstance3D
var camera: Camera3D
var setup_panel: PanelContainer
var telemetry_panel: PanelContainer
var menu_toggle_button: Button
var dashboard_panel: PanelContainer
var dashboard_label: Label
var breathalyzer_panel: PanelContainer
var breathalyzer_label: Label
var breathalyzer_bar: ProgressBar
var puzzle_label: Label
var countdown_label: Label
var fuel_slider: HSlider
var thrust_slider: HSlider
var angle_slider: HSlider
var launch_button: Button
var cockpit_launch_button: Button
var quick_reset_button: Button
var reset_button
var status_label: Label
var telemetry_label: Label
var result_label: Label
var altitude_value: Label
var speed_value: Label
var fuel_value: Label
var time_value: Label
var attitude_label: Label
var instrument_fuel: ProgressBar
var instrument_thrust: ProgressBar
var hardware_label: Label
var serial_socket := StreamPeerTCP.new()
var serial_buffer := ""
var hardware_connected := false
var hardware_temp := -999.0
var humidity_value := -1.0
var hardware_front := false
var hardware_back := false
var hardware_pot := 0
var hardware_angle := 0
var hardware_encoder_button := false
var humidity_unlocked := false
var last_hardware_front := false
var last_hardware_back := false
var menu_is_open := false
var mouse_look_enabled := false
var mouse_look_yaw := 0.0
var mouse_look_pitch := 0.0
var mouse_sensitivity := 0.0025
var earth_timer_remaining := 150.0
var game_over := false
var pot_puzzle_seconds := 0.0
var angle_puzzle_seconds := 0.0
var pot_puzzle_complete := false
var angle_puzzle_complete := false
const PUZZLE_HOLD_SECONDS := 2.0

var fuel_initial := 100.0
var fuel_left := 100.0
var thrust_setting := 75.0
var angle_setting := 5.0
var altitude := 0.0
var vertical_speed := 0.0
var horizontal_speed := 0.0
var flight_time := 0.0
var is_flying := false
var mission_complete := false
var flight_ended := false
var sky_birds: Array[Node3D] = []
var sky_meteors: Array[Node3D] = []
var sky_asteroids: Array[Node3D] = []
var cockpit_sensor_left: Label3D
var cockpit_sensor_middle: Label3D
var cockpit_sensor_right: Label3D

func _ready() -> void:
	_build_environment()
	_build_launch_site()
	_build_rocket()
	# The vehicle is never shown from an external chase camera: this is a cockpit-only game.
	# Keep the hidden vehicle node for the simplified flight model and telemetry calculations.
	rocket.visible = false
	_build_cockpit()
	_build_ui()
	_connect_hardware_bridge()
	_reset_flight(false)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.055, 0.19, 0.38)
	sky_mat.sky_horizon_color = Color(0.55, 0.72, 0.83)
	sky_mat.ground_bottom_color = Color(0.10, 0.14, 0.17)
	sky_mat.ground_horizon_color = Color(0.42, 0.52, 0.56)
	sky_mat.sun_angle_max = 18.0
	sky_mat.use_debanding = true
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.72, 0.82)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 0.5 #used to be 1.35
	sun.shadow_enabled = true
	add_child(sun)

	# The rig is the pilot's eye point. The camera, cockpit shell and dashboard
	# all move and rotate together; world scenery is deliberately NOT parented here.
	cockpit_rig = Node3D.new()
	cockpit_rig.name = "CockpitRig"
	cockpit_rig.position = COCKPIT_START
	add_child(cockpit_rig)

	camera = Camera3D.new()
	camera.name = "CockpitCamera"
	camera.position = Vector3.ZERO
	camera.fov = 82.0
	cockpit_rig.add_child(camera)
	camera.current = true
	camera_home = Vector3.ZERO

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(500.0, 500.0)
	ground.mesh = ground_mesh
	ground_plane = ground
	ground.position = Vector3(0.0, -0.12, -30.0)
	ground.material_override = _mat(Color(0.22, 0.28, 0.29), 0.94)
	add_child(ground)

	# Distant low mountains give the window a real horizon line.
	for i in range(25):
		var hill := MeshInstance3D.new()
		var hill_mesh := SphereMesh.new()
		hill_mesh.radius = 1.0
		hill_mesh.height = 2.0
		hill.mesh = hill_mesh
		var x := -100.0 + float(i) * 8.3
		hill.position = Vector3(x, -1.1 + sin(float(i) * 1.21) * 0.9, -82.0 - float(i % 4) * 8.0)
		hill.scale = Vector3(7.0 + float(i % 3) * 2.0, 2.5 + float(i % 4), 5.5)
		hill.material_override = _mat(Color(0.24, 0.34, 0.39), 1.0)
		add_child(hill)

	# Static cloud banks live in world space, not under the cockpit rig. As the
	# cockpit flies upward, these clouds pass by naturally instead of rising with it.
	for cloud_index in range(20):
		var cloud_center := Node3D.new()
		cloud_center.name = "WorldCloud_%02d" % cloud_index
		cloud_center.position = Vector3(-230.0 + float(cloud_index) * 24.0, 55.0 + float(cloud_index % 5) * 17.0, -85.0 - float(cloud_index % 6) * 28.0)
		add_child(cloud_center)
		for puff_index in range(5):
			var puff := MeshInstance3D.new()
			var puff_mesh := SphereMesh.new()
			puff_mesh.radius = 1.0
			puff_mesh.height = 2.0
			puff.mesh = puff_mesh
			puff.position = Vector3(float(puff_index) * 4.0 - 8.0, sin(float(puff_index) * 1.7) * 1.1, cos(float(puff_index) * 1.2) * 1.6)
			puff.scale = Vector3(5.0 + float(puff_index % 2) * 1.2, 2.5 + float(puff_index % 3) * 0.5, 3.6)
			puff.material_override = _mat(Color(0.82, 0.88, 0.91), 1.0)
			cloud_center.add_child(puff)

	# Small distant bird silhouettes add scale near the launch site. They are
	# separate world objects, so they do not rotate with the cockpit.
	for bird_index in range(9):
		var bird := Node3D.new()
		bird.name = "DistantBird_%02d" % bird_index
		bird.position = Vector3(-75.0 + float(bird_index) * 18.0, 22.0 + float(bird_index % 4) * 8.0, -55.0 - float(bird_index % 3) * 16.0)
		add_child(bird)
		var wing_left := _box(bird, Vector3(-0.22, 0.0, 0.0), Vector3(0.48, 0.035, 0.10), Color(0.12, 0.16, 0.18), 0.9, 0.0)
		wing_left.rotation_degrees.z = -12.0
		var wing_right := _box(bird, Vector3(0.22, 0.0, 0.0), Vector3(0.48, 0.035, 0.10), Color(0.12, 0.16, 0.18), 0.9, 0.0)
		wing_right.rotation_degrees.z = 12.0
		bird.scale = Vector3.ONE * (0.7 + float(bird_index % 3) * 0.18)
		sky_birds.append(bird)

	# Meteors are hidden until launch, then move past the window as the rocket
	# climbs. They are not parented to the cockpit.
	for meteor_index in range(5):
		var meteor := Node3D.new()
		meteor.name = "Meteor_%02d" % meteor_index
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.7
		rock_mesh.height = 1.2
		rock.mesh = rock_mesh
		rock.scale = Vector3(1.0, 0.8, 1.25)
		rock.material_override = _mat(Color(0.38, 0.31, 0.27), 0.95, 0.0)
		meteor.add_child(rock)
		var trail := _box(meteor, Vector3(0.0, 0.0, 1.2), Vector3(0.16, 0.16, 2.4), Color(0.95, 0.36, 0.12), 0.45, 0.0, true)
		trail.rotation_degrees.x = -18.0
		meteor.position = Vector3(-45.0 + float(meteor_index) * 23.0, 180.0 + float(meteor_index % 3) * 45.0, -110.0 - float(meteor_index % 2) * 35.0)
		meteor.visible = false
		add_child(meteor)
		sky_meteors.append(meteor)

	# Rocky asteroid field: irregularly scaled rocks at varied distances.
	for asteroid_index in range(22):
		var asteroid := Node3D.new()
		asteroid.name = "Asteroid_%02d" % asteroid_index
		var rock_mesh_instance := MeshInstance3D.new()
		var asteroid_mesh := SphereMesh.new()
		asteroid_mesh.radius = randf_range(0.8, 2.2)
		asteroid_mesh.height = asteroid_mesh.radius * 1.7
		asteroid_mesh.radial_segments = 8
		asteroid_mesh.rings = 5
		rock_mesh_instance.mesh = asteroid_mesh
		rock_mesh_instance.scale = Vector3(randf_range(0.65, 1.4), randf_range(0.6, 1.2), randf_range(0.7, 1.5))
		rock_mesh_instance.material_override = _mat(Color(0.25 + randf() * 0.13, 0.23 + randf() * 0.10, 0.20 + randf() * 0.08), 0.98, 0.0)
		asteroid.add_child(rock_mesh_instance)
		asteroid.position = Vector3(randf_range(-95.0, 95.0), randf_range(100.0, 380.0), randf_range(-180.0, -55.0))
		asteroid.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		asteroid.visible = false
		add_child(asteroid)
		sky_asteroids.append(asteroid)

func _build_launch_site() -> void:
	var pad := Node3D.new()
	pad.name = "LaunchComplex"
	launch_site = pad
	pad.position = ROCKET_START
	add_child(pad)
	_box(pad, Vector3(0.0, 0.0, 0.0), Vector3(18.0, 0.35, 18.0), Color(0.24, 0.28, 0.30), 0.75, 0.45)
	_box(pad, Vector3(0.0, 0.20, 0.0), Vector3(8.0, 0.12, 8.0), Color(0.40, 0.43, 0.43), 0.7, 0.35)
	for i in range(8):
		var stripe := _box(pad, Vector3(-6.2 + float(i) * 1.77, 0.19, 5.2), Vector3(0.85, 0.025, 0.34), Color(0.95, 0.64, 0.14), 0.65, 0.0)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Launch tower beside the rocket.
	var tower := Node3D.new()
	tower.position = Vector3(4.0, 0.0, -24.0)
	add_child(tower)
	_box(tower, Vector3(0.0, 5.0, 0.0), Vector3(0.45, 10.0, 0.45), Color(0.24, 0.28, 0.31), 0.55, 0.55)
	_box(tower, Vector3(1.0, 5.0, 0.0), Vector3(0.25, 10.0, 0.25), Color(0.34, 0.38, 0.40), 0.55, 0.5)
	for y in range(1, 10):
		_box(tower, Vector3(0.5, float(y), 0.0), Vector3(1.1, 0.12, 0.20), Color(0.36, 0.40, 0.42), 0.55, 0.4)
		_box(tower, Vector3(0.5, float(y) + 0.5, 0.0), Vector3(0.9, 0.07, 0.14), Color(0.18, 0.22, 0.24), 0.55, 0.4)
	_box(tower, Vector3(-0.7, 7.5, 0.0), Vector3(1.7, 0.22, 0.32), Color(0.33, 0.37, 0.39), 0.55, 0.5)

	# Apron lights and distant service structures.
	for side in [-1.0, 1.0]:
		for i in range(4):
			var lamp := MeshInstance3D.new()
			var lamp_mesh := CylinderMesh.new()
			lamp_mesh.top_radius = 0.06
			lamp_mesh.bottom_radius = 0.08
			lamp_mesh.height = 2.2
			lamp.mesh = lamp_mesh
			lamp.position = Vector3(side * (8.0 + float(i) * 3.0), 1.1, -18.0 - float(i) * 9.0)
			lamp.material_override = _mat(Color(0.32, 0.37, 0.40), 0.45, 0.55)
			add_child(lamp)
			_box(self, Vector3(lamp.position.x, 2.22, lamp.position.z), Vector3(0.25, 0.12, 0.25), Color(0.96, 0.78, 0.42), 0.3, 0.0, true)

func _build_rocket() -> void:
	rocket = Node3D.new()
	rocket.name = "LaunchVehicle"
	rocket.position = ROCKET_START
	add_child(rocket)

	rocket_body = MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.62
	body_mesh.bottom_radius = 0.62
	body_mesh.height = 5.8
	body_mesh.radial_segments = 32
	rocket_body.mesh = body_mesh
	rocket_body.position.y = 3.15
	rocket_body.material_override = _mat(Color(0.82, 0.85, 0.84), 0.28, 0.42)
	rocket.add_child(rocket_body)

	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.635
	band_mesh.bottom_radius = 0.635
	band_mesh.height = 0.34
	band.mesh = band_mesh
	band.position.y = 2.4
	band.material_override = _mat(Color(0.13, 0.18, 0.22), 0.3, 0.5)
	rocket.add_child(band)

	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 0.62
	nose_mesh.height = 1.45
	nose_mesh.radial_segments = 32
	nose.mesh = nose_mesh
	nose.position.y = 6.78
	nose.material_override = _mat(Color(0.75, 0.79, 0.80), 0.25, 0.35)
	rocket.add_child(nose)

	# Dark interstage and engine skirt.
	var skirt := MeshInstance3D.new()
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.top_radius = 0.60
	skirt_mesh.bottom_radius = 0.84
	skirt_mesh.height = 0.75
	skirt.mesh = skirt_mesh
	skirt.position.y = 0.65
	skirt.material_override = _mat(Color(0.16, 0.19, 0.21), 0.48, 0.62)
	rocket.add_child(skirt)

	for i in range(4):
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.14, 1.2, 1.0)
		fin.mesh = fin_mesh
		var a := float(i) * TAU / 4.0
		fin.position = Vector3(sin(a) * 0.72, 0.75, cos(a) * 0.72)
		fin.rotation.y = a
		fin.material_override = _mat(Color(0.22, 0.27, 0.29), 0.42, 0.48)
		rocket.add_child(fin)

	flame = MeshInstance3D.new()
	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = 0.08
	flame_mesh.bottom_radius = 0.46
	flame_mesh.height = 2.2
	flame_mesh.radial_segments = 20
	flame.mesh = flame_mesh
	flame.position.y = -0.72
	flame.material_override = _mat(Color(1.0, 0.48, 0.10), 0.25, 0.0, true)
	flame.visible = false
	rocket.add_child(flame)

func _build_cockpit() -> void:
	# Use the custom GLB cabin supplied with the project instead of the old
	# procedural cockpit blocks. The rig remains the pilot's eye point.
	cockpit_visuals = Node3D.new()
	cockpit_visuals.name = "CustomCockpitModelAnchor"
	cockpit_visuals.position = -COCKPIT_START
	cockpit_rig.add_child(cockpit_visuals)

	var cockpit_scene := load("res://rocket_ship_interior.glb") as PackedScene
	if cockpit_scene != null:
		var cockpit_model := cockpit_scene.instantiate() as Node3D
		cockpit_model.name = "CustomRocketInterior"
		# The GLB is authored at a large scale (about 80 units wide). The
		# cockpit_visuals anchor is offset back to world origin, while the
		# camera sits at COCKPIT_START. Put the model around that eye point:
		# positive local Y lifts its floor to the pilot's feet, and this Z
		# placement keeps the cabin around the camera instead of behind it.
		# The supplied GLB already uses Y-up coordinates and includes vertex
		# colours. Do not rotate it onto its side: that makes a large wall/floor
		# fill the camera. Keep its original up-axis and only turn it to face
		# the pilot's view. The model is centred around the cockpit camera.
		cockpit_model.scale = Vector3.ONE * 0.085
		cockpit_model.rotation = Vector3.ZERO
		cockpit_model.rotation.y = 0.0
		cockpit_model.position = Vector3(0.0, 0.0, 0.0)
		cockpit_visuals.add_child(cockpit_model)
	else:
		push_error("Could not load res://rocket_ship_interior.glb. In Godot, wait for the GLB import to finish, then run the project again.")

	# Keep live ESP32 readouts in the HUD, not floating over unknown model screens.
	cockpit_sensor_left = null
	cockpit_sensor_middle = null
	cockpit_sensor_right = null

func _instrument_text(initial_text: String, at: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = initial_text
	label.position = at
	# cockpit_visuals is rotated 180 degrees, so counter-rotate the labels
	# to make their text face the pilot instead of appearing backwards.
	label.rotation.y = PI
	label.font_size = size
	label.pixel_size = 0.01
	label.modulate = Color(0.72, 0.88, 0.82)
	label.outline_size = 3
	label.outline_modulate = Color(0.015, 0.035, 0.04)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cockpit_visuals.add_child(label)
	return label

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MissionHUD"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# Small title plate, not a giant floating banner.
	var title_plate := _panel(root, Vector2(26, 22), Vector2(330, 68), Color(0.12, 0.15, 0.18, 0.94), Color(0.12, 0.15, 0.18))
	var title_stack := VBoxContainer.new()
	title_stack.add_theme_constant_override("separation", 2)
	title_plate.add_child(title_stack)
	var title := _label("LAUNCH CONTROL", 18, Color(0.78, 0.91, 0.95))
	title_stack.add_child(title)
	title_stack.add_child(_label("VEHICLE ASCENT TEST", 10, Color(0.53, 0.70, 0.76)))

	# Setup panel at top left, styled like a compact instrument console.
	setup_panel = _panel(root, Vector2(26, 106), Vector2(340, 355), Color(0.15, 0.17, 0.20, 0.96), Color(0.15, 0.17, 0.20))
	var setup_box := VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 8)
	setup_panel.add_child(setup_box)
	setup_box.add_child(_label("PRE-LAUNCH CHECKLIST", 17, Color(0.80, 0.92, 0.95)))
	setup_box.add_child(_label("Configure the vehicle before ignition.", 11, Color(0.56, 0.68, 0.72)))
	fuel_slider = _add_slider(setup_box, "FUEL LOAD", 60, 100, 100, "%")
	thrust_slider = _add_slider(setup_box, "ENGINE OUTPUT", 30, 100, 75, "%")
	angle_slider = _add_slider(setup_box, "PITCH ANGLE", 0, 45, 5, "°")
	angle_slider.value_changed.connect(func(value: float):
		angle_setting = value
		_update_cockpit_pitch()
	)
	hardware_label = Label.new()
	hardware_label.text = "ESP32: waiting for bridge\nHumidity must reach 80% to unlock"
	hardware_label.add_theme_font_size_override("font_size", 11)
	hardware_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
	hardware_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_box.add_child(hardware_label)

	launch_button = Button.new()
	launch_button.text = "IGNITION SEQUENCE"
	launch_button.custom_minimum_size = Vector2(0, 43)
	launch_button.add_theme_font_size_override("font_size", 14)
	launch_button.add_theme_color_override("font_color", Color(0.96, 1.0, 0.98))
	launch_button.add_theme_stylebox_override("normal", _button_style(Color(0.045, 0.31, 0.29), Color(0.20, 0.78, 0.61)))
	launch_button.add_theme_stylebox_override("hover", _button_style(Color(0.06, 0.42, 0.37), Color(0.32, 0.95, 0.72)))
	launch_button.add_theme_stylebox_override("pressed", _button_style(Color(0.025, 0.20, 0.18), Color(0.20, 0.78, 0.61)))
	launch_button.pressed.connect(_on_launch_pressed)
	setup_box.add_child(launch_button)

	reset_button = Button.new()
	reset_button.text = "RESET CONFIGURATION"
	reset_button.custom_minimum_size = Vector2(0, 34)
	reset_button.add_theme_font_size_override("font_size", 12)
	reset_button.add_theme_color_override("font_color", Color(0.78, 0.84, 0.86))
	reset_button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.10, 0.11), Color(0.25, 0.32, 0.34)))
	reset_button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.17, 0.18), Color(0.36, 0.48, 0.50)))
	reset_button.pressed.connect(_on_reset_pressed)
	setup_box.add_child(reset_button)

	status_label = _label("SYSTEM READY  /  AWAITING CONFIGURATION", 10, Color(0.39, 0.91, 0.68))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_box.add_child(status_label)

	# Telemetry card on the right.
	var telem_panel := _panel(root, Vector2(1, 22), Vector2(300, 238), Color(0.15, 0.17, 0.20, 0.96), Color(0.15, 0.17, 0.20))
	telemetry_panel = telem_panel
	telem_panel.anchor_left = 1.0
	telem_panel.anchor_right = 1.0
	telem_panel.offset_left = -324.0
	telem_panel.offset_right = -24.0
	telem_panel.offset_top = 22.0
	telem_panel.offset_bottom = 260.0
	var telem_box := VBoxContainer.new()
	telem_box.add_theme_constant_override("separation", 6)
	telem_panel.add_child(telem_box)
	telem_box.add_child(_label("LIVE TELEMETRY", 16, Color(0.80, 0.92, 0.95)))
	telem_box.add_child(_rule())
	altitude_value = _label("ALTITUDE          000 m", 14, Color(0.87, 0.94, 0.95))
	speed_value = _label("VELOCITY        0.0 m/s", 14, Color(0.87, 0.94, 0.95))
	fuel_value = _label("FUEL REMAINING       72%", 14, Color(0.87, 0.94, 0.95))
	time_value = _label("MISSION TIME      00:00", 14, Color(0.87, 0.94, 0.95))
	telem_box.add_child(altitude_value)
	telem_box.add_child(speed_value)
	telem_box.add_child(fuel_value)
	telem_box.add_child(time_value)
	telem_box.add_child(_rule())
	telem_box.add_child(_label("TARGET  /  1,000 m", 12, Color(0.40, 0.81, 0.92)))

	# Minimal mission/status strip near the top center.
	var mission := _panel(root, Vector2(440, 22), Vector2(300, 38), Color(0.15, 0.17, 0.20, 0.90), Color(0.15, 0.17, 0.20))
	mission.anchor_left = 0.5
	mission.anchor_right = 0.5
	mission.offset_left = -150.0
	mission.offset_right = 150.0
	mission.offset_top = 22.0
	mission.offset_bottom = 60.0
	var mission_label := _label("MISSION 001 · ASCENT TEST", 11, Color(0.72, 0.84, 0.87))
	mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission.add_child(mission_label)

	result_label = _label("MISSION OBJECTIVE: Reach 1,000 m altitude.", 13, Color(0.88, 0.94, 0.95))
	result_label.anchor_left = 0.5
	result_label.anchor_right = 0.5
	result_label.offset_left = -250.0
	result_label.offset_right = 250.0
	result_label.anchor_top = 1.0
	result_label.anchor_bottom = 1.0
	result_label.offset_top = -122.0
	result_label.offset_bottom = -100.0
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(result_label)

	# A small always-visible cockpit dashboard sits at the bottom of the view.
	# The full controls and telemetry can be opened as a menu when needed.
	dashboard_panel = _panel(root, Vector2.ZERO, Vector2(620, 78), Color(0.015, 0.025, 0.032, 0.90), Color(0.16, 0.42, 0.49))
	dashboard_panel.anchor_left = 0.5
	dashboard_panel.anchor_right = 0.5
	dashboard_panel.anchor_top = 1.0
	dashboard_panel.anchor_bottom = 1.0
	dashboard_panel.offset_left = -310.0
	dashboard_panel.offset_right = 310.0
	dashboard_panel.offset_top = -96.0
	dashboard_panel.offset_bottom = -12.0
	var dash_box := VBoxContainer.new()
	dash_box.add_theme_constant_override("separation", 3)
	dashboard_panel.add_child(dash_box)
	dash_box.add_child(_label("COCKPIT INSTRUMENTS", 11, Color(0.45, 0.78, 0.83)))
	dashboard_label = _label("ALT 000 m   SPEED 0 m/s   FUEL 100%   PITCH 5°", 13, Color(0.88, 0.96, 0.96))
	dash_box.add_child(dashboard_label)
	puzzle_label = _label("POT: WAIT   ANGLE: WAIT   THRUST: WAIT", 9, Color(0.94, 0.72, 0.32))
	dash_box.add_child(puzzle_label)

	# The breathalyser gate is intentionally prominent. In this game, the existing
	# DHT11 humidity reading is used as a fictional breathalyser-style check.
	breathalyzer_panel = _panel(root, Vector2(26, 100), Vector2(330, 104), Color(0.24, 0.17, 0.11, 0.97), Color(0.24, 0.17, 0.11))
	breathalyzer_panel.anchor_left = 0.0
	breathalyzer_panel.anchor_right = 0.0
	breathalyzer_panel.anchor_top = 0.0
	breathalyzer_panel.anchor_bottom = 0.0
	breathalyzer_panel.offset_left = 26.0
	breathalyzer_panel.offset_right = 356.0
	breathalyzer_panel.offset_top = 100.0
	breathalyzer_panel.offset_bottom = 204.0
	var breath_box := VBoxContainer.new()
	breath_box.add_theme_constant_override("separation", 5)
	breathalyzer_panel.add_child(breath_box)
	breath_box.add_child(_label("SENSOR CHECK", 14, Color(1.0, 0.73, 0.37)))
	breathalyzer_label = _label("WAITING FOR SENSOR...  /  REQUIRED: 80%", 12, Color(0.98, 0.88, 0.74))
	breath_box.add_child(breathalyzer_label)
	breathalyzer_bar = ProgressBar.new()
	breathalyzer_bar.min_value = 0.0
	breathalyzer_bar.max_value = 80.0
	breathalyzer_bar.value = 0.0
	breathalyzer_bar.show_percentage = false
	breathalyzer_bar.custom_minimum_size.y = 16.0
	breath_box.add_child(breathalyzer_bar)
	breath_box.add_child(_label("Pass this, then complete calibrations.", 9, Color(0.80, 0.69, 0.57)))

	countdown_label = _label("EARTH COLLAPSE IN 01:30", 17, Color(1.0, 0.36, 0.25))
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.offset_left = -160.0
	countdown_label.offset_right = 160.0
	countdown_label.offset_top = 78.0
	countdown_label.offset_bottom = 106.0
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(countdown_label)

	menu_toggle_button = Button.new()
	menu_toggle_button.text = "MENU"
	menu_toggle_button.anchor_left = 1.0
	menu_toggle_button.anchor_right = 1.0
	menu_toggle_button.offset_left = -108.0
	menu_toggle_button.offset_right = -26.0
	menu_toggle_button.offset_top = 22.0
	menu_toggle_button.offset_bottom = 56.0
	menu_toggle_button.custom_minimum_size = Vector2(82.0, 34.0)
	menu_toggle_button.add_theme_font_size_override("font_size", 12)
	menu_toggle_button.add_theme_stylebox_override("normal", _button_style(Color(0.025, 0.045, 0.06, 0.95), Color(0.24, 0.55, 0.68)))
	menu_toggle_button.add_theme_stylebox_override("hover", _button_style(Color(0.06, 0.12, 0.15, 0.98), Color(0.32, 0.78, 0.88)))
	menu_toggle_button.pressed.connect(_toggle_menu)
	root.add_child(menu_toggle_button)

	# Large, always-visible launch control. The detailed checklist can stay hidden
	# in MENU, but the main action remains easy to find in the cockpit view.
	cockpit_launch_button = Button.new()
	cockpit_launch_button.name = "CockpitLaunchButton"
	cockpit_launch_button.text = "LAUNCH ROCKET"
	cockpit_launch_button.anchor_left = 0.5
	cockpit_launch_button.anchor_right = 0.5
	cockpit_launch_button.anchor_top = 1.0
	cockpit_launch_button.anchor_bottom = 1.0
	cockpit_launch_button.offset_left = -130.0
	cockpit_launch_button.offset_right = 130.0
	cockpit_launch_button.offset_top = -164.0
	cockpit_launch_button.offset_bottom = -120.0
	cockpit_launch_button.custom_minimum_size = Vector2(0.0, 40.0)
	cockpit_launch_button.add_theme_font_size_override("font_size", 12)
	cockpit_launch_button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.96))
	cockpit_launch_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	cockpit_launch_button.add_theme_stylebox_override("normal", _button_style(Color(0.70, 0.12, 0.055), Color(1.0, 0.48, 0.18)))
	cockpit_launch_button.add_theme_stylebox_override("hover", _button_style(Color(0.90, 0.20, 0.07), Color(1.0, 0.78, 0.25)))
	cockpit_launch_button.add_theme_stylebox_override("pressed", _button_style(Color(0.42, 0.07, 0.035), Color(1.0, 0.48, 0.18)))
	cockpit_launch_button.add_theme_stylebox_override("disabled", _button_style(Color(0.16, 0.18, 0.18), Color(0.34, 0.38, 0.38)))
	cockpit_launch_button.pressed.connect(_on_launch_pressed)
	root.add_child(cockpit_launch_button)

	# A reset control stays visible even when the menu is closed, and its right
	# edge is anchored to the viewport so it does not drift off small screens.
	quick_reset_button = Button.new()
	quick_reset_button.name = "QuickResetButton"
	quick_reset_button.text = "RESET MISSION"
	quick_reset_button.anchor_left = 1.0
	quick_reset_button.anchor_right = 1.0
	quick_reset_button.anchor_top = 0.0
	quick_reset_button.anchor_bottom = 0.0
	quick_reset_button.offset_left = -156.0
	quick_reset_button.offset_right = -20.0
	quick_reset_button.offset_top = 68.0
	quick_reset_button.offset_bottom = 106.0
	quick_reset_button.add_theme_font_size_override("font_size", 12)
	quick_reset_button.add_theme_color_override("font_color", Color(0.88, 0.93, 0.95))
	quick_reset_button.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.14, 0.17), Color(0.32, 0.48, 0.54)))
	quick_reset_button.add_theme_stylebox_override("hover", _button_style(Color(0.17, 0.23, 0.27), Color(0.48, 0.70, 0.76)))
	quick_reset_button.pressed.connect(_on_reset_pressed)
	root.add_child(quick_reset_button)

	setup_panel.visible = false
	telemetry_panel.visible = false
	menu_is_open = false

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", _panel_style(bg, border))
	parent.add_child(panel)
	return panel

func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.34, 0.39, 0.44, 0.72)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _add_slider(parent: VBoxContainer, caption: String, min_value: float, max_value: float, initial: float, suffix: String) -> HSlider:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	parent.add_child(group)
	var row := HBoxContainer.new()
	group.add_child(row)
	var name_label := _label(caption, 11, Color(0.66, 0.79, 0.82))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _label(str(int(initial)) + suffix, 12, Color(0.48, 0.84, 0.92))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size.x = 48
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 1
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(slider)
	slider.value_changed.connect(func(value: float):
		value_label.text = str(int(value)) + suffix
	)
	return slider

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(0)
	style.set_corner_radius_all(12)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(0)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style

func _mat(color: Color, roughness: float = 0.55, metallic: float = 0.0, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.1
	return material

func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, color: Color, roughness: float = 0.55, metallic: float = 0.0, emissive: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color, roughness, metallic, emissive)
	parent.add_child(mesh_instance)
	return mesh_instance

func _connect_hardware_bridge() -> void:
	# The Python bridge forwards USB serial CSV from the ESP32 to localhost:8765.
	var err := serial_socket.connect_to_host("127.0.0.1", 8765)
	if err != OK:
		print("ESP32 bridge not connected. Start esp32_serial_bridge.py before running Godot.")

func _poll_hardware() -> void:
	serial_socket.poll()
	hardware_connected = serial_socket.get_status() == StreamPeerTCP.STATUS_CONNECTED
	if not hardware_connected:
		humidity_unlocked = false
	if hardware_connected:
		var available := serial_socket.get_available_bytes()
		if available > 0:
			var packet := serial_socket.get_data(available)
			if packet[0] == OK:
				serial_buffer += packet[1].get_string_from_utf8()
				while serial_buffer.contains("\n"):
					var split_at := serial_buffer.find("\n")
					var line := serial_buffer.substr(0, split_at).strip_edges()
					serial_buffer = serial_buffer.substr(split_at + 1)
					_parse_hardware_line(line)

	if hardware_connected and humidity_value >= 0.0 and not humidity_unlocked:
		fuel_slider.editable = false
		thrust_slider.editable = false
		angle_slider.editable = false
	elif hardware_connected and humidity_unlocked and not is_flying and not game_over:
		fuel_slider.editable = true
		thrust_slider.editable = true
		angle_slider.editable = true
	if is_instance_valid(launch_button):
		launch_button.disabled = not _preflight_passed() or is_flying or game_over or mission_complete
	_sync_launch_buttons()

	if not is_instance_valid(hardware_label):
		return
	if not hardware_connected:
		hardware_label.text = "ESP32 OFFLINE — start the serial bridge"
		hardware_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.35))
	elif humidity_value < 0.0:
		hardware_label.text = "ESP32 CONNECTED — waiting for DHT11"
	elif humidity_unlocked:
		hardware_label.text = "ESP32 ONLINE  |  HUMIDITY %.0f%%  |  UNLOCKED" % humidity_value
		hardware_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.58))
	else:
		hardware_label.text = "LOCKED  |  HUMIDITY %.0f%% / 80%%" % humidity_value
		hardware_label.add_theme_color_override("font_color", Color(1.0, 0.52, 0.36))

func _parse_hardware_line(line: String) -> void:
	# CSV order: temperature,humidity,front,back,pot,encoder,encoder_button
	var fields := line.split(",")
	if fields.size() < 7:
		return
	var new_front := fields[2].strip_edges() == "1"
	var new_back := fields[3].strip_edges() == "1"
	hardware_temp = fields[0].to_float()
	humidity_value = fields[1].to_float()
	hardware_front = new_front
	hardware_back = new_back
	hardware_pot = clampi(fields[4].to_int(), 0, 4095)
	hardware_angle = clampi(fields[5].to_int(), 0, 100)
	hardware_encoder_button = fields[6].strip_edges() == "1"
	var previously_unlocked := humidity_unlocked
	humidity_unlocked = humidity_value >= 80.0
	if humidity_unlocked and not previously_unlocked:
		_set_status("HUMIDITY CHECK PASSED — CONTROLS UNLOCKED", Color(0.4, 1.0, 0.58))
	elif previously_unlocked and not humidity_unlocked and not is_flying:
		_set_status("LAUNCH LOCKED — HUMIDITY BELOW 80%", Color(1.0, 0.52, 0.36))

	if not is_flying:
		fuel_slider.value = lerpf(20.0, 100.0, float(hardware_pot) / 4095.0)
		angle_slider.value = lerpf(0.0, 45.0, float(hardware_angle) / 100.0)
		angle_setting = angle_slider.value
		_update_cockpit_pitch()
	else:
		thrust_setting = lerpf(0.0, 100.0, float(hardware_pot) / 4095.0)
		thrust_slider.value = thrust_setting

	if not is_flying and hardware_front and not last_hardware_front and humidity_unlocked:
		_on_launch_pressed()
	if hardware_back and not last_hardware_back:
		_on_reset_pressed()
	last_hardware_front = hardware_front
	last_hardware_back = hardware_back

func _on_launch_pressed() -> void:
	if is_flying or game_over or not _preflight_passed():
		return
	fuel_initial = fuel_slider.value
	fuel_left = fuel_initial
	thrust_setting = thrust_slider.value
	angle_setting = angle_slider.value
	altitude = 0.0
	vertical_speed = 0.0
	horizontal_speed = 0.0
	flight_velocity = Vector3.ZERO
	flight_time = 0.0
	cockpit_rig.position = COCKPIT_START
	mouse_look_yaw = 0.0
	mouse_look_pitch = 0.0
	camera.rotation = Vector3.ZERO
	_update_cockpit_pitch()
	is_flying = true
	mission_complete = false
	flight_ended = false
	rocket.position = ROCKET_START
	rocket.rotation = Vector3.ZERO
	# Engine state is represented by cockpit indicators and flight telemetry, not an exterior rocket view.
	flame.visible = false
	launch_button.disabled = true
	_sync_launch_buttons()
	fuel_slider.editable = false
	thrust_slider.editable = false
	angle_slider.editable = false
	_set_status("ENGINE IGNITION  /  ASCENT STARTED", Color(1.0, 0.72, 0.28))
	result_label.text = "MISSION IN PROGRESS — REACH 1,000 m BEFORE THE 150 s TIMER EXPIRES."

func _on_reset_pressed() -> void:
	_reset_flight(true)

func _reset_flight(show_message: bool) -> void:
	is_flying = false
	mission_complete = false
	flight_ended = false
	altitude = 0.0
	vertical_speed = 0.0
	horizontal_speed = 0.0
	flight_velocity = Vector3.ZERO
	flight_time = 0.0
	earth_timer_remaining = 150.0
	game_over = false
	pot_puzzle_seconds = 0.0
	angle_puzzle_seconds = 0.0
	pot_puzzle_complete = false
	angle_puzzle_complete = false
	thrust_puzzle_seconds = 0.0
	thrust_puzzle_complete = false
	fuel_initial = fuel_slider.value if is_instance_valid(fuel_slider) else 100.0
	fuel_left = fuel_initial
	thrust_setting = thrust_slider.value if is_instance_valid(thrust_slider) else 75.0
	angle_setting = angle_slider.value if is_instance_valid(angle_slider) else 5.0
	if is_instance_valid(rocket):
		rocket.position = ROCKET_START
		rocket.rotation = Vector3.ZERO
	# The launch pad and ground stay fixed in world space. Reset the cockpit rig
	# instead of dragging the scenery to fake altitude.
	if is_instance_valid(cockpit_rig):
		cockpit_rig.position = COCKPIT_START
		if is_instance_valid(camera):
			camera.position = camera_home
			camera.rotation = Vector3.ZERO
		mouse_look_yaw = 0.0
		mouse_look_pitch = 0.0
		_update_cockpit_pitch()
	if is_instance_valid(flame):
		flame.visible = false
	if is_instance_valid(launch_button):
		launch_button.disabled = not _preflight_passed()
	fuel_slider.editable = true
	thrust_slider.editable = true
	angle_slider.editable = true
	_sync_launch_buttons()
	if is_instance_valid(status_label):
		_set_status("SYSTEM READY  /  AWAITING CONFIGURATION", Color(0.39, 0.91, 0.68))
	if is_instance_valid(result_label):
		result_label.text = "MISSION 001 OBJECTIVE: REACH 1,000 m BEFORE THE 150 s FLIGHT TIMER EXPIRES."
	_update_telemetry()
	if show_message:
		print("Flight configuration reset.")

func _process(delta: float) -> void:
	_poll_hardware()
	_animate_sky_objects(delta)
	if is_flying and not mission_complete and not game_over:
		earth_timer_remaining = maxf(0.0, earth_timer_remaining - delta)
		if earth_timer_remaining <= 0.0:
			game_over = true
			is_flying = false
			if is_instance_valid(flame):
				flame.visible = false
			_finish_controls()
			_set_status("EARTH DESTROYED  /  TIME EXPIRED", Color(1.0, 0.22, 0.16))
			if is_instance_valid(result_label):
				result_label.text = "MISSION FAILED — EARTH'S COUNTDOWN REACHED ZERO"
	_update_puzzles(delta)
	if is_flying and not game_over:
		_simulate_flight(delta)
	_update_telemetry()
	_update_dashboard()
	_sync_launch_buttons()

func _animate_sky_objects(delta: float) -> void:
	for i in range(sky_birds.size()):
		var bird := sky_birds[i]
		bird.position.x += delta * (1.5 + float(i % 3) * 0.35)
		bird.position.y += sin(Time.get_ticks_msec() * 0.001 + float(i)) * delta * 0.4
		if bird.position.x > 150.0:
			bird.position.x = -150.0
	for i in range(sky_asteroids.size()):
		var asteroid := sky_asteroids[i]
		asteroid.visible = is_flying
		if asteroid.visible:
			asteroid.rotation += Vector3(delta * (0.08 + float(i % 4) * 0.025), delta * (0.12 + float(i % 3) * 0.03), delta * 0.06)
			asteroid.position.z += delta * (1.0 + float(i % 5) * 0.45)
			if asteroid.position.distance_to(cockpit_rig.global_position) > 260.0 or asteroid.position.z > cockpit_rig.global_position.z + 20.0:
				asteroid.position = cockpit_rig.global_position + Vector3(randf_range(-95.0, 95.0), randf_range(45.0, 160.0), randf_range(-180.0, -70.0))
	for i in range(sky_meteors.size()):
		var meteor := sky_meteors[i]
		meteor.visible = is_flying and fuel_left > 0.0
		if meteor.visible:
			meteor.position += Vector3(-delta * (3.0 + float(i % 2)), -delta * (1.5 + float(i % 3)), delta * 2.0)
			if meteor.position.distance_to(cockpit_rig.global_position) > 260.0:
				meteor.position = cockpit_rig.global_position + Vector3(randf_range(-65.0, 65.0), randf_range(45.0, 100.0), randf_range(-110.0, -45.0))

func _simulate_flight(delta: float) -> void:
	flight_time += delta

	# Pitch angle is the cockpit's real view/flight direction above the horizon.
	# The rig rotates before launch, then this same forward vector drives motion.
	var flight_direction := -cockpit_rig.global_transform.basis.z.normalized()
	var thrust_accel := (thrust_setting / 100.0) * 45.0
	var burn_rate := 0.22 + (thrust_setting / 100.0) * 0.42

	if fuel_left > 0.0:
		fuel_left = maxf(0.0, fuel_left - burn_rate * delta)
		flight_velocity += flight_direction * thrust_accel * delta
		flame.visible = true
	else:
		flame.visible = false

	# Gravity always acts downward in world space. The launch pad and terrain
	# are static; the cockpit rises through the world instead of moving the world.
	flight_velocity.y -= 9.81 * delta
	cockpit_rig.global_position += flight_velocity * delta

	altitude = maxf(0.0, cockpit_rig.global_position.y - COCKPIT_START.y)
	vertical_speed = flight_velocity.y
	horizontal_speed = Vector2(flight_velocity.x, flight_velocity.z).length()

	# Tiny local vibration during powered flight. This never changes the rig's
	# position or pitch and therefore cannot fake the launch angle.
	var shake_strength := 0.012 if fuel_left > 0.0 else 0.003
	camera.position = camera_home + Vector3(
		sin(flight_time * 31.0) * shake_strength,
		sin(flight_time * 43.0) * shake_strength,
		0.0
	)

	if altitude >= TARGET_ALTITUDE and not mission_complete:
		mission_complete = true
		is_flying = false
		flame.visible = false
		_finish_controls()
		_set_status("MISSION SUCCESS  /  TARGET ALTITUDE REACHED", Color(0.38, 0.96, 0.67))
		result_label.text = "MISSION COMPLETE  —  ALTITUDE %.0f m" % altitude
		return

	if cockpit_rig.global_position.y <= COCKPIT_START.y and flight_velocity.y <= 0.0 and flight_time > 1.0 and not flight_ended:
		flight_ended = true
		is_flying = false
		cockpit_rig.global_position.y = COCKPIT_START.y
		flame.visible = false
		_finish_controls()
		_set_status("ASCENT ENDED  /  ALTITUDE NOT REACHED", Color(1.0, 0.56, 0.34))
		result_label.text = "MISSION FAILED — TARGET ALTITUDE NOT REACHED. PRESS RESET MISSION TO TRY AGAIN."

func _finish_controls() -> void:
	launch_button.disabled = game_over or mission_complete or not _preflight_passed()
	_sync_launch_buttons()
	fuel_slider.editable = not game_over and not mission_complete
	thrust_slider.editable = not game_over and not mission_complete
	angle_slider.editable = not game_over and not mission_complete


func _update_cockpit_pitch() -> void:
	# The encoder value is the rocket's actual angle above the horizon.
	# Mouse-look rotation is applied to the Camera3D separately, so looking
	# around does not secretly change the vehicle's flight direction.
	if not is_instance_valid(cockpit_rig):
		return
	cockpit_rig.rotation = Vector3(deg_to_rad(clampf(angle_setting, 0.0, 45.0)), 0.0, 0.0)

func _preflight_passed() -> bool:
	var breath_check_passed := humidity_unlocked if hardware_connected else false
	return breath_check_passed and pot_puzzle_complete and angle_puzzle_complete and thrust_puzzle_complete

func _update_puzzles(delta: float) -> void:
	if is_flying or game_over or mission_complete:
		return

	var pot_percent := fuel_slider.value if is_instance_valid(fuel_slider) else 0.0
	var angle_degrees := angle_setting
	var thrust_percent := thrust_slider.value if is_instance_valid(thrust_slider) else 0.0
	if pot_percent >= 45.0 and pot_percent <= 65.0:
		pot_puzzle_seconds += delta
		if pot_puzzle_seconds >= PUZZLE_HOLD_SECONDS:
			pot_puzzle_complete = true
	else:
		pot_puzzle_seconds = 0.0
		pot_puzzle_complete = false

	if angle_degrees >= 15.0 and angle_degrees <= 30.0:
		angle_puzzle_seconds += delta
		if angle_puzzle_seconds >= PUZZLE_HOLD_SECONDS:
			angle_puzzle_complete = true
	else:
		angle_puzzle_seconds = 0.0
		angle_puzzle_complete = false

	if thrust_percent >= 65.0 and thrust_percent <= 85.0:
		thrust_puzzle_seconds += delta
		if thrust_puzzle_seconds >= PUZZLE_HOLD_SECONDS:
			thrust_puzzle_complete = true
	else:
		thrust_puzzle_seconds = 0.0
		thrust_puzzle_complete = false

	if is_instance_valid(launch_button):
		launch_button.disabled = not _preflight_passed()
	_sync_launch_buttons()

func _sync_launch_buttons() -> void:
	var blocked := not _preflight_passed() or is_flying or game_over or mission_complete
	if is_instance_valid(launch_button):
		launch_button.disabled = blocked
	if is_instance_valid(cockpit_launch_button):
		cockpit_launch_button.disabled = blocked
		if game_over:
			cockpit_launch_button.text = "EARTH LOST"
		elif mission_complete:
			cockpit_launch_button.text = "MISSION COMPLETE"
		elif is_flying:
			cockpit_launch_button.text = "ROCKET IN FLIGHT"
		elif blocked:
			cockpit_launch_button.text = "COMPLETE CHECKS TO LAUNCH"
		else:
			cockpit_launch_button.text = "LAUNCH ROCKET"

func _update_dashboard() -> void:
	if is_instance_valid(countdown_label):
		var remaining := int(ceil(earth_timer_remaining))
		countdown_label.text = "FLIGHT TIMER %02d:%02d" % [remaining / 60, remaining % 60]
		if earth_timer_remaining <= 15.0:
			countdown_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.12))
		elif earth_timer_remaining <= 35.0:
			countdown_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.22))

	if is_instance_valid(dashboard_label):
		dashboard_label.text = "ALT %04.0f m    SPEED %05.1f m/s    FUEL %02.0f%%    PITCH %02.0f°" % [maxf(altitude, 0.0), sqrt(vertical_speed * vertical_speed + horizontal_speed * horizontal_speed), maxf(fuel_left, 0.0), angle_setting]

	if is_instance_valid(puzzle_label):
		var pot_text := "PASS" if pot_puzzle_complete else "SET POT TO 45-65%% (%.1f/%.1fs)" % [minf(pot_puzzle_seconds, PUZZLE_HOLD_SECONDS), PUZZLE_HOLD_SECONDS]
		var angle_text := "PASS" if angle_puzzle_complete else "SET ANGLE TO 15-30° (%.1f/%.1fs)" % [minf(angle_puzzle_seconds, PUZZLE_HOLD_SECONDS), PUZZLE_HOLD_SECONDS]
		var thrust_text := "PASS" if thrust_puzzle_complete else "SET THRUST TO 65-85%% (%.1f/%.1fs)" % [minf(thrust_puzzle_seconds, PUZZLE_HOLD_SECONDS), PUZZLE_HOLD_SECONDS]
		puzzle_label.text = "POT: %s   |   ANGLE: %s   |   THRUST: %s" % [pot_text, angle_text, thrust_text]
		puzzle_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.58) if pot_puzzle_complete and angle_puzzle_complete and thrust_puzzle_complete else Color(0.98, 0.73, 0.34))

	if is_instance_valid(breathalyzer_label):
		if not hardware_connected:
			breathalyzer_label.text = "SENSOR OFFLINE — CONNECT ESP32 (80% REQUIRED)"
		elif humidity_value < 0.0:
			breathalyzer_label.text = "WAITING FOR HUMIDITY SENSOR..."
		elif humidity_unlocked:
			breathalyzer_label.text = "PASS — SENSOR %.0f%% / 80%% REQUIRED" % humidity_value
		else:
			breathalyzer_label.text = "LOCKED — SENSOR %.0f%% / 80%% REQUIRED" % humidity_value
		breathalyzer_bar.value = clampf(humidity_value, 0.0, 80.0) if humidity_value >= 0.0 else 0.0
		breathalyzer_panel.visible = not menu_is_open and not humidity_unlocked and not is_flying and not game_over


func _toggle_menu() -> void:
	menu_is_open = not menu_is_open
	setup_panel.visible = menu_is_open
	telemetry_panel.visible = menu_is_open
	menu_toggle_button.text = "CLOSE" if menu_is_open else "MENU"
	if menu_is_open:
		mouse_look_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		mouse_look_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not menu_is_open and not mouse_look_enabled:
		mouse_look_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not menu_is_open:
		mouse_look_enabled = not mouse_look_enabled
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_look_enabled else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and mouse_look_enabled and not menu_is_open:
		mouse_look_yaw -= event.relative.x * mouse_sensitivity
		mouse_look_pitch -= event.relative.y * mouse_sensitivity
		mouse_look_pitch = clampf(mouse_look_pitch, deg_to_rad(-65.0), deg_to_rad(65.0))
		if is_instance_valid(camera):
			camera.rotation = Vector3(mouse_look_pitch, mouse_look_yaw, 0.0)

func _update_telemetry() -> void:
	if not is_instance_valid(altitude_value):
		return
	var speed := sqrt(vertical_speed * vertical_speed + horizontal_speed * horizontal_speed)
	altitude_value.text = "ALTITUDE          %04.0f m" % maxf(altitude, 0.0)
	speed_value.text = "VELOCITY        %05.1f m/s" % speed
	fuel_value.text = "FUEL REMAINING       %02.0f%%" % maxf(fuel_left, 0.0)
	var minutes := int(flight_time / 60.0)
	var seconds := int(fmod(flight_time, 60.0))
	time_value.text = "MISSION TIME      %02d:%02d" % [minutes, seconds]

func _set_status(message: String, color: Color) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
		status_label.add_theme_color_override("font_color", color)
