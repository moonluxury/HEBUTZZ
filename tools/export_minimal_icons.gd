extends SceneTree

func _init() -> void:
	var source := "res://assets/minimal/source"
	for file in DirAccess.get_files_at(source):
		if not file.ends_with(".svg"):
			continue
		var svg := FileAccess.get_file_as_string(source + "/" + file).replace("currentColor", "#ffffff")
		var picture := Image.new()
		if picture.load_svg_from_string(svg, 16.0) != OK:
			quit(1)
			return
		picture.save_png("res://assets/minimal/icons/" + file.get_basename() + ".png")
	print("Exported individual 384px icons from original library paths.")
	quit()
