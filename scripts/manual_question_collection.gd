extends RefCounted
## Manual stable-ID sets. Answer results never change membership.

static func ids(saved: Variant) -> Dictionary:
	var result: Dictionary = {}
	if saved is Array:
		for id in saved: result[str(id)] = true
	return result

static func serialized(values: Dictionary) -> Array[int]:
	var saved: Array[int] = []
	for id in values: saved.append(int(id))
	saved.sort()
	return saved

static func toggled(values: Dictionary, id: String) -> Dictionary:
	var next := values.duplicate(true)
	if next.has(id): next.erase(id)
	else: next[id] = true
	return next

static func questions(bank: Array, saved: Dictionary) -> Array:
	return bank.filter(func(question: Dictionary): return saved.has(str(question.id)))
