class_name BoardConverter

#BoardConverter Class made by Pablo Ibarz
#created in December 2021

#BoardConverter started as a converter for things related to well, the board
#but now its a more general use collection of static functions because I'm too lazy to learn how to use a singleton

#return the face index, position in space and normal of mesh from a uv coordinate pos
static func uv_to_mdata(var mdt:MeshDataTool, var pos:Vector2 = Vector2.ZERO, 
	var mask:Array = []):
	
	#convert pos into Vector3 with y=0 to be compatible with Triangle's Vector3 components
	var p:Vector3 = Vector3(pos.x, 0, pos.y)
	
	#closest distance between p and a triangle
	var distance:Array = [INF]
	#closest triangle
	var closest = null
	
	#loop through each face, looking for a triangle closer than distance to p
	for i in mdt.get_face_count():
		var found = uv_to_mdata_step(mdt, i, [p], distance)
		#if one is found, assign it to closest
		if found != null:
			closest = found
			#check if a surrounding triangle was found, and return early if so
			if closest[4]: return closest
	
	return closest

#check a face to see if it surrounds uv
#WIP if not, move onto another face
static func uv_to_mdata_step(var mdt:MeshDataTool, var i:int, var uv:PoolVector3Array,
	var distances:Array = []):
	
	#get positions and uvs of the triangle
	var t = get_face_vertices(mdt, i)
	#copy positions of t into another triangle to calculate position later
	var u:PoolVector3Array = t[0]
	
	#convert uvs into Vector3 with y=0
	for k in t[1].size():
		t[1][k] = Vector3(t[1][k].x, 0, t[1][k].y)
	#send expanded uvs into t
	t = Triangle.new(t[1])
	
	var c:Vector3 = t.center()
	
	#check uv set for anything contained in the face
	for j in uv.size():
		#get the barycentric coordinates of p in t
		var b = t.barycentric(uv[j])
		#weight distance of uv to center by the magnitude of the barycentric coords
		var d:float = uv[j].distance_to(c)
		
		#whether uv[j] is closer to t or not, assume not
		var closer:bool = false
		#if distances were fed into the method, check for a closer distance
		if distances.size() > j:
			if d < distances[j]:
				distances[j] = d
				closer = true
		#check if t is surrounding uv[j], but a closer distance can circumvent this measure
		var surrounding:bool = t.is_surrounding(uv[j])
		if surrounding || closer:
			#reconstruct the 3d position of uv[j] from b and u
			var out:Vector3 = b[0] * u[0] + b[1] * u[1] + b[2] * u[2]
			#return data about the triangle
			#encode the face index, position of uv[j] in 3D normal and the input uv into the result
			return [i, out, mdt.get_face_normal(i), Vector2(uv[j].x, uv[j].z), surrounding]

	#if no more uvs can be checked, return null
	return null
				
#retrieve an Arrays object from a face index of a MeshDataTool
static func get_face_vertices(var mdt:MeshDataTool, var i:int):
	return [[mdt.get_vertex(mdt.get_face_vertex(i, 0)),
	mdt.get_vertex(mdt.get_face_vertex(i, 1)),
	mdt.get_vertex(mdt.get_face_vertex(i, 2))],
	[mdt.get_vertex_uv(mdt.get_face_vertex(i, 0)),
	mdt.get_vertex_uv(mdt.get_face_vertex(i, 1)),
	mdt.get_vertex_uv(mdt.get_face_vertex(i, 2))]]

#convert from uv coordinate to square using the size in squares of the board
static func uv_to_square(var size:Vector2, var pos):
	if pos == null: return null
	var large = pos * size
	large.x = floor(large.x)
	large.y = floor(large.y)
	return large
	
#convert from square on the board to uv coordinates
static func square_to_uv(var size:Vector2 = Vector2.ONE, var pos:Vector2 = Vector2.ZERO):
	var square = Vector2.ONE/size
	#add 1 to pos to adjust for board starting at 0, 0
	#subtract one half of the square size to get the uv coordinate in the center of the target square
	return (pos + Vector2.ONE)/(size) - square/2

#combine space converters into single function
static func square_to_mdata(var mdt:MeshDataTool = null, var size:Vector2 = Vector2.ONE, var pos:Vector2 = Vector2.ZERO):
	var uv = square_to_uv(size, pos)
	return uv_to_mdata(mdt, uv)

