extends SceneTree
## Export the original library paths unchanged. No image generation/redesign.

const ICONS := {
	"nav_home": "house-door-fill",
	"nav_bank": "journal-text",
	"nav_wrong": "clipboard-x-fill",
	"nav_kaiwu": "collection-fill",
	"nav_spirit": "person-fill",
	"nav_legacy": "grid-1x2-fill",
	"stat_today": "clipboard-data-fill",
	"stat_progress": "bar-chart-fill",
	"stat_days": "calendar-check-fill",
	"stat_total": "plus-circle-fill",
	"action_arrow": "arrow-right",
}


func _init() -> void:
	var destination := "res://assets/workbench/art/original"
	DirAccess.make_dir_recursive_absolute(destination)
	var manifest: Array = []
	for name in ICONS:
		var source := "res://assets/workbench/icons/%s.svg" % ICONS[name]
		var image := Image.new()
		var result := image.load_svg_from_string(FileAccess.get_file_as_string(source), 32.0)
		if result != OK or image.save_png(destination + "/" + name + ".png") != OK:
			push_error("Cannot export original icon: " + source)
			quit(1)
			return
		manifest.append({"file": name + ".png", "source": source, "size": [image.get_width(), image.get_height()], "tint": "Original UI color applied at runtime", "method": "Godot SVG rasterizer; original paths unchanged"})
	var file := FileAccess.open(destination + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("Exported %d original icons without shape changes." % ICONS.size())
	quit()
