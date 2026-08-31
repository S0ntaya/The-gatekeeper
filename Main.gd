extends Control

# ============================================================
#  PAPERS PLEASE - CLONE (prototype)
#  Border inspection game: check documents against the day's
#  rules, approve or deny each applicant before time runs out.
#
#  All UI lives as real, named nodes in Main.tscn now (open it
#  in the Godot editor to see/rearrange/restyle everything).
#  This script only fills in the dynamic parts: applicant data,
#  loaded art, timers, and game state.
#
#  ART / ASSETS:
#  Drop your own PNGs into these folders and they'll be used
#  automatically (see README.md for exact filenames/sizes):
#    res://assets/portraits/   -> any number of face images
#    res://assets/stamps/      -> approve.png, deny.png
#    res://assets/ui/          -> background.png, passport_bg.png
#  If a folder is empty / a file is missing, a generated
#  placeholder is used instead so the game always runs.
# ============================================================

# ---------- CONFIG ----------
const APPLICANTS_PER_DAY := 5
const TIME_PER_APPLICANT := 25.0   # seconds
const MAX_MISTAKES := 5
const LAST_DAY := 6
const CORRECT_REWARD := 5
const MISTAKE_PENALTY := 5

const PORTRAIT_DIR := "res://assets/portraits/"
const STAMP_DIR := "res://assets/stamps/"
const UI_DIR := "res://assets/ui/"

# ---------- STATE ----------
var day := 1
var date_value := 24244            # day counter -> formats as 5/05/67 (see _format_date)
var applicant_index := 0
var mistakes := 0
var score := 0
var money := 0
var day_correct := 0
var day_wrong := 0
var day_earned := 0
var day_lost := 0
var current_applicant := {}
var rules := []
var time_left := 0.0
var timer_running := false

var portrait_textures: Array = []
var approve_stamp_tex: Texture2D
var deny_stamp_tex: Texture2D
var bg_tex: Texture2D
var passport_bg_tex: Texture2D

const NATIONALITIES := ["Arstotzka", "Kolechia", "Antegria", "Republia", "Obristan"]
const PURPOSES := ["Tourism", "Work", "Diplomatic Visit", "Family Visit"]
const GENDERS := ["M", "F"]
const FIRST_NAMES := ["Jorji", "Vess", "Kata", "Boris", "Yuri", "Nadia", "Dmitri", "Elena", "Anya", "Petr"]
const LAST_NAMES := ["Kostov", "Vashenko", "Rurikov", "Bratsk", "Molotov", "Dragomir", "Zhirova"]

# ---------- SCENE NODE REFERENCES (see Main.tscn) ----------
@onready var background_image: TextureRect = %BackgroundImage
@onready var hud_label: Label = %HUDLabel
@onready var document_background: TextureRect = %DocumentBackground
@onready var document_fallback_panel: PanelContainer = %DocumentFallbackPanel
@onready var document_title: Label = %DocumentTitle
@onready var photo_row: HBoxContainer = %PhotoRow
@onready var id_photo_rect: TextureRect = %IDPhotoRect
@onready var booth_photo_rect: TextureRect = %BoothPhotoRect
@onready var info_label: Label = %InfoLabel
@onready var end_label: Label = %EndLabel
@onready var restart_button: Button = %RestartButton
@onready var continue_button: Button = %ContinueButton
@onready var rulebook_label: RichTextLabel = %RulebookLabel
@onready var stamp_rect: TextureRect = %StampRect
@onready var feedback_label: Label = %FeedbackLabel
@onready var timer_bar: ProgressBar = %TimerBar
@onready var approve_btn: Button = %ApproveButton
@onready var deny_btn: Button = %DenyButton