#take an input board mdt, board, and piece to return a Transform for the associated PieceMesh accosiated with piece on the mdt constructed from a BoardMesh
static func square_to_transform(var mdt:MeshDataTool, 
	var board:Board, var piece:Piece):
	
	#reference useful piece properties in other variables
	var pos:Vector2 = piece.get_pos()
	var table:Dictionary = piece.table
	
	#create a new transform to modify
	var transform:Transform = Transform()
	
	#get mesh data on square center for position and normal of the piece
	#if the piece is not centered on its origin, offsets can be created
	var mdata = square_to_mdata(mdt, board.size, pos)
	#skip function if mdata returns null
	if mdata == null:
		return transform
	
	#ROTATION
	#go through each of the transformation steps
	#check piece's settings on each before running each function
	if table["rotate_mode"] != 2:
		transform.basis = square_to_basis(mdt, board, piece, mdata)
		
	#SCALE
	#scale does not need the mdata step, but has to be executed after rotation
	#if scale mode is 0, scale piece by board's piece scale param
	if table["scale_mode"] == 0:
		transform = transform.scaled(Vector3.ONE * board.table["piece_scale"])
	#TODO if scale mode is 1, dynamically scale piece, this is left up to PieceMesh
	#if scale mode is 2, ignore scaling
	
	#TRANSLATION
	#translate the piece to the center of the square after the scaling and rotation steps
	if table["translate_mode"] != 2:
		transform.origin = mdata[1]
	
	return transform

#convert the normal of a square on the board to a set of basis vectors
static func square_to_basis(var mdt:MeshDataTool, var board:Board, 
	var piece:Piece, var mdata:Array):
		
	if mdata == null: return Basis()
	
	#up vector will take the normal of the square
	var up:Vector3 = mdata[2].normalized()
	
	#forward vector will try to look at square in forward direction from piece, and use the relative directions to form a vector
	var v:Vector2 = piece.get_forward()
	var d = 0
	#check if piece's direction goes out of bounds, if so try next orthogonal direction
	#keep trying orthogonal directions until a valid spot is found
	while !board.is_surrounding(piece.get_pos() + v) && d < 4:
		v = v.tangent()
		d += 1
	#if no directions are valid, just default to Vector3.forward
	var mf = [-1, Vector3.FORWARD, Vector3.UP]
	if d < 4 && v != Vector2.ZERO:
		mf = square_to_mdata(mdt, board.size, piece.get_pos() + v)
	
	#process mf[1] into a vector that is orthogonal to up
	#these vectors are not necesarily orthogonal, but a true forward can be computed from up and right later
	var fd:Vector3 = (mf[1] - mdata[1]).normalized()
	
	#last basis vector is cross of up and forward
	var rt = up.cross(fd)
	
	#to force fd to be orthogonal to up, cross up with right
	fd = rt.cross(up)
	
	#finally, send the basis as a transform into self.transform
	var b:Basis = Basis(rt, up, fd)
	
	return b

#run square to box and add mesh as a CSGMesh child of an input parent node
static func square_to_child(var parent:Node, 
	var square:Vector2=Vector2.ZERO, var material:Material = SpatialMaterial.new(), var name:String = ""):
	
	var m = square_to_box(parent, square)
	var csg = CSGMesh.new()
	csg.mesh = m
	csg.material = material
	if name.empty(): name = "Square " + String(parent.board.size)
	csg.name = name
	parent.add_child(csg)
	
	return csg

