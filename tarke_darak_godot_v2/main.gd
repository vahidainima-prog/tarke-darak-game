extends Node3D

# Godot 4.x — visual mechanics test. Side camera looks along -Z.
# Feint depth: negative Z is BEHIND the attacker; positive Z is IN FRONT.
const DEF_X := 1.55
const MIN_X := -4.7
const MAX_X := 0.35
const SWING_SECONDS := 0.62
const STICK_LENGTH := 2.15
const STICK_RADIUS := 0.055
const GUARD_RADIUS := 0.09

var attacker: Node3D
var defender: Node3D
var terkeh: MeshInstance3D
var darak: MeshInstance3D
var attack_x := -2.7
var swing := -1.0
var swing_finished := false
var defending := false
var opponent_delay := -1.0
var feint_depth := 0.0
var feint_target := 0.0
var guard_shift := 0.0
var guard_target := 0.0
var score_hit := 0
var score_block := 0
var status: Label
var header: Label
var detail: Label
var attack_hand_a: MeshInstance3D
var attack_hand_b: MeshInstance3D
var defend_hand: MeshInstance3D
var attack_arm_a: MeshInstance3D
var attack_arm_b: MeshInstance3D
var defend_arm: MeshInstance3D
var last_outcome := ""

func material(c: Color) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = c
 m.roughness = 0.8
 return m

