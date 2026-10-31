class_name HUD
extends CanvasLayer
## Trailer-style HUD: rank, km to sea, litres (top right), name + rivers left
## (top left), event feed (bottom right), end screen.

var rank_label: Label
var dist_label: Label
var vol_label: Label
var name_label: Label
var left_label: Label
var surge_label: Label
var feed: VBoxContainer
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var again_button: Button

const RANK_COLOR := Color(1.0, 0.35, 0.3)
const WATER := Color(0.22, 0.84, 0.82)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# top right stats
	var stats := VBoxContainer.new()
	stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats.anchor_left = 1.0
	stats.anchor_right = 1.0
	stats.offset_left = -420
	stats.offset_right = -24
	stats.offset_top = 16
	stats.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(stats)
	rank_label = _label(72, RANK_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	dist_label = _label(30, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	vol_label = _label(30, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	stats.add_child(rank_label)
	stats.add_child(dist_label)
	stats.add_child(vol_label)

	# top left name
	var ident := VBoxContainer.new()
	ident.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ident.offset_left = 24
	ident.offset_top = 16
	root.add_child(ident)
	name_label = _label(26, WATER, HORIZONTAL_ALIGNMENT_LEFT)
	left_label = _label(14, Color(0.7, 0.78, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	surge_label = _label(14, Color(0.7, 0.78, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	ident.add_child(name_label)
	ident.add_child(left_label)
	ident.add_child(surge_label)

	var hint := _label(13, Color(0.7, 0.78, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "A / D  or  ←  →  steer      SPACE  surge      TAB  map view      ▽ smaller: absorb it     ▲ bigger: run"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.offset_top = -40
	hint.offset_bottom = -16
	root.add_child(hint)

	# feed
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.anchor_top = 1.0
	feed.anchor_bottom = 1.0
	feed.offset_left = -460
	feed.offset_right = -24
	feed.offset_top = -220
	feed.offset_bottom = -56
	feed.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(feed)

	# end screen
	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.13, 0.92)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	end_panel.add_theme_stylebox_override("panel", style)
	root.add_child(end_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	end_panel.add_child(box)
	end_title = _label(44, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	end_body = _label(18, Color(0.85, 0.9, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	again_button = Button.new()
	again_button.text = "Rain again"
	again_button.custom_minimum_size = Vector2(0, 48)
	box.add_child(end_title)
	box.add_child(end_body)
	box.add_child(again_button)
	end_panel.reset_size()


func _label(size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func update(sim: RiverSim, player: RiverSim.River) -> void:
	rank_label.text = "#%d / %d" % [sim.rank_of(player), RiverSim.RIVER_COUNT]
	dist_label.text = "%.2f KM TO SEA" % sim.terrain.km_to_sea(player.x, player.y)
	vol_label.text = "● %s L" % _fmt(player.vol)
	name_label.text = player.display_name
	var chevrons := "▲".repeat(clampi(int(player.slope * 3.0) + 1, 1, 5))
	var grade := "FLAT" if player.slope < 0.08 else ("GENTLE" if player.slope < 0.3 else ("STEEP" if player.slope < 0.8 else "FALLS"))
	left_label.text = "RIVERS LEFT: %d      GRADE %s %s" % [sim.remaining(), chevrons, grade]
	if sim.elapsed < RiverSim.GRACE_SECONDS:
		surge_label.text = "SAFE FOR %d s" % int(RiverSim.GRACE_SECONDS - sim.elapsed)
		surge_label.add_theme_color_override("font_color", WATER)
	elif player.surging():
		surge_label.text = "SURGE!"
		surge_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	elif player.can_surge():
		surge_label.text = "SURGE READY  [space]"
		surge_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	else:
		surge_label.text = "surge in %.1f s" % player.surge_cd
		surge_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))


func post(text: String, color: Color = Color.WHITE) -> void:
	var l := _label(15, color, HORIZONTAL_ALIGNMENT_RIGHT)
	l.text = text
	feed.add_child(l)
	while feed.get_child_count() > 5:
		feed.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func show_end(sim: RiverSim, player: RiverSim.River, reached_sea: bool) -> void:
	var rank := sim.rank_of(player) if reached_sea else sim.remaining() + sim.finished_count + 1
	if reached_sea:
		end_title.text = "Mighty river." if rank == 1 else ("Big water." if rank <= 5 else ("Respectable flow." if rank <= 20 else "Still a river."))
	else:
		end_title.text = "Tributary."
	var lines := PackedStringArray()
	lines.append("You reached the sea" if reached_sea else "Swallowed by %s" % player.killer)
	lines.append("")
	lines.append("FINAL RANK     #%d / %d" % [rank, RiverSim.RIVER_COUNT])
	lines.append("FINAL VOLUME   %s L" % _fmt(player.vol))
	lines.append("ABSORBED       %d rivers" % player.eaten)
	lines.append("CARVED         %.2f km" % (player.length * TerrainData.CELL_KM))
	lines.append("TIME           %d:%02d" % [int(sim.elapsed) / 60, int(sim.elapsed) % 60])
	lines.append("")
	var board: Array[RiverSim.River] = []
	for r in sim.rivers:
		if r.alive:
			board.append(r)
	board.sort_custom(func(a, b): return a.vol > b.vol)
	for i in mini(6, board.size()):
		var r := board[i]
		var me := "  ◀" if r == player else ""
		lines.append("#%d  %-14s %s L%s" % [i + 1, r.display_name, _fmt(r.vol), me])
	end_body.text = "\n".join(lines)
	end_panel.visible = true
	end_panel.reset_size()
	end_panel.position = (get_viewport().get_visible_rect().size - end_panel.size) * 0.5


static func _fmt(v: float) -> String:
	var s := str(int(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