#WIP return a convex cube mesh bounding a square
static func square_to_box(var board:Node, var square:Vector2=Vector2.ZERO):
	
	#size and mesh of the board
	var size:Vector2 = board.size
	var mdt:MeshDataTool = board.mdt
	#bound and uv corners of the square
	var b:Bound = square_to_bound(size ,square)
	var c:PoolVector2Array = b.get_corners()
	
	#surface builder st and mesh m for st to push into when the box is finished being constructed
	var m:ArrayMesh = ArrayMesh.new()
	var st:SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	#mdata of each uv corner
	var coverts:Array = []
	coverts.resize(4)
	for i in range(0, 4):
		#get mdata of each corner
		coverts[i] = uv_to_mdata(mdt, c[i])
		#convert coverts to vert arrays
		coverts[i] = mdata_to_array(coverts[i])
		
		#add verts into surface tool
		st.add_normal(array_to_vert(coverts[i], 1))
		st.add_uv(array_to_vert(coverts[i], 2))
		st.add_vertex(array_to_vert(coverts[i], 0))
		
	#PoolRealArray Dictionary of PoolIntArrays represeting indices of mdt with duplicate data
	var duplicates:Dictionary = board.duplicates
	#integer Dictionary of faces intersecting with b and their verts
	var faces:Dictionary = {}
	#PoolRealArray Dictionary of PoolVector2Array intersections, vertices with edges that they could move to
	var outer:Dictionary = {}
	
	#for each vertex in the dupmap, check if it is inside b or has edges intersecting b
	#store any connected faces to duplicates of "a" that fill these conditions
	for a in duplicates:
		#if uv of a is inside b, add all connected triangles
		var uv:Vector2 = array_to_vert(a, 2)
		
		#flags for whether a is inside b, and whether its connected to a face intersecting b
		var inside:bool = b.is_surrounding(uv)
		var connected:bool = inside
		
		#store uv intersections of edges from a with b
		var intersections:PoolVector2Array = []
			
		#loop through duplicates of a to find intersections and connections to b
		for i in duplicates[a]:
			#get the faces of each duplicate
			var fs:PoolIntArray = mdt.get_vertex_faces(i)
			#check each connected face
			for f in fs:
				#construct and array of vertices from the face verts
				var v:PoolIntArray = [-1, -1, -1]
				for j in range(0, 3):
					v[j] = mdt.get_face_vertex(f, j)
				
				#if uv is inside b, add faces connected to a to faces
				if inside: faces[f] = v
				#otherwise, check for edge intersecitons with b
				else: 
					for j in range(0, 3):
						var uv1:Vector2 = mdt.get_vertex_uv(v[j])
						if uv1 == uv: continue
						#if there are intersections, add face and flag connected
						var inter:PoolVector2Array = b.edge_set_intersection([uv1, uv])
						if inter.empty(): continue
						#add intersections not already found
						for k in inter.size():
							var added:bool = false
							for l in intersections.size():
								if intersections[l] == inter[k]: 
									added = true
									break
							if !added: intersections.append(inter[k])
						faces[f] = v
						connected = true
					
				#if this face connected to a has an intersection, flag connected
				if faces.has(f):
					connected = true
		
		#add a to the appropriate set depending on inside and connected
		if !inside && connected: outer[a] = intersections
		
	debug_positions(board, outer.keys(), 0.1)
	
	#PoolRealArray Dictionary of PoolRealArrays, verts with their target positions
	var verts:Dictionary = {}
	#bool Array of whether each corner has been filled
	#find closest intersection to each outer point
	for i in outer:
		#distance of closest intersection and uv of outer
		var distance:float = INF
		var uv:Vector2 = array_to_vert(i, 2)
		#array of intersections and index of closest intersection
		var inter:PoolVector2Array = outer[i]
		var close:int = -1
		#ensure intersections has contents by appending the corner uvs
		inter.append_array(c)
		#loop through inter, replace close with j when inter[j] is closer than distance to uv
		for j in inter.size():
			var d:float = uv.distance_to(inter[j])
			if d < distance:
				distance = d
				close = j
		#create vert array for inter[close] to add as i's movement in verts
		if close > inter.size() - 4:
			verts[i] = coverts[close - inter.size() + 4]
		else:
			var mdata = uv_to_mdata(mdt, inter[close])
			verts[i] = mdata_to_array(mdata)
				
	#if square is flat, index faces into two triangles like so
	if faces.empty():
		st.add_index(2)
		st.add_index(1)
		st.add_index(0)
		st.add_index(3)
		st.add_index(2)
		st.add_index(0)
	else:
		var count:int = 4
		for i in faces:
			for j in range(0, 3):
				var v:int = mdt.get_face_vertex(i, j)
				var a:PoolRealArray = vert_to_array(mdt, v)
				#replace vert array with new data if it has been moved
				if verts.has(a): a = verts[a]
				
				st.add_normal(array_to_vert(a, 1))
				st.add_uv(array_to_vert(a, 2))
				st.add_vertex(array_to_vert(a, 0))
				st.add_index(count)
				count += 1
	
		
	#commit st to m and return it
	st.commit(m)
	var md = MeshDataTool.new()
	md.create_from_surface(m, 0)
	return m

#convert a square in uv space to a Bound object
static func square_to_bound(var size:Vector2, var square:Vector2):
	var center:Vector2 = square_to_uv(size, square)
	var half_square:Vector2 = Vector2(1 / size.x, 1 / size.y) * 0.5
	return Bound.new(center + half_square, center - half_square)

#convert mouse position in pixels from the top left to uv from the bottom left
static func mpos_to_screenuv(var pos:Vector2):
	#find size of screen at the time to normalize pos, then invert pos.y
	pos /= OS.window_size
	pos.y = 1 - pos.y
	return pos