func block(parent: Node3D, name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 n.name = name
 var mesh := BoxMesh.new()
 mesh.size = size
 n.mesh = mesh
 n.material_override = material(color)
 parent.add_child(n)
 n.position = at
 return n

func rod(parent: Node3D, name: String, radius: float, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 n.name = name
 var mesh := CylinderMesh.new()
 mesh.top_radius = radius
 mesh.bottom_radius = radius
 mesh.height = 1.0
 n.mesh = mesh
 n.material_override = material(color)
 parent.add_child(n)
 return n

func place_rod(n: MeshInstance3D, a: Vector3, b: Vector3) -> void:
 var v := b - a
 n.position = (a + b) * 0.5
 if v.length() > 0.001:
  n.quaternion = Quaternion(Vector3.UP, v.normalized())
 (n.mesh as CylinderMesh).height = maxf(v.length(), 0.01)

func person(name: String, x: float, face_right: bool) -> Node3D:
 var root := Node3D.new()
 root.name = name
 add_child(root)
 root.position.x = x
 var cloth := Color(0.86, 0.81, 0.66)
 var black := Color(0.065, 0.07, 0.085)
 var skin := Color(0.65, 0.45, 0.32)
 block(root, "Chogha", Vector3(0.62, 0.90, 0.38), Vector3(0, 1.57, 0), cloth)
 for off in [-0.18, -0.05, 0.10, 0.22]:
  block(root, "Stripe", Vector3(0.043, 0.85, 0.39), Vector3(off, 1.57, 0), black)
 for side in [-1.0, 1.0]:
  block(root, "Debit trousers", Vector3(0.33, 0.91, 0.43), Vector3(side * 0.18, 0.70, 0), black)
  block(root, "Giveh", Vector3(0.40, 0.18, 0.52), Vector3(side * 0.18 + (0.08 if face_right else -0.08), 0.12, 0.09), cloth)
 block(root, "Head", Vector3(0.36, 0.38, 0.37), Vector3(0, 2.26, 0), skin)
 block(root, "Hat", Vector3(0.44, 0.23, 0.44), Vector3(0, 2.54, 0), black)
 block(root, "Nose-facing", Vector3(0.12, 0.11, 0.15), Vector3(0.22 if face_right else -0.22, 2.27, 0.06), skin)
 return root

func _ready() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.57, 0.74, 0.87)
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.85, 0.88, 0.9)
 world.environment = env
 add_child(world)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55, -30, -20)
 light.light_energy = 1.6
 add_child(light)
 block(self, "Ground", Vector3(17, 0.12, 7), Vector3(0, -0.08, 0), Color(0.32, 0.51, 0.28))
 attacker = person("Attacker facing RIGHT", attack_x, true)
 defender = person("Defender facing LEFT", DEF_X, false)
 terkeh = rod(self, "Terkeh attached to raised hands", STICK_RADIUS, Color(0.93, 0.61, 0.20))
 darak = rod(self, "Darak held in defender hand", GUARD_RADIUS, Color(0.27, 0.14, 0.07))
 attack_hand_a = block(self, "Attacker left hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 attack_hand_b = block(self, "Attacker right hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 defend_hand = block(self, "Defender gripping darak", Vector3(0.22, 0.20, 0.22), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 attack_arm_a = rod(self, "Attacker arm left", 0.095, Color(0.66, 0.44, 0.30))
 attack_arm_b = rod(self, "Attacker arm right", 0.095, Color(0.66, 0.44, 0.30))
 defend_arm = rod(self, "Defender arm", 0.11, Color(0.66, 0.44, 0.30))
 var cam := Camera3D.new()
 add_child(cam)
 cam.position = Vector3(0, 2.45, 12.5)
 cam.look_at(Vector3(0, 1.45, 0), Vector3.UP)
 cam.fov = 53.0
 cam.current = true
 var layer := CanvasLayer.new()
 add_child(layer)
 var panel := PanelContainer.new()
 panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
 panel.offset_bottom = 112
 layer.add_child(panel)
 var column := VBoxContainer.new()
 panel.add_child(column)
 header = Label.new()
 header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 header.add_theme_font_size_override("font_size", 23)
 column.add_child(header)
 status = Label.new()
 status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 status.add_theme_font_size_override("font_size", 19)
 column.add_child(status)
 detail = Label.new()
 detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 column.add_child(detail)
 var footer := Label.new()
 footer.text = "A / D: move   |   J: behind-body feint   L: front-body feint   |   SPACE: swing   |   TAB: defend   |   W / S: move darak   |   R: reset"
 footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
 footer.offset_top = -43
 footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 footer.add_theme_font_size_override("font_size", 15)
 layer.add_child(footer)
 say("Approach with D. Terkeh stays in the hands; no invisible hit line.")
 update_visuals()

func say(s: String) -> void:
 if status != null:
  status.text = s

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_TAB:
    defending = not defending
    swing = -1.0
    opponent_delay = -1.0
    attack_x = -0.2 if defending else -2.7
    guard_shift = 0.0
    guard_target = 0.0
    say("DEFENSE: SPACE starts opponent; W/S move darak while it stays in hand." if defending else "ATTACK: approach with D, feint J/L, swing SPACE.")
   KEY_R:
    defending = false
    attack_x = -2.7
    swing = -1.0
    opponent_delay = -1.0
    guard_shift = 0.0
    guard_target = 0.0
    feint_target = 0.0
    score_hit = 0
    score_block = 0
    say("Reset. Move closer before striking.")
   KEY_J:
    if not defending and swing < 0.0:
     feint_target = -0.60
     say("Feint BEHIND the attacker (far side of body).")
   KEY_L:
    if not defending and swing < 0.0:
     feint_target = 0.65
     say("Feint IN FRONT of the attacker (near camera).")
   KEY_SPACE:
    if swing < 0.0 and opponent_delay < 0.0:
     if defending:
      opponent_delay = 0.55
      say("Watch the opponent. W/S shifts the held darak.")
     else:
      start_swing()

func start_swing() -> void:
 swing = 0.0
 swing_finished = false
 feint_target = 0.0
 say("Swing: physical terkeh sweeps toward the defender.")

func strike_ends(p: float) -> Array[Vector3]:
 # A long, visibly continuous wooden rod; the near grip stays in raised hands.
 var t := smoothstep(0.0, 1.0, clampf(p, 0.0, 1.0))
 var angle := lerpf(0.12, -1.20, t)
 var z := lerpf(feint_depth, 0.26, t)
 var grip := Vector3(attack_x + 0.36, 2.51 - 0.10 * t, z)
 var tip := grip + Vector3(cos(angle) * STICK_LENGTH, sin(angle) * STICK_LENGTH, 0)
 return [grip, tip]

func guard_ends() -> Array[Vector3]:
 # One grip always follows the defender's hand. The lower end pivots across the shins.
 var grip := Vector3(DEF_X - 0.36, 1.37, 0.28)
 var bottom := Vector3(DEF_X - 0.52 + guard_shift, 0.08, 0.28)
 var top := grip + (grip - bottom).normalized() * 0.55
 return [bottom, top]

func update_visuals() -> void:
 attacker.position.x = attack_x
 var ends := strike_ends(0.0 if swing < 0.0 else swing)
 var a := ends[0]
 var b := ends[1]
 if swing < 0.0:
  a.z = feint_depth
  b.z = feint_depth
 place_rod(terkeh, a, b)
 # Two visible hands remain around the wooden grip and move together with it.
 var direction := (b - a).normalized()
 attack_hand_a.position = a + direction * 0.10
 attack_hand_b.position = a + direction * 0.35
 place_rod(attack_arm_a, Vector3(attack_x + 0.20, 1.91, -0.13), attack_hand_a.position)
 place_rod(attack_arm_b, Vector3(attack_x + 0.24, 1.91, 0.16), attack_hand_b.position)
 var g := guard_ends()
 place_rod(darak, g[0], g[1])
 defend_hand.position = Vector3(DEF_X - 0.36, 1.37, 0.28)
 place_rod(defend_arm, Vector3(DEF_X - 0.20, 1.91, 0.10), defend_hand.position)

func segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
 var u := b - a
 var v := d - c
 var w := a - c
 var aa := u.dot(u)
 var bb := u.dot(v)
 var cc := v.dot(v)
 var dd := u.dot(w)
 var ee := v.dot(w)
 var denominator := aa * cc - bb * bb
 var s := 0.0
 var t := 0.0
 if denominator > 0.00001:
  s = clampf((bb * ee - cc * dd) / denominator, 0.0, 1.0)
 t = clampf((bb * s + ee) / maxf(cc, 0.00001), 0.0, 1.0)
 s = clampf((bb * t - dd) / maxf(aa, 0.00001), 0.0, 1.0)
 return (w + u * s - v * t).length()

func check_sweep(previous: float, current: float) -> String:
 var g := guard_ends()
 for i in range(1, 21):
  var p := lerpf(previous, current, float(i) / 20.0)
  var s := strike_ends(p)
  if segment_distance(s[0], s[1], g[0], g[1]) <= STICK_RADIUS + GUARD_RADIUS + 0.055:
   return "block"
  for foot_x in [DEF_X - 0.18, DEF_X + 0.18]:
   var leg_a := Vector3(foot_x, 0.12, 0.0)
   var leg_b := Vector3(foot_x, 0.77, 0.0)
   if segment_distance(s[0], s[1], leg_a, leg_b) <= 0.20:
    return "leg"
 return ""

func _process(delta: float) -> void:
 if swing < 0.0 and not defending:
  if Input.is_key_pressed(KEY_D):
   attack_x = minf(MAX_X, attack_x + 2.0 * delta)
  if Input.is_key_pressed(KEY_A):
   attack_x = maxf(MIN_X, attack_x - 2.0 * delta)
 if defending:
  if Input.is_key_pressed(KEY_W):
   guard_target = minf(0.53, guard_target + delta * 1.65)
  if Input.is_key_pressed(KEY_S):
   guard_target = maxf(-0.53, guard_target - delta * 1.65)
  guard_shift = move_toward(guard_shift, guard_target, delta * 2.8)
  if opponent_delay >= 0.0:
   opponent_delay -= delta
   if opponent_delay < 0.0:
    start_swing()
 feint_depth = move_toward(feint_depth, feint_target, delta * 1.7)
 if swing >= 0.0:
  var old := swing
  swing = minf(1.0, swing + delta / SWING_SECONDS)
  var result := check_sweep(old, swing)
  if result == "block":
   score_block += 100
   say("BLOCK: terkeh touched the held darak! Defender +100")
   swing = -1.0
  elif result == "leg":
   score_hit += 100
   say("LEGAL CONTACT: terkeh reached below-knee target. Attacker +100")
   swing = -1.0
  elif swing >= 1.0:
   say("MISS: terkeh did not reach the darak or leg. Check distance.")
   swing = -1.0
 update_visuals()
 header.text = ("DEFENSE TEST" if defending else "ATTACK TEST") + "   |   Hit: %d   Block: %d" % [score_hit, score_block]
 detail.text = "Distance: %.2f m   |   Darak offset: %.2f m   |   J=back / L=front" % [DEF_X - attack_x, guard_shift]
