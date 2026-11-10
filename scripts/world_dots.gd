extends RefCounted
## The fixed dots of the house: every static surface carries its own dots, always in the
## same place, and the echo only decides which of them light up (and how brightly).
##
##  - Sharp edges and corners (wall corners, door frames, table edges, shelf rims): a close
##    line of dots, the brightest in a scan. This is what shows the house's structure.
##  - Surfaces: dots scattered at random but evenly (one per cell of a world-anchored grid,
##    anywhere in the cell), so a surface never reads as rows and columns.
##
## Not included: anything interactive (doors, the TV, things you can pick up: the scanner's
## detail pass draws them, they move), people, and bodies without collision (lamps).
##
## Each dot: position, outward normal, echo material, edge flag. Packed for a MultiMesh:
## transform (identity basis + position) and custom data (normal xyz, material + 0.5 if edge).

const EDGE_SPACING := 0.045
const FILL_SPACING := 0.11
const SHARP_DOT := 0.8      # faces meeting at more than ~37 degrees make a sharp edge


## Returns {"buffer": PackedFloat32Array (16 floats per dot), "count": int}.
static func build(root: Node, skip: Callable) -> Dictionary:
	var buf := PackedFloat32Array()
	var seen := {}
	var count := 0
	for c in root.find_children("*", "StaticBody3D", true, false):
		var body := c as StaticBody3D
		if body.collision_layer & 1 == 0 or skip.call(body):
			continue
		var mat := float(body.get_meta("echo_material", 1))
		for m in body.get_children():
			var mi := m as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var xf := mi.global_transform
			var faces := mi.mesh.get_faces()
			var tris := PackedVector3Array()
			tris.resize(faces.size())
			for i in faces.size():
				tris[i] = xf * faces[i]
			count = _edges(tris, mat, buf, seen, count)
			count = _fill(tris, mat, buf, seen, count)
	return {"buffer": buf, "count": count}


static func _key(p: Vector3) -> int:
	return (roundi(p.x * 60.0) * 73856093) ^ (roundi(p.y * 60.0) * 19349663) ^ (roundi(p.z * 60.0) * 83492791)


static func _add(buf: PackedFloat32Array, p: Vector3, n: Vector3, mat: float, edge: bool) -> void:
	buf.append_array([1.0, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 0.0, 0.0, 1.0, p.z,
		n.x, n.y, n.z, mat + (0.5 if edge else 0.0)])


## Dots along the sharp edges of a mesh (and its open borders).
static func _edges(tris: PackedVector3Array, mat: float, buf: PackedFloat32Array, seen: Dictionary, count: int) -> int:
	var found := {}
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var n := (c - a).cross(b - a) # outward (Godot front faces wind clockwise)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var tri := [a, b, c]
		for k in 3:
			var p: Vector3 = tri[k]
			var q: Vector3 = tri[(k + 1) % 3]
			var kp := _key(p)
			var kq := _key(q)
			var key := Vector2i(mini(kp, kq), maxi(kp, kq))
			if found.has(key):
				found[key][3] = n
			else:
				found[key] = [p, q, n, null]
	for e in found.values():
		var n1: Vector3 = e[2]
		var sharp: bool = e[3] == null or n1.dot(e[3]) < SHARP_DOT
		if not sharp:
			continue
		var nn: Vector3 = n1 if e[3] == null else (n1 + (e[3] as Vector3)).normalized()
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var steps := maxi(1, roundi(a.distance_to(b) / EDGE_SPACING))
		for k in steps + 1:
			# uneven spacing along the edge (a hand-drawn line of dots, not a ruler)
			var p := a.lerp(b, clampf((float(k) + randf_range(-0.35, 0.35)) / steps, 0.0, 1.0))
			var key := _key(p)
			if seen.has(key):
				continue
			seen[key] = true
			_add(buf, p, nn, mat, true)
			count += 1
	return count


## Scattered dots over each triangle (in the triangle's plane).
static func _fill(tris: PackedVector3Array, mat: float, buf: PackedFloat32Array, seen: Dictionary, count: int) -> int:
	var s := FILL_SPACING
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var n := (c - a).cross(b - a) # outward (Godot front faces wind clockwise)
		var area := n.length() * 0.5
		if area < 1e-8:
			continue
		n = n.normalized()
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		var a2 := Vector2(a.dot(u), a.dot(v))
		var b2 := Vector2(b.dot(u), b.dot(v))
		var c2 := Vector2(c.dot(u), c.dot(v))
		var lo := Vector2(minf(a2.x, minf(b2.x, c2.x)), minf(a2.y, minf(b2.y, c2.y)))
		var hi := Vector2(maxf(a2.x, maxf(b2.x, c2.x)), maxf(a2.y, maxf(b2.y, c2.y)))
		var d := a.dot(n)
		var placed := false
		# One dot somewhere in each cell of a world-anchored grid: scattered, never in rows,
		# but evenly spread. The place in the cell depends only on the cell, so coplanar
		# surfaces agree and nothing is doubled.
		var plane_k := roundi(d * 50.0) * 83492791 ^ roundi(n.x * 7.0 + n.y * 13.0 + n.z * 29.0) * 2654435
		for gx in range(floori(lo.x / s) - 1, ceili(hi.x / s) + 1):
			for gy in range(floori(lo.y / s) - 1, ceili(hi.y / s) + 1):
				var h := ((gx * 73856093) ^ (gy * 19349663) ^ plane_k) & 0x7fffffff
				h = (h * 1103515245 + 12345) & 0x7fffffff
				var q := Vector2(gx + float(h % 1009) / 1009.0, gy + float((h / 1009) % 1013) / 1013.0) * s
				if not _inside_strict(q, a2, b2, c2):
					continue
				var p := u * q.x + v * q.y + n * d
				var key := _key(p)
				placed = true
				if seen.has(key):
					continue
				seen[key] = true
				_add(buf, p, n, mat, false)
				count += 1
		# small triangles (curved things) that the grid misses: a dot now and then
		if not placed and randf() < area / (s * s):
			var p := (a + b + c) / 3.0
			_add(buf, p, n, mat, false)
			count += 1
	return count


static func _inside_strict(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	return (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0)