#convert raycast hit to uv on mesh by projecting mesh onto camera and seeing if any triangles surround the input position
static func mpos_to_uv(var mdt:MeshDataTool, var board:Transform, 
	var transform:Transform, var pos:Vector3 = Vector3.ZERO):
	
	var p:Vector3 = transform.xform_inv(pos)
	#send p into xy plane
	p.z = 0
	
	#Triangle array of triangles projected into Camera space
	var triangles:Array = []
	#array of distances used to sort triangles
	var distances:PoolRealArray = []
	
	#loop through each triangle on the mdt and add triangles that surround p
	for i in mdt.get_face_count():
		#skip faces facing away from the camera
		if mdt.get_face_normal(i).dot(transform.basis.z) < 0:
			continue
			
		#get camera space position of triangle
		var tri = get_face_vertices(mdt, i)
		#project positions into world space, and then camera space
		var t = tri[0]
		for j in range(0, 3):
			t[j] = board.xform(t[j])
			t[j] = transform.xform_inv(t[j])
			t[j].z = 0
		tri = Triangle.new(tri[0], tri[1])

		#check if triangle is surrounding modded pos p
		if tri.is_surrounding(p):
			triangles.append(tri)
			t = get_face_vertices(mdt, i)
			t = Triangle.new(t[0], t[1])
			distances.append(t.center().distance_to(pos))

	#get closest triangle to p
	var d = INF
	var m = -1
	for i in distances.size():
		var t = get_face_vertices(mdt, i)
		t = Triangle.new(t[0], t[1])
		if distances[i] < d:
			m = i
	#if nothing is less than infinity, something is horribly wrong
	if m == -1:
		return null
	

	#return barycentric uv coords of p with the mth element of triangles
	return triangles[m].uv(p)

#import mesh from .obj path
static func path_to_mesh(var path:String = "", var debug:bool = false):
	#parse board using parser script into loadable mesh
	var m = ObjParse.parse_obj(path, path.substr(0, path.length() - 3) + "mtl", debug)
	
	#create mdt to read mesh
	var mdt:MeshDataTool = MeshDataTool.new()
	mdt.create_from_surface(m, 0)
	#if mesh was not created correctly, read from default mesh path
	if mdt.get_vertex_count() == 0:
		path = "Instructions/default/meshes/default.obj"
		m = ObjParse.parse_obj(path, path.substr(0, path.length() - 3) + "mtl", debug)
	
	return m

#create a convex or concave shape from a mesh dependant on whether or not the mesh is flat
static func mesh_to_shape(var m:Mesh):
	return m.create_trimesh_shape()

#get all verts and faces connected to an index in mdt
#return [0] is vert dictionary, return [1] is face dicitonary
static func vert_to_triangle_fan(var mdt:MeshDataTool, var i:int = 0, 
	var verts:Dictionary = {}, var faces:Dictionary = {}, var edges:bool = false):
	
	#get connected faces
	var fs:Array
	if edges:
		fs = mdt.get_edge_faces(i)
	else:
		fs = mdt.get_vertex_faces(i)
	
	#loop through faces and add their verts
	for f in fs:
		#add face to faces dict so calling function can see the faces being searched
		faces[f] = get_face_vertices(mdt, f)[0]
		for j in range(0, 3):
			var v = mdt.get_face_vertex(f, j)
			#same deal as faces
			verts[v] = [f, mdt.get_vertex(v), mdt.get_vertex_normal(v)]
	
	#in case vert_to_triangle_fan doesnt have dictionary args, return them back out
	return [verts, faces]

#return a Dictionary of PoolRealArray and PoolIntArrays keying sets of vertices to positions
static func find_duplicates(var mdt:MeshDataTool):
	
	var verts:Dictionary= {}
	
	#loop through each face
	for i in mdt.get_face_count():
		#see if each vertex of each face already exists
		for j in range(0, 3):
			var k:int = mdt.get_face_vertex(i, j)
			#key vertex by its properties, preserving split edges
			var v:PoolRealArray = vert_to_array(mdt, k)
		
			#if vertex already exists, add a match
			if verts.has(v):
				verts[v].append(k)
			#if not, add vertex position with index as first match
			else:
				#add vertex position to dictionary
				verts[v] = [k]
	
	return verts

