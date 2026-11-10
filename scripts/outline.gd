extends RefCounted
## The edges of an object: what its outline and its structure are made of.
## Used by the live layer (the white outline of what you touch) and by the scanner (the
## structured dots of everything you can interact with).
##
## Each edge is [a, b, n1, n2]: its two ends and the normals of the (up to two) faces that
## share it, all in the object's own space. n2 is null for a boundary edge.

static var _cache := {}


## Every mesh edge of `obj` (all child meshes), cached per object.
static func edges(obj: Node3D) -> Array:
	var key := obj.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var inv := obj.global_transform.affine_inverse()
	for c in obj.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		_collect(mi.mesh, inv * mi.global_transform, out)
	_cache[key] = out
	return out


static func _collect(mesh: Mesh, to_obj: Transform3D, out: Array) -> void:
	var faces := mesh.get_faces()
	var found := {}
	for t in range(0, faces.size(), 3):
		var a: Vector3 = to_obj * faces[t]
		var b: Vector3 = to_obj * faces[t + 1]
		var c: Vector3 = to_obj * faces[t + 2]
		var n := (b - a).cross(c - a).normalized()
		var tri := [a, b, c]
		for k in 3:
			var p: Vector3 = tri[k]
			var q: Vector3 = tri[(k + 1) % 3]
			var kp := "%d,%d,%d" % [roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0)]
			var kq := "%d,%d,%d" % [roundi(q.x * 2000.0), roundi(q.y * 2000.0), roundi(q.z * 2000.0)]
			var key := kp + "|" + kq if kp < kq else kq + "|" + kp
			if found.has(key):
				found[key][3] = n
			else:
				found[key] = [p, q, n, null]
	out.append_array(found.values())


## Dots that show the structure of an object: close dots along its sharp edges (corners,
## rims, frames), sparser dots along its curved edges, and a thin fill of its surface.
## Returns points in the object's own space, about `budget` of them.
static func structure_points(obj: Node3D, budget := 540) -> PackedVector3Array:
	var sharp: Array = []
	var soft: Array = []
	var sharp_len := 0.0
	var soft_len := 0.0
	for e in edges(obj):
		var len := ((e[1] as Vector3) - (e[0] as Vector3)).length()
		if len < 0.002:
			continue
		if e[3] == null or (e[2] as Vector3).dot(e[3]) < 0.8:
			sharp.append(e)
			sharp_len += len
		elif (e[2] as Vector3).dot(e[3]) < 0.985:
			soft.append(e)
			soft_len += len
	var out := PackedVector3Array()
	var groups := [[sharp, maxf(0.008, sharp_len / (budget * 0.66))], [soft, maxf(0.018, soft_len / (budget * 0.17))]]
	for g in groups:
		var spacing: float = g[1]
		for e in g[0]:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var n := maxi(1, roundi(a.distance_to(b) / spacing))
			for k in n:
				out.append(a.lerp(b, float(k) / n))
	# a thin fill of the surface, so something solid still reads as solid
	var meshes := obj.find_children("*", "MeshInstance3D", true, false)
	var inv := obj.global_transform.affine_inverse()
	var fill := int(budget * 0.17)
	var total := 0.0
	var areas := []
	for c in meshes:
		var area := _area((c as MeshInstance3D).mesh)
		areas.append(area)
		total += area
	for k in meshes.size():
		var mi := meshes[k] as MeshInstance3D
		var share := maxi(int(fill * areas[k] / maxf(total, 0.0001)), 2)
		for pt in _surface(mi.mesh, share):
			out.append(inv * mi.global_transform * pt)
	return out


static func _area(mesh: Mesh) -> float:
	var f := mesh.get_faces()
	var a := 0.0
	for i in range(0, f.size(), 3):
		a += (f[i + 1] - f[i]).cross(f[i + 2] - f[i]).length() * 0.5
	return a


static func _surface(mesh: Mesh, count: int) -> PackedVector3Array:
	var faces := mesh.get_faces()
	var out := PackedVector3Array()
	if faces.size() < 3:
		return out
	var cum := PackedFloat32Array()
	var total := 0.0
	for i in range(0, faces.size(), 3):
		total += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() * 0.5
		cum.append(total)
	for n in count:
		var tri := mini(cum.bsearch(randf() * total), cum.size() - 1)
		var a := faces[tri * 3]
		var b := faces[tri * 3 + 1]
		var c := faces[tri * 3 + 2]
		var u := randf()
		var v := randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		out.append(a + (b - a) * u + (c - a) * v)
	return out
