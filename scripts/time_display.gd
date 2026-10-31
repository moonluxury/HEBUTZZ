extends RefCounted
## Display only: keep API timestamps, sort keys, cursors and expiry checks unchanged.
## All dated UI uses Beijing time. Legacy unzoned labels already denote local time.
const BEIJING_OFFSET := 8 * 3600
static var _datetime: RegEx
static var _date: RegEx
static var _clock: RegEx

static func _patterns() -> void:
	if _datetime != null: return
	_datetime = RegEx.new()
	_datetime.compile("^(\\d{4})-(\\d{2})-(\\d{2})[Tt ](\\d{2}):(\\d{2})(?::(\\d{2})(?:[.,]\\d+)?)?([Zz]|[+-]\\d{2}:?\\d{2})?$")
	_date = RegEx.new()
	_date.compile("^(\\d{4})-(\\d{2})-(\\d{2})$")
	_clock = RegEx.new()
	_clock.compile("^(\\d{2}):(\\d{2})(?::(\\d{2}))?$")

static func _valid_date(year: int, month: int, day: int) -> bool:
	if year < 1 or month < 1 or month > 12 or day < 1: return false
	var days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day <= days[month - 1]

static func _parse(value: String) -> Dictionary:
	_patterns()
	var source := value.strip_edges()
	var matched := _datetime.search(source)
	if matched != null:
		var year := int(matched.get_string(1))
		var month := int(matched.get_string(2))
		var day := int(matched.get_string(3))
		var hour := int(matched.get_string(4))
		var minute := int(matched.get_string(5))
		var second := int(matched.get_string(6))
		if not _valid_date(year, month, day) or hour > 23 or minute > 59 or second > 59: return {}
		var zone := matched.get_string(7)
		var offset := BEIJING_OFFSET
		if zone.to_upper() == "Z": offset = 0
		elif not zone.is_empty():
			var compact := zone.replace(":", "")
			var zone_hour := int(compact.substr(1, 2))
			var zone_minute := int(compact.substr(3, 2))
			if zone_hour > 23 or zone_minute > 59: return {}
			offset = (zone_hour * 3600 + zone_minute * 60) * (-1 if zone.begins_with("-") else 1)
		var unix := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second}) - offset
		var local := Time.get_datetime_dict_from_unix_time(unix + BEIJING_OFFSET)
		local.kind = "datetime"
		local.unix = unix
		return local
	matched = _date.search(source)
	if matched != null:
		var year := int(matched.get_string(1))
		var month := int(matched.get_string(2))
		var day := int(matched.get_string(3))
		return {"kind": "date", "year": year, "month": month, "day": day} if _valid_date(year, month, day) else {}
	matched = _clock.search(source)
	if matched != null:
		var hour := int(matched.get_string(1))
		var minute := int(matched.get_string(2))
		var second := int(matched.get_string(3))
		return {"kind": "clock", "hour": hour, "minute": minute} if hour < 24 and minute < 60 and second < 60 else {}
	return {}

static func _day(parts: Dictionary) -> String:
	return "%04d-%02d-%02d" % [parts.year, parts.month, parts.day]

static func _hour(parts: Dictionary) -> String:
	return "%02d:%02d" % [parts.hour, parts.minute]

static func datetime(value: String) -> String:
	var parts := _parse(value)
	if parts.is_empty(): return ""
	if parts.kind == "date": return _day(parts)
	if parts.kind == "clock": return _hour(parts)
	return _day(parts) + " " + _hour(parts)

static func date(value: String, fallback := "") -> String:
	var parts := _parse(value)
	if parts.is_empty() or parts.kind == "clock":
		parts = _parse(fallback)
	return _day(parts) if not parts.is_empty() and parts.kind != "clock" else ""

static func clock(value: String) -> String:
	var parts := _parse(value)
	return _hour(parts) if not parts.is_empty() and parts.kind != "date" else ""

static func recent(value: String, now := -1) -> String:
	var parts := _parse(value)
	if parts.is_empty(): return ""
	if parts.kind == "clock": return _hour(parts)
	var today := Time.get_datetime_dict_from_unix_time((int(Time.get_unix_time_from_system()) if now < 0 else now) + BEIJING_OFFSET)
	if parts.kind == "datetime" and _day(parts) == _day(today): return _hour(parts)
	if parts.year != today.year: return "%02d/%02d/%02d" % [int(parts.year) % 100, parts.month, parts.day]
	return "%02d-%02d" % [parts.month, parts.day]

static func relative(value: String, now := -1) -> String:
	var parts := _parse(value)
	if parts.is_empty(): return ""
	if parts.kind != "datetime": return datetime(value)
	var elapsed: int = (int(Time.get_unix_time_from_system()) if now < 0 else now) - int(parts.unix)
	# Future records must not be mistaken for "just now".
	if elapsed < 0: return datetime(value)
	if elapsed < 60: return "刚刚"
	if elapsed < 3600: return "%d分钟前" % (elapsed / 60)
	if elapsed < 86400: return "%d小时前" % (elapsed / 3600)
	return datetime(value)