#copy a set of duplicate vertices (i in duplicates) into an indexmap,
#then increment the number of unique vertices in the indexmap, returns new count
static func map_duplicates(var duplicates:Dictionary, var indexmap:Dictionary,
	var i:PoolRealArray, var count:int = 0):
	
	var a:PoolIntArray = duplicates[i]
	for j in a.size():
		indexmap[a[j]] = count
	return count + 1

#fit uv to the square between Vector2.ZERO and Vector2.ONE
static func clamp_uv(var uv:Vector2):
	uv.x = fmod(uv.x, 1)
	uv.y = fmod(uv.y, 1)
	return uv

#convert a vertex on an mdt to a PoolRealArray of properties
#can also create an array from a larger array of multiple vertices
static func vert_to_array(var data, var i:int = 0):
	
	if data is MeshDataTool:
		var p:Vector3 = data.get_vertex(i)
		var n:Vector3 = data.get_vertex_normal(i)
		var u:Vector2 = data.get_vertex_uv(i)
		var v:PoolRealArray = [p.x, p.y, p.z, n.x, n.y, n.z, u.x, u.y]
		return v
	if data is PoolRealArray:
		var v:PoolRealArray = PoolRealArray()
		v.resize(8)
		for j in range(0, 8):
			v[j] = data[j + i]
		return v
	else:
		return PoolRealArray()
		
#convert a return from the mdata method to a vertex array
static func mdata_to_array(var mdata:Array):
	#convert coverts to vert arrays
	var v:Vector3 = mdata[1]
	var u:Vector2 = mdata[3]
	var n:Vector3 = mdata[2]
	var a:PoolRealArray = [v.x, v.y, v.z, n.x, n.y, n.z, u.x, u.y]
	return a

#decode an array from vert_to_array() back into a position (0), normal (1), or uv (2) based on mode
#start is the starting index in a from which to decode
static func array_to_vert(var a:PoolRealArray, var mode:int = 0, var start:int = 0):
	#if array is too small, return null
	if a.size() < start + 8: return null
	#return parts of the array relevant to mode
	if mode == 2:
		return Vector2(a[start + 6], a[start + 7])
	elif mode == 1:
		return Vector3(a[start + 3], a[start + 4], a[start + 5])
	else:
		return Vector3(a[start], a[start + 1], a[start + 2])
		
#add a vertex array from vert_to_array() into a SurfaceTool
static func add_array_to_surface(var st:SurfaceTool, var a:PoolRealArray):
	st.add_normal(array_to_vert(a, 1))
	st.add_uv(array_to_vert(a, 2))
	st.add_vertex(array_to_vert(a, 0))

#cast out a ray from the camera, given a physics state s
static func raycast(var p:Vector2, var c:Camera, 
	var w:World, var v:float = INF, var mask:int = 0x7FFFFFFF):
	
	#get physics state of the current scene
	var s = w.direct_space_state
	#origin and normal of the camera
	var o:Vector3 = c.project_ray_origin(p)
	var n:Vector3 = c.project_ray_normal(p)
	#get ray intersection with that scene
	var r = s.intersect_ray(o, n * v, [], mask)
	#if the intersection lands, return r
	if !r.empty():
		return r
	return null

#add CSGsphere children to node at relative positions
#setting mode to 1 will stop the method from deleting old csgballs
static func debug_positions(var node:Node = null, var positions:Array = [], 
	var radius:float = 0.1, var mode:int = 0):
	
	#remove old debug objects
	if mode != 1:
		for c in node.get_children():
			if c.name.find("debug") != -1:
				node.remove_child(c)
				
	#if position map is empty, exit function
	if positions.empty(): return
	
	#material to apply to the CSGBalls
	var material:Material = SpatialMaterial.new()
	
	#checks if positions is an Array of PoolRealArray, assumes all elements are of same type
	var t:bool = positions[0] is PoolRealArray
	
	#add new ones
	for p in positions: 
		if t:
			p = array_to_vert(p)
		
		var csg = CSGSphere.new()
		csg.radius = radius
		csg.material = material
		csg.transform.origin = p
		csg.name = "debug " + String(p)
		node.add_child(csg)

#debug positions alternative which instead takes a MeshDataTool and an array of vertex indices as arguments
static func debug_vertices(var node:Node, var mdt:MeshDataTool, var positions:PoolIntArray = [],
	var mode:int = 0, var radius:float = 0.1):
		
	if positions.size() == 0:
		return
	
	var p:PoolVector3Array = PoolVector3Array()
	p.resize(positions.size())
	
	for i in p.size():
		p[i] = mdt.get_vertex(positions[i])
	
	debug_positions(node, p, mode, radius)