func _ready() -> void:
	randomize()
	_load_assets()
	_apply_assets()
	approve_btn.pressed.connect(func(): _on_decision(true, false))
	deny_btn.pressed.connect(func(): _on_decision(false, false))
	restart_button.pressed.connect(_on_restart_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	_start_day()

func _process(delta: float) -> void:
	if timer_running:
		time_left -= delta
		timer_bar.value = time_left
		if time_left <= 0.0:
			timer_running = false
			_on_decision(false, true)  # ran out of time -> auto-fail this one

# ================= ASSET LOADING (with fallbacks) =================
func _load_assets() -> void:
	portrait_textures = _load_images_from_dir(PORTRAIT_DIR)
	if portrait_textures.is_empty():
		for i in range(6):
			portrait_textures.append(_make_placeholder_square(128, Color.from_hsv(float(i) / 6.0, 0.5, 0.7)))

	approve_stamp_tex = _load_single_image(STAMP_DIR + "approve.png")
	deny_stamp_tex = _load_single_image(STAMP_DIR + "deny.png")
	bg_tex = _load_single_image(UI_DIR + "background.png")
	passport_bg_tex = _load_single_image(UI_DIR + "passport_bg.png")

func _load_images_from_dir(path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower := fname.to_lower()
			if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
				var tex = load(path + fname)
				if tex is Texture2D:
					result.append(tex)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return a.resource_path < b.resource_path)
	return result

func _load_single_image(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			return tex
	return null

func _make_placeholder_square(size: int, color: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	for x in range(size):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, size - 1, Color.BLACK)
	for y in range(size):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(size - 1, y, Color.BLACK)
	return ImageTexture.create_from_image(img)

func _apply_assets() -> void:
	if bg_tex != null:
		background_image.texture = bg_tex
		background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background_image.stretch_mode = TextureRect.STRETCH_SCALE
		background_image.visible = true

	if passport_bg_tex != null:
		document_background.texture = passport_bg_tex
		document_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		document_background.stretch_mode = TextureRect.STRETCH_SCALE
		document_background.visible = true
		document_fallback_panel.visible = false
	else:
		document_fallback_panel.visible = true

	id_photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	id_photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	booth_photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	booth_photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.autowrap_mode = TextServer.AUTOWRAP_WORD

# ================= DAY / RULES =================
func _start_day() -> void:
	applicant_index = 0
	day_correct = 0
	day_wrong = 0
	day_earned = 0
	day_lost = 0
	_set_rules_for_day(day)
	_update_rulebook()
	approve_btn.disabled = false
	deny_btn.disabled = false
	timer_bar.visible = true
	_next_applicant()

func _set_rules_for_day(d: int) -> void:
	rules.clear()
	rules.append({"desc": "Document must not be expired.", "check": Callable(self, "_rule_expiry")})
	if d >= 2:
		var banned = NATIONALITIES[randi() % NATIONALITIES.size()]
		rules.append({
			"desc": "Entrants from %s are banned. Deny them." % banned,
			"check": Callable(self, "_rule_nationality"),
			"banned": banned
		})
	if d >= 3:
		rules.append({"desc": "The photo must match the person at the window.", "check": Callable(self, "_rule_photo")})
	if d >= 4:
		rules.append({"desc": "'Work' purpose requires a valid, unexpired work visa.", "check": Callable(self, "_rule_visa")})
	if d >= 5:
		rules.append({"desc": "If a visa is present, its name and gender must match the passport.", "check": Callable(self, "_rule_visa_match")})

func _update_rulebook() -> void:
	var text := "[b]RULEBOOK - Day %d[/b]\n\n" % day
	for r in rules:
		text += "• %s\n" % r["desc"]
	rulebook_label.text = text

func _get_rule(key: String) -> Dictionary:
	for r in rules:
		if r.has(key):
			return r
	return {}

# ================= APPLICANT GENERATION =================
func _random_applicant() -> Dictionary:
	var expired := randf() < 0.3
	var expiry := date_value + (-randi_range(1, 200) if expired else randi_range(1, 400))

	var nationality = NATIONALITIES[randi() % NATIONALITIES.size()]
	var banned_rule := _get_rule("banned")
	if not banned_rule.is_empty() and randf() < 0.35:
		nationality = banned_rule["banned"]

	var purpose = PURPOSES[randi() % PURPOSES.size()]
	var name := _random_name()
	var gender: String = GENDERS[randi() % GENDERS.size()]

	var has_visa := randf() < 0.6
	var visa_expired := randf() < 0.3
	var visa_expiry := 0
	var visa_name := ""
	var visa_gender := ""
	if has_visa:
		visa_expiry = date_value + (-randi_range(1, 200) if visa_expired else randi_range(1, 400))

		var name_mismatch := randf() < 0.25
		if name_mismatch:
			var alt_name := _random_name()
			while alt_name == name:
				alt_name = _random_name()
			visa_name = alt_name
		else:
			visa_name = name

		var gender_mismatch := randf() < 0.25
		visa_gender = _other_gender(gender) if gender_mismatch else gender

	var photo_match := randf() > 0.25

	var id_idx := randi() % portrait_textures.size()
	var booth_idx := id_idx
	if not photo_match and portrait_textures.size() > 1:
		booth_idx = (id_idx + 1 + (randi() % (portrait_textures.size() - 1))) % portrait_textures.size()

	return {
		"name": name,
		"gender": gender,
		"nationality": nationality,
		"passport_no": str(randi_range(100000, 999999)),
		"expiry": expiry,
		"purpose": purpose,
		"has_visa": has_visa,
		"visa_expiry": visa_expiry,
		"visa_name": visa_name,
		"visa_gender": visa_gender,
		"photo_match": photo_match,
		"id_photo_idx": id_idx,
		"booth_photo_idx": booth_idx,
	}

func _other_gender(g: String) -> String:
	return GENDERS[1] if g == GENDERS[0] else GENDERS[0]

func _random_name() -> String:
	return FIRST_NAMES[randi() % FIRST_NAMES.size()] + " " + LAST_NAMES[randi() % LAST_NAMES.size()]

func _next_applicant() -> void:
	stamp_rect.visible = false
	if applicant_index >= APPLICANTS_PER_DAY:
		_end_day()
		return
	applicant_index += 1
	current_applicant = _random_applicant()
	_render_applicant()
	feedback_label.text = ""
	time_left = TIME_PER_APPLICANT
	timer_running = true
	_update_hud()

func _render_applicant() -> void:
	document_title.visible = true
	photo_row.visible = true
	info_label.visible = true
	end_label.visible = false
	restart_button.visible = false
	continue_button.visible = false

	id_photo_rect.texture = portrait_textures[current_applicant["id_photo_idx"]]
	booth_photo_rect.texture = portrait_textures[current_applicant["booth_photo_idx"]]

	var fields := [
		["Name", current_applicant["name"]],
		["Gender", current_applicant["gender"]],
		["Nationality", current_applicant["nationality"]],
		["Passport No.", current_applicant["passport_no"]],
		["Passport Expiry", _format_date(current_applicant["expiry"])],
		["Purpose", current_applicant["purpose"]],
	]
	var info_lines := []
	for f in fields:
		info_lines.append("%s: %s" % [f[0], f[1]])
	if current_applicant["has_visa"]:
		info_lines.append("Visa Expiry: %s" % _format_date(current_applicant["visa_expiry"]))
		info_lines.append("Visa Name: %s" % current_applicant["visa_name"])
		info_lines.append("Visa Gender: %s" % current_applicant["visa_gender"])
	info_label.text = "\n".join(info_lines)

func _format_date(v: int) -> String:
	var y := v / 360
	var rem := v % 360
	var m := (rem / 30) + 1
	var d := (rem % 30) + 1
	return "%d/%02d/%02d" % [d, m, y % 100]

# ================= DECISION =================
func _on_decision(approved: bool, timeout: bool) -> void:
	timer_running = false
	var should_approve := _evaluate_applicant()
	var correct := (approved == should_approve)

	stamp_rect.texture = approve_stamp_tex if approved else deny_stamp_tex
	stamp_rect.visible = (stamp_rect.texture != null) and not timeout

	if timeout:
		correct = false
		feedback_label.text = "Too slow! The queue grows restless."
	elif correct:
		score += 1
		feedback_label.text = "Correct decision."
	else:
		mistakes += 1
		feedback_label.text = "Mistake! Should have %s." % ("APPROVED" if should_approve else "DENIED")

	if correct:
		money += CORRECT_REWARD
		day_earned += CORRECT_REWARD
		day_correct += 1
	else:
		money -= MISTAKE_PENALTY
		day_lost += MISTAKE_PENALTY
		day_wrong += 1

	_update_hud()

	if mistakes >= MAX_MISTAKES:
		await get_tree().create_timer(0.8).timeout
		_game_over("Too many mistakes. Your inspector license has been revoked.")
		return

	if money < 0:
		await get_tree().create_timer(0.8).timeout
		_game_over("You went bankrupt. You can no longer support your family.")
		return

	await get_tree().create_timer(0.8).timeout
	_next_applicant()

func _evaluate_applicant() -> bool:
	for r in rules:
		var check: Callable = r["check"]
		if not check.call(current_applicant, r):
			return false
	return true

func _rule_expiry(a: Dictionary, _r: Dictionary) -> bool:
	return a["expiry"] >= date_value

func _rule_nationality(a: Dictionary, r: Dictionary) -> bool:
	return a["nationality"] != r["banned"]

func _rule_photo(a: Dictionary, _r: Dictionary) -> bool:
	return a["photo_match"]

func _rule_visa(a: Dictionary, _r: Dictionary) -> bool:
	if a["purpose"] == "Work":
		if not a["has_visa"]:
			return false
		return a["visa_expiry"] >= date_value
	return true

func _rule_visa_match(a: Dictionary, _r: Dictionary) -> bool:
	if not a["has_visa"]:
		return true
	return a["visa_name"] == a["name"] and a["visa_gender"] == a["gender"]

# ================= DAY END / GAME OVER =================
func _end_day() -> void:
	date_value += randi_range(1, 3)
	day += 1
	if day > LAST_DAY:
		_victory()
		return
	_show_day_summary()

func _show_day_summary() -> void:
	var msg := "END OF DAY %d\n\nCorrect: %d\nMistakes: %d\n\nEarned: +$%d\nLost: -$%d\n\nTotal Money: $%d" % [
		day - 1, day_correct, day_wrong, day_earned, day_lost, money
	]
	document_title.visible = false
	photo_row.visible = false
	info_label.visible = false
	end_label.visible = true
	end_label.text = msg
	end_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	timer_bar.visible = false
	stamp_rect.visible = false
	approve_btn.disabled = true
	deny_btn.disabled = true
	continue_button.visible = true

func _on_continue_pressed() -> void:
	continue_button.visible = false
	approve_btn.disabled = false
	deny_btn.disabled = false
	_start_day()

func _game_over(reason: String) -> void:
	_show_end_screen(
		"GAME OVER\n\n%s\n\nFinal Score: %d\nTotal Money: $%d" % [reason, score, money],
		Color(0.85, 0.25, 0.25)
	)

func _victory() -> void:
	_show_end_screen(
		"CONGRATULATIONS\n\nYou survived Day 1 through %d as border inspector.\n\nFinal Score: %d   |   Mistakes: %d\nTotal Money: $%d" % [LAST_DAY, score, mistakes, money],
		Color(0.25, 0.65, 0.3)
	)

func _show_end_screen(msg: String, color: Color) -> void:
	document_title.visible = false
	photo_row.visible = false
	info_label.visible = false
	end_label.visible = true
	end_label.text = msg
	end_label.add_theme_color_override("font_color", color)
	restart_button.visible = true
	approve_btn.disabled = true
	deny_btn.disabled = true
	timer_bar.visible = false
	stamp_rect.visible = false

func _on_restart_pressed() -> void:
	day = 1
	date_value = 24244
	score = 0
	mistakes = 0
	money = 0
	restart_button.visible = false
	approve_btn.disabled = false
	deny_btn.disabled = false
	_start_day()

# ================= HUD =================
func _update_hud() -> void:
	hud_label.text = _format_date(date_value)
