--!optimize 2
--[[
	============================================================================================
	 CLASSIC STENCIL SHADOWS - a real-time recreation of Roblox's old (2008-2013) stencil shadows
	============================================================================================
	 Setup: put this in a LocalScript in StarterPlayer > StarterPlayerScripts.
	        Press 9 to switch between Roblox's shadows and the stencil shadows.

	 How it works (the same approach as the "real-time stencil shadow system" on the DevForum):

	 * Every opaque part is a shadow caster. Its outline is pushed along the light direction onto
	   every surface behind it (a shadow volume), cut to fit each surface exactly, split into
	   triangles and written into EditableMeshes. Blocks use their corners, balls / cylinders /
	   capsules their curves, meshes their real triangles (or a raycast-sampled outline when the
	   mesh data can't be read).
	 * The meshes are 99.9% transparent. One Highlight (black fill at 0.6, no outline, Occluded)
	   paints the whole shadow model in a single pass, so overlapping shadows never get darker
	   than one shadow - which is exactly what made stencil shadows look the way they did.
	 * If EditableMesh isn't allowed in the game, the same shadow triangles are drawn with thin
	   wedge parts instead (same Highlight trick, same look).
	 * Still parts are grouped into chunks around the camera and built nearest-first inside a
	   per-frame time budget. Moving parts and characters are rebuilt every frame. Shadows also
	   land on players and loose parts, drape over terrain, and the sides of parts that face away
	   from the light are darkened as if they were inside the old shadow volumes.
	 * Shadows follow the sun, and the moon at night.

	 Other scripts can use _G.StencilShadows:  SetEnabled(bool), Toggle(), IsEnabled(),
	 Rebuild(), GetStats(), Destroy().
	============================================================================================
]]

local CONFIG = {
	-- Controls ----------------------------------------------------------------------------------
	ToggleKey = Enum.KeyCode.Nine,        -- switches between Roblox shadows and stencil shadows
	StartEnabled = true,

	-- Look --------------------------------------------------------------------------------------
	ShadowColor = Color3.new(0, 0, 0),
	ShadowTransparency = 0.6,             -- Highlight fill transparency (0.6 = the classic darkness)
	RenderStyle = "Highlight",            -- "Highlight": all shadows merged, overlaps never stack
	                                      -- "Direct":    plain see-through black geometry
	DirectTransparency = 0.62,            -- part transparency used by the "Direct" style
	SurfaceOffset = 0.04,                 -- how far shadows float off a surface (stops z-fighting)
	ShadeBackFaces = true,                -- sides facing away from the light are shadowed too
	TransparentShadows = false,           -- TRANSPARENT_SHADOWS_ENABLED: see-through parts cast
	TransparentShadowTransparency = 0.75, -- ...lighter shadows tinted with their own color

	-- Renderer ----------------------------------------------------------------------------------
	Backend = "Auto",                     -- "Auto" | "EditableMesh" | "Parts"
	                                      -- EditableMesh needs Game Settings > Security >
	                                      -- "Allow Mesh / Image APIs". Auto falls back to parts.

	-- Light -------------------------------------------------------------------------------------
	UseMoon = true,
	MinLightElevation = 1.5,              -- degrees; sun AND moon lower than this = no shadows
	MinShadowElevation = 8,               -- degrees; a lower light is raised to this angle
	LightUpdateAngle = 0.6,               -- degrees the light must move before map shadows rebuild
	MaxShadowLength = 200,                -- studs a shadow can reach past its caster

	-- Range & detail ----------------------------------------------------------------------------
	ShadowDistance = 520,                 -- map shadows are kept within this distance of the camera
	ChunkSize = 64,                       -- studs; map shadows load and unload per chunk
	NearDetail = 140,                     -- full detail (smooth curves, exact mesh shadows) within this
	MidDetail = 320,
	CurveSegments = {24, 16, 10},         -- sides used for round shadows: near / mid / far

	-- What casts and receives -------------------------------------------------------------------
	RespectCastShadow = true,             -- parts with CastShadow off don't cast stencil shadows
	MinPartSize = 0.15,                   -- skip parts whose largest side is smaller than this
	OpaqueThreshold = 0.05,               -- Transparency above this counts as a transparent part
	MeshShadows = true,                   -- read real mesh data for MeshParts / FileMeshes
	ExactMeshTriangles = 1200,            -- meshes up to this many triangles get exact (concave) shadows
	MeshReceiverTriangles = 600,          -- meshes up to this many triangles receive shadows on them
	RaySampleMeshes = true,               -- if mesh data can't be read, sample the shape with raycasts
	MissingMeshFallback = "None",         -- "None" (like the original) or "Box" when all else fails
	UnionShadows = true,
	TerrainShadows = true,
	CharacterShadows = true,
	AccessoryShadows = true,
	IgnoreAttribute = "NoStencilShadow",  -- set this attribute to true on a part / model to skip it

	-- Moving things -----------------------------------------------------------------------------
	DynamicDistance = 260,                -- moving parts and characters cast shadows within this range
	MaxCharacters = 8,
	MaxMovingShadows = 150,
	RestTime = 1.5,                       -- seconds a moved part must stay still to rejoin the map
	ReceiverDistance = 120,               -- players / loose parts this close get shadows drawn on them
	MaxCharacterReceivers = 3,
	MaxLooseReceivers = 24,

	-- Performance -------------------------------------------------------------------------------
	FrameBudget = 4.2,                    -- milliseconds of work per frame
	LoadingBudget = 9,                    -- milliseconds per frame while shadows are still loading
	RegisterPerFrame = 2500,              -- parts scanned per frame at startup
	PollPerFrame = 250,                   -- resting unanchored parts checked for movement per frame

	-- Roblox's own shadows ----------------------------------------------------------------------
	DisableRobloxShadows = true,          -- Lighting.GlobalShadows is off while this is enabled
}

----------------------------------------------------------------------------------------------------
-- Services, shortcuts, constants
----------------------------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")

local LocalPlayer = Players.LocalPlayer

local abs, sqrt, min, max, floor, ceil = math.abs, math.sqrt, math.min, math.max, math.floor, math.ceil
local cos, sin, atan2, rad, pi, huge = math.cos, math.sin, math.atan2, math.rad, math.pi, math.huge
local clock = os.clock
local V3 = Vector3.new
local ZERO = Vector3.zero
local XAXIS, YAXIS, ZAXIS = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis
local tsort, tremove, tcreate = table.sort, table.remove, table.create

local CONTAINER_NAME = "__StencilShadows"
local TINT_CONTAINER_NAME = "__StencilShadowsTinted"
local SAVED_SHADOWS_ATTR = "StencilShadowsSavedGlobalShadows"

local CONTACT = 0.01       -- studs; caster points this close to a surface count as touching it
local MIN_LIT = 0.02       -- a face must face the light at least this much (cosine) to receive
local MIN_AREA = 4e-4      -- shadow pieces smaller than this (studs^2) are dropped
local MARGIN = 0.25        -- studs added around spatial queries
local TERRAIN_OFFSET = 0.12
local WEDGE_THICKNESS = 0.01

----------------------------------------------------------------------------------------------------
-- Stop a previous copy of this script (or the older SurfaceGui engine) if one is running
----------------------------------------------------------------------------------------------------
do
	for _, key in ipairs({"__StencilShadowsCleanup", "__StencilShadowEngineCleanup"}) do
		local fn = _G[key]
		if type(fn) == "function" then
			pcall(fn)
			_G[key] = nil
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		local name = child.Name
		if name == CONTAINER_NAME or name == TINT_CONTAINER_NAME or name == "__StencilShadowReceivers" then
			pcall(child.Destroy, child)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Runtime state
----------------------------------------------------------------------------------------------------
local alive = true
local enabled = CONFIG.StartEnabled ~= false
local frameId = 0
local connections = {}

local states = {}              -- BasePart -> state
local characters = {}          -- character Model -> info
local chunks = {}              -- chunk key -> chunk of still casters
local dynamicStates = {}       -- moving (non-character) states
local physList = {}            -- resting unanchored parts that are polled for movement
local physCursor = 1
local nextStateId = 0
local terrainPresent = false
local initialScanDone = false
local savedGlobalShadows = true
local errorCount = 0
local rebuildRequested = false
local refreshSoon = false      -- a new map chunk appeared: activate it next frame

local stats = {parts = 0, records = 0, pages = 0, wedges = 0, meshLoads = 0, frameMs = 0}

-- Functions shared between sections. Each section below is its own do-block so the script stays
-- far below Luau's limit of 200 locals per function.
local getShape, onShapeChanged, onPartChanged
local markDirty, markDependentsDirty, addToChunk, removeFromChunk, queueUpstream
local convexHull, clipLine, clipByLines, polyArea, reversePoly, edgeLines, setLine
local updateLight, supportPoints, waitForMesh, getGeom, getWorldFaces
local resetOut, emitFace, emitWorld, lightOverlap, castOnFace, drapeOnTerrain
local queryBox, dropRecord, buildStaticCaster, buildDynamicCaster, buildReceiverRecord, safeCall
local register, unregister, processChanges, processRemovals, processAdds, processCharacterChanges
local processMeshReady, processUpstream, pollPhysics, refreshCharacters, step

----------------------------------------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------------------------------------
local function newQueue()
	return {head = 1, tail = 0, items = {}}
end

local function qpush(q, v)
	local t = q.tail + 1
	q.tail = t
	q.items[t] = v
end

local function qpop(q)
	local h = q.head
	if h > q.tail then
		return nil
	end
	local items = q.items
	local v = items[h]
	items[h] = nil
	if h >= q.tail then
		q.head = 1
		q.tail = 0
	else
		q.head = h + 1
	end
	return v
end

local addQ, removeQ, changeQ, charQ, urgentQ, upstreamQ =
	newQueue(), newQueue(), newQueue(), newQueue(), newQueue(), newQueue()

local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local warnOnce
do
	local warned = {}
	function warnOnce(key, msg)
		if not warned[key] then
			warned[key] = true
			warn("[StencilShadows] " .. msg)
		end
	end
end

-- Packs three integers (+-32767) into one number key.
local function cellKey(ix, iy, iz)
	return ((ix + 32768) * 65536 + (iy + 32768)) * 65536 + (iz + 32768)
end

----------------------------------------------------------------------------------------------------
-- 2D polygon helpers (flat x / y arrays, counter-clockwise polygons)
----------------------------------------------------------------------------------------------------
do
	local hullKeyX, hullKeyY = nil, nil
	local function hullLess(i, j)
		local a, b = hullKeyX[i], hullKeyX[j]
		if a ~= b then
			return a < b
		end
		return hullKeyY[i] < hullKeyY[j]
	end

	local hullOrder = {}
	-- Monotone chain convex hull. Writes the CCW hull as indices into `out` and returns the count.
	function convexHull(px, py, n, out)
		if n < 3 then
			for i = 1, n do
				out[i] = i
			end
			return n
		end
		local order = hullOrder
		for i = 1, n do
			order[i] = i
		end
		for i = #order, n + 1, -1 do
			order[i] = nil
		end
		hullKeyX, hullKeyY = px, py
		tsort(order, hullLess)
		local k = 0
		for t = 1, n do
			local i = order[t]
			local x, y = px[i], py[i]
			while k >= 2 do
				local o, a = out[k - 1], out[k]
				local ox, oy = px[o], py[o]
				if (px[a] - ox) * (y - oy) - (py[a] - oy) * (x - ox) <= 1e-9 then
					k -= 1
				else
					break
				end
			end
			k += 1
			out[k] = i
		end
		local lowerEnd = k + 1
		for t = n - 1, 1, -1 do
			local i = order[t]
			local x, y = px[i], py[i]
			while k >= lowerEnd do
				local o, a = out[k - 1], out[k]
				local ox, oy = px[o], py[o]
				if (px[a] - ox) * (y - oy) - (py[a] - oy) * (x - ox) <= 1e-9 then
					k -= 1
				else
					break
				end
			end
			k += 1
			out[k] = i
		end
		return k - 1
	end

	-- Keeps the part of a polygon where A*x + B*y + C >= 0. Writes into (ox, oy), returns the count.
	function clipLine(ix, iy, n, A, B, C, ox, oy)
		if n == 0 then
			return 0
		end
		local m = 0
		local px, py = ix[n], iy[n]
		local pd = A * px + B * py + C
		for i = 1, n do
			local cx, cy = ix[i], iy[i]
			local cd = A * cx + B * cy + C
			if cd >= 0 then
				if pd < 0 then
					local t = pd / (pd - cd)
					m += 1
					ox[m] = px + (cx - px) * t
					oy[m] = py + (cy - py) * t
				end
				m += 1
				ox[m] = cx
				oy[m] = cy
			elseif pd >= 0 then
				local t = pd / (pd - cd)
				m += 1
				ox[m] = px + (cx - px) * t
				oy[m] = py + (cy - py) * t
			end
			px, py, pd = cx, cy, cd
		end
		return m
	end

	local clipAX, clipAY, clipBX, clipBY = {}, {}, {}, {}
	-- Clips a polygon by lines {A, B, C, A, B, C, ...}. The input must not be one of the clip buffers.
	function clipByLines(sx, sy, n, lines, nLines)
		local inX, inY, outX, outY = sx, sy, clipAX, clipAY
		for l = 0, nLines - 1 do
			local base = l * 3
			n = clipLine(inX, inY, n, lines[base + 1], lines[base + 2], lines[base + 3], outX, outY)
			if n < 3 then
				return 0, outX, outY
			end
			if outX == clipAX then
				inX, inY, outX, outY = clipAX, clipAY, clipBX, clipBY
			else
				inX, inY, outX, outY = clipBX, clipBY, clipAX, clipAY
			end
		end
		return n, inX, inY
	end

	function polyArea(xs, ys, n)
		local a = 0
		local jx, jy = xs[n], ys[n]
		for i = 1, n do
			local x, y = xs[i], ys[i]
			a += jx * y - x * jy
			jx, jy = x, y
		end
		return a * 0.5
	end

	function reversePoly(xs, ys, n)
		local i, j = 1, n
		while i < j do
			xs[i], xs[j] = xs[j], xs[i]
			ys[i], ys[j] = ys[j], ys[i]
			i += 1
			j -= 1
		end
	end

	-- Unit-length inward edge lines of a CCW convex polygon.
	function edgeLines(xs, ys, n)
		local lines = {}
		for i = 1, n do
			local ax, ay = xs[i], ys[i]
			local j = i % n + 1
			local ex, ey = xs[j] - ax, ys[j] - ay
			local len = sqrt(ex * ex + ey * ey)
			if len > 1e-7 then
				local A, B = -ey / len, ex / len
				lines[#lines + 1] = A
				lines[#lines + 1] = B
				lines[#lines + 1] = -(A * ax + B * ay)
			end
		end
		return lines, #lines / 3
	end

	function setLine(lines, idx, ax, ay, bx, by)
		local ex, ey = bx - ax, by - ay
		local len = sqrt(ex * ex + ey * ey)
		if len < 1e-9 then
			len = 1e-9
		end
		local A, B = -ey / len, ex / len
		local base = idx * 3
		lines[base + 1] = A
		lines[base + 2] = B
		lines[base + 3] = -(A * ax + B * ay)
	end
end

----------------------------------------------------------------------------------------------------
-- Light: the sun, or the moon at night
----------------------------------------------------------------------------------------------------
local Light = {
	valid = false,
	version = 0,
	dir = YAXIS,   -- points toward the light
	L = -YAXIS,    -- the direction light travels
	a = XAXIS,     -- a and b are perpendicular to L, with a:Cross(b) == L
	b = ZAXIS,
}

do
	local function readLightDirection()
		local minY = sin(rad(CONFIG.MinLightElevation))
		local dir = Lighting:GetSunDirection()
		if dir.Y < minY then
			if not CONFIG.UseMoon then
				return nil
			end
			dir = Lighting:GetMoonDirection()
			if dir.Y < minY then
				return nil
			end
		end
		local floorY = sin(rad(CONFIG.MinShadowElevation))
		if dir.Y < floorY then
			local hx, hz = dir.X, dir.Z
			local h = sqrt(hx * hx + hz * hz)
			if h < 1e-6 then
				hx, hz, h = 1, 0, 1
			end
			local c = sqrt(1 - floorY * floorY)
			dir = V3(hx / h * c, floorY, hz / h * c)
		end
		return dir.Unit
	end

	local function setLight(dir)
		local L = -dir
		local ref = abs(L.Y) < 0.9 and YAXIS or XAXIS
		local a = ref:Cross(L).Unit
		Light.dir = dir
		Light.L = L
		Light.a = a
		Light.b = L:Cross(a).Unit
		Light.version += 1
	end

	-- Returns true when the map shadows have to be rebuilt.
	function updateLight()
		local dir = readLightDirection()
		if not dir then
			if Light.valid then
				Light.valid = false
				return true
			end
			return false
		end
		local moved = dir:Dot(Light.dir) < cos(rad(CONFIG.LightUpdateAngle))
		if not Light.valid then
			Light.valid = true
			if moved or Light.version == 0 then
				setLight(dir)
			end
			return true
		end
		if moved then
			setLight(dir)
			return true
		end
		return false
	end
end

----------------------------------------------------------------------------------------------------
-- Shape library: local-space caster geometry and receiving faces, cached and shared
----------------------------------------------------------------------------------------------------
local Shapes = {}
do
	local shapeCache = setmetatable({}, {__mode = "v"})

	local function vkey(v)
		return string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z)
	end

	local function averageOf(verts)
		local s = ZERO
		for i = 1, #verts do
			s += verts[i]
		end
		return s / #verts
	end

	local function newellNormal(verts)
		local nx, ny, nz = 0, 0, 0
		local count = #verts
		for i = 1, count do
			local p, q = verts[i], verts[i % count + 1]
			nx += (p.Y - q.Y) * (p.Z + q.Z)
			ny += (p.Z - q.Z) * (p.X + q.X)
			nz += (p.X - q.X) * (p.Y + q.Y)
		end
		return V3(nx, ny, nz)
	end

	local function angleLess(p, q)
		return p[3] < q[3]
	end

	-- A flat convex face: origin, normal, in-plane axes (u, v, n right-handed) and its 2D outline.
	local function makeFace(n, verts)
		local count = #verts
		if count < 3 then
			return nil
		end
		local o = averageOf(verts)
		local u = verts[1] - o
		u -= n * u:Dot(n)
		if u.Magnitude < 1e-7 then
			u = (abs(n.Y) < 0.9 and YAXIS or XAXIS):Cross(n)
		end
		u = u.Unit
		local v = n:Cross(u)
		local items = tcreate(count)
		for i = 1, count do
			local d = verts[i] - o
			local x, y = d:Dot(u), d:Dot(v)
			items[i] = {x, y, atan2(y, x)}
		end
		tsort(items, angleLess)
		local xs, ys = tcreate(count), tcreate(count)
		for i = 1, count do
			xs[i] = items[i][1]
			ys[i] = items[i][2]
		end
		local area = polyArea(xs, ys, count)
		if area < 1e-6 then
			return nil
		end
		local lines, nLines = edgeLines(xs, ys, count)
		if nLines < 3 then
			return nil
		end
		return {o = o, n = n, u = u, v = v, xs = xs, ys = ys, count = count, lines = lines, nLines = nLines}
	end

	-- Convex polyhedron from vertices and face index loops (outward normals worked out here).
	local function makePolyhedron(verts, faceLists)
		local centroid = averageOf(verts)
		local edges, seen, faces = {}, {}, {}
		local radius = 0
		for i = 1, #verts do
			radius = max(radius, verts[i].Magnitude)
		end
		for _, list in ipairs(faceLists) do
			local fv = tcreate(#list)
			for k = 1, #list do
				fv[k] = verts[list[k]]
			end
			local nrm = newellNormal(fv)
			if nrm.Magnitude > 1e-9 then
				nrm = nrm.Unit
				if nrm:Dot(averageOf(fv) - centroid) < 0 then
					nrm = -nrm
				end
				local face = makeFace(nrm, fv)
				if face then
					faces[#faces + 1] = face
				end
			end
			for k = 1, #list do
				local i, j = list[k], list[k % #list + 1]
				if i > j then
					i, j = j, i
				end
				local key = i * 65536 + j
				if not seen[key] then
					seen[key] = true
					edges[#edges + 1] = i
					edges[#edges + 1] = j
				end
			end
		end
		return {kind = "poly", verts = verts, edges = edges, faces = faces, radius = radius, shade = true}
	end

	local function translated(shape, offset)
		local copy = {}
		for k, v in pairs(shape) do
			copy[k] = v
		end
		local function moved(list)
			local out = tcreate(#list)
			for i = 1, #list do
				out[i] = list[i] + offset
			end
			return out
		end
		if shape.verts then
			copy.verts = moved(shape.verts)
		end
		if shape.points then
			copy.points = moved(shape.points)
		end
		if shape.tris then
			copy.tris = moved(shape.tris)
		end
		if shape.ellipsoids then
			local es = {}
			for i, e in ipairs(shape.ellipsoids) do
				es[i] = {c = e.c + offset, e1 = e.e1, e2 = e.e2, e3 = e.e3}
			end
			copy.ellipsoids = es
		end
		if shape.faces then
			local fs = tcreate(#shape.faces)
			for i, f in ipairs(shape.faces) do
				local nf = {}
				for k, v in pairs(f) do
					nf[k] = v
				end
				nf.o = f.o + offset
				fs[i] = nf
			end
			copy.faces = fs
		end
		copy.radius = shape.radius + offset.Magnitude
		return copy
	end

	local function cached(key, offset, build)
		local base = shapeCache[key]
		if not base then
			base = build()
			shapeCache[key] = base
		end
		if not offset or offset.Magnitude < 1e-6 then
			return base
		end
		local full = key .. "@" .. vkey(offset)
		local s = shapeCache[full]
		if not s then
			s = translated(base, offset)
			shapeCache[full] = s
		end
		return s
	end

	function Shapes.box(size, offset)
		return cached("B" .. vkey(size), offset, function()
			local x, y, z = size.X / 2, size.Y / 2, size.Z / 2
			return makePolyhedron({
				V3(-x, -y, -z), V3(x, -y, -z), V3(x, y, -z), V3(-x, y, -z),
				V3(-x, -y, z), V3(x, -y, z), V3(x, y, z), V3(-x, y, z),
			}, {
				{1, 2, 3, 4}, {5, 8, 7, 6}, {1, 4, 8, 5}, {2, 6, 7, 3}, {1, 5, 6, 2}, {4, 3, 7, 8},
			})
		end)
	end

	-- WedgePart: full bottom and back (+Z) faces, the slope runs from the front-bottom edge up to
	-- the back-top edge.
	function Shapes.wedge(size, offset)
		return cached("W" .. vkey(size), offset, function()
			local x, y, z = size.X / 2, size.Y / 2, size.Z / 2
			return makePolyhedron({
				V3(-x, -y, -z), V3(x, -y, -z), V3(x, -y, z), V3(-x, -y, z), V3(x, y, z), V3(-x, y, z),
			}, {
				{1, 2, 3, 4}, {4, 3, 5, 6}, {1, 6, 5, 2}, {2, 5, 3}, {1, 4, 6},
			})
		end)
	end

	-- CornerWedgePart: square bottom, peak above the right-front (+X, -Z) corner.
	function Shapes.cornerWedge(size, offset)
		return cached("C" .. vkey(size), offset, function()
			local x, y, z = size.X / 2, size.Y / 2, size.Z / 2
			return makePolyhedron({
				V3(-x, -y, -z), V3(x, -y, -z), V3(x, -y, z), V3(-x, -y, z), V3(x, y, -z),
			}, {
				{1, 2, 3, 4}, {2, 5, 3}, {1, 5, 2}, {1, 4, 5}, {4, 3, 5},
			})
		end)
	end

	-- Cylinder approximated by a prism whose flat sides touch the real curve (so shadows drawn on
	-- the sides never sink into the round surface).
	local function prism(len, r, segs, axis)
		local rc = r / cos(pi / segs)
		local h = len / 2
		local verts = {}
		for i = 0, segs - 1 do
			local t = (i + 0.5) * 2 * pi / segs
			local c, s = cos(t) * rc, sin(t) * rc
			if axis == "X" then
				verts[2 * i + 1] = V3(-h, c, s)
				verts[2 * i + 2] = V3(h, c, s)
			else
				verts[2 * i + 1] = V3(c, -h, s)
				verts[2 * i + 2] = V3(c, h, s)
			end
		end
		local faces, capA, capB = {}, {}, {}
		for i = 0, segs - 1 do
			local j = (i + 1) % segs
			capA[i + 1] = 2 * i + 1
			capB[i + 1] = 2 * i + 2
			faces[#faces + 1] = {2 * i + 1, 2 * j + 1, 2 * j + 2, 2 * i + 2}
		end
		faces[#faces + 1] = capA
		faces[#faces + 1] = capB
		return makePolyhedron(verts, faces)
	end

	function Shapes.cylinderX(size, segs, offset)
		return cached("X" .. vkey(size) .. "/" .. segs, offset, function()
			return prism(size.X, min(size.Y, size.Z) / 2, segs, "X")
		end)
	end

	function Shapes.cylinderY(height, diameter, segs, offset)
		return cached(string.format("Y%.3f,%.3f/%d", height, diameter, segs), offset, function()
			return prism(height, diameter / 2, segs, "Y")
		end)
	end

	-- Receiving faces of an ellipsoid: a UV sphere pushed out so its flat faces sit on the surface.
	local function ellipsoidFaces(rx, ry, rz, segs)
		local m = max(8, segs)
		local k = max(4, floor(m / 2))
		local push = 1 / cos(pi * 1.4143 / m)
		local rings = {}
		for i = 0, k do
			local theta = pi * i / k
			local st, ct = sin(theta), cos(theta)
			local ring = {}
			for j = 0, m - 1 do
				local phi = 2 * pi * j / m
				ring[j] = V3(st * cos(phi) * rx * push, ct * ry * push, st * sin(phi) * rz * push)
			end
			rings[i] = ring
		end
		local faces = {}
		for i = 0, k - 1 do
			for j = 0, m - 1 do
				local j2 = (j + 1) % m
				local fv
				if i == 0 then
					fv = {rings[0][0], rings[1][j2], rings[1][j]}
				elseif i == k - 1 then
					fv = {rings[i][j], rings[i][j2], rings[k][0]}
				else
					fv = {rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]}
				end
				local nrm = newellNormal(fv)
				if nrm.Magnitude > 1e-12 then
					nrm = nrm.Unit
					if nrm:Dot(averageOf(fv)) < 0 then
						nrm = -nrm
					end
					local face = makeFace(nrm, fv)
					if face then
						faces[#faces + 1] = face
					end
				end
			end
		end
		return faces
	end

	local function sphereAt(c, r)
		return {c = c, e1 = V3(r, 0, 0), e2 = V3(0, r, 0), e3 = V3(0, 0, r)}
	end

	function Shapes.ellipsoid(radii, segs, offset)
		return cached("E" .. vkey(radii) .. "/" .. segs, offset, function()
			return {
				kind = "round",
				segs = segs,
				shade = true,
				ellipsoids = {{c = ZERO, e1 = V3(radii.X, 0, 0), e2 = V3(0, radii.Y, 0), e3 = V3(0, 0, radii.Z)}},
				faces = ellipsoidFaces(radii.X, radii.Y, radii.Z, segs),
				radius = max(radii.X, radii.Y, radii.Z),
			}
		end)
	end

	function Shapes.ball(size, segs)
		local r = min(size.X, size.Y, size.Z) / 2
		return Shapes.ellipsoid(V3(r, r, r), segs)
	end

	function Shapes.capsule(size, segs)
		local r = min(size.Y, size.Z) / 2
		local half = size.X / 2 - r
		if half < 0.01 then
			return Shapes.ball(size, segs)
		end
		return cached("K" .. vkey(size) .. "/" .. segs, nil, function()
			return {
				kind = "round",
				segs = segs,
				shade = true,
				ellipsoids = {sphereAt(V3(-half, 0, 0), r), sphereAt(V3(half, 0, 0), r)},
				faces = prism(size.X, r, segs, "X").faces,
				radius = size.X / 2,
			}
		end)
	end

	local function isFlat(size)
		local lo = min(size.X, size.Y, size.Z)
		local mid = size.X + size.Y + size.Z - lo - max(size.X, size.Y, size.Z)
		return lo <= mid * 0.35
	end

	-- Shape from a sampled point cloud (normalized to -0.5..0.5 of the bounds).
	function Shapes.fromPoints(id, points, mul, add, receive)
		return cached("P" .. id .. "|" .. vkey(mul) .. "|" .. vkey(add) .. (receive and "r" or ""), nil, function()
			local pts = tcreate(#points)
			for i = 1, #points do
				pts[i] = points[i] * mul + add
			end
			local size = mul:Abs()
			return {
				kind = "mesh",
				points = pts,
				faces = (receive and isFlat(size)) and Shapes.box(size, add).faces or nil,
				shade = false,
				radius = (size * 0.5).Magnitude + add.Magnitude,
			}
		end)
	end

	-- Shape from real mesh data. Vertices are normalized; mul / add place them in part space.
	function Shapes.fromMesh(entry, mul, add)
		return cached("M" .. entry.id .. "|" .. vkey(mul) .. "|" .. vkey(add), nil, function()
			local verts, tris, hull = entry.verts, entry.tris, entry.hull
			local size = mul:Abs()
			local pts = tcreate(#hull)
			for i = 1, #hull do
				pts[i] = hull[i] * mul + add
			end
			local shape = {kind = "mesh", points = pts, shade = false, radius = (size * 0.5).Magnitude + add.Magnitude}
			local triCount = #tris / 3
			if triCount <= CONFIG.ExactMeshTriangles then
				local tv = tcreate(#tris)
				for i = 1, #tris do
					tv[i] = verts[tris[i]] * mul + add
				end
				shape.tris = tv
			end
			if triCount <= CONFIG.MeshReceiverTriangles then
				local faces = {}
				for t = 1, #tris, 3 do
					local A = verts[tris[t]] * mul + add
					local B = verts[tris[t + 1]] * mul + add
					local C = verts[tris[t + 2]] * mul + add
					local nrm = (B - A):Cross(C - A)
					if nrm.Magnitude > 1e-9 then
						local f = makeFace(nrm.Unit, {A, B, C})
						if f then
							faces[#faces + 1] = f
						end
					end
				end
				shape.faces = faces
			elseif isFlat(size) then
				shape.faces = Shapes.box(size, add).faces
			end
			return shape
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Mesh data: real mesh triangles read with EditableMesh, cached per mesh, retried with backoff
----------------------------------------------------------------------------------------------------
local MeshData = {allowed = false, entries = {}, queue = newQueue(), ready = newQueue(), running = false, nextId = 0}

do
	local SUPPORT_DIRS = {}
	do
		local n = 48
		local golden = pi * (3 - sqrt(5))
		for i = 0, n - 1 do
			local y = 1 - (i + 0.5) * 2 / n
			local r = sqrt(1 - y * y)
			local t = golden * i
			SUPPORT_DIRS[i + 1] = V3(cos(t) * r, y, sin(t) * r)
		end
	end

	-- The extreme points of a cloud in many directions: a small set with nearly the same hull.
	function supportPoints(verts, canYield)
		local n = #verts
		if n <= 48 then
			return verts
		end
		local picked, out = {}, {}
		local work = 0
		for d = 1, #SUPPORT_DIRS do
			local dir = SUPPORT_DIRS[d]
			local dx, dy, dz = dir.X, dir.Y, dir.Z
			local best, bi = -huge, 1
			for i = 1, n do
				local p = verts[i]
				local s = p.X * dx + p.Y * dy + p.Z * dz
				if s > best then
					best, bi = s, i
				end
			end
			if not picked[bi] then
				picked[bi] = true
				out[#out + 1] = verts[bi]
			end
			work += n
			if canYield and work > 60000 then
				work = 0
				task.wait()
			end
		end
		return out
	end

	local function meshKey(content)
		if content == nil then
			return nil
		end
		local sourceType = content.SourceType
		if sourceType == Enum.ContentSourceType.Uri then
			local uri = content.Uri
			if uri and uri ~= "" then
				return uri
			end
		elseif sourceType == Enum.ContentSourceType.Object then
			return content.Object
		end
		return nil
	end

	local function readMesh(entry)
		local em = AssetService:CreateEditableMeshAsync(entry.content, {FixedSize = true})
		if not em then
			error("no EditableMesh returned", 0)
		end
		local ok, err = pcall(function()
			local size, center = em:GetSize(), em:GetCenter()
			local sx, sy, sz = max(size.X, 1e-4), max(size.Y, 1e-4), max(size.Z, 1e-4)
			local vids = em:GetVertices()
			local index, verts = {}, tcreate(#vids)
			for i = 1, #vids do
				local p = em:GetPosition(vids[i])
				verts[i] = V3((p.X - center.X) / sx, (p.Y - center.Y) / sy, (p.Z - center.Z) / sz)
				index[vids[i]] = i
				if i % 4000 == 0 then
					task.wait()
				end
			end
			local fids = em:GetFaces()
			local tris, nt = tcreate(#fids * 3), 0
			for i = 1, #fids do
				local fv = em:GetFaceVertices(fids[i])
				local a, b, c = index[fv[1]], index[fv[2]], index[fv[3]]
				if a and b and c then
					tris[nt + 1], tris[nt + 2], tris[nt + 3] = a, b, c
					nt += 3
					local d = fv[4] and index[fv[4]]
					if d then
						tris[nt + 1], tris[nt + 2], tris[nt + 3] = a, c, d
						nt += 3
					end
				end
				if i % 4000 == 0 then
					task.wait()
				end
			end
			entry.verts, entry.tris = verts, tris
			entry.size, entry.center = V3(sx, sy, sz), center
			entry.hull = supportPoints(verts, true)
		end)
		pcall(em.Destroy, em)
		if not ok then
			error(err, 0)
		end
	end

	local function meshLoader()
		while alive do
			local entry = qpop(MeshData.queue)
			if not entry then
				break
			end
			entry.status = "loading"
			local ok = pcall(readMesh, entry)
			if ok then
				entry.status = "ready"
				stats.meshLoads += 1
			else
				entry.fails += 1
				if entry.fails >= 3 then
					entry.status = "dead"
				else
					entry.status = "failed"
					entry.retryAt = clock() + 8 * 4 ^ (entry.fails - 1)
				end
			end
			qpush(MeshData.ready, entry)
			task.wait()
		end
		MeshData.running = false
	end

	function MeshData.get(content)
		if not CONFIG.MeshShadows then
			return nil
		end
		local key = meshKey(content)
		if key == nil then
			return nil
		end
		local entry = MeshData.entries[key]
		if not entry then
			MeshData.nextId += 1
			entry = {id = MeshData.nextId, key = key, content = content, status = "new", fails = 0, retryAt = 0}
			MeshData.entries[key] = entry
		end
		if entry.status == "new" or (entry.status == "failed" and clock() >= entry.retryAt) then
			if MeshData.allowed then
				entry.status = "queued"
				qpush(MeshData.queue, entry)
				if not MeshData.running and alive then
					MeshData.running = true
					task.spawn(meshLoader)
				end
			else
				entry.status = "dead"
			end
		end
		return entry
	end

	-- True (and remembers the part) while a mesh is still loading.
	-- Remembers the part so it updates when the mesh arrives. Only the first load attempt makes
	-- the part wait (no shadow); while a failed load is retried it keeps its fallback shadow.
	function waitForMesh(entry, state)
		local s = entry.status
		if s == "queued" or s == "loading" or s == "new" or s == "failed" then
			entry.users = entry.users or setmetatable({}, {__mode = "k"})
			entry.users[state] = true
			return entry.fails == 0 and s ~= "failed"
		end
		return false
	end
end

----------------------------------------------------------------------------------------------------
-- Raycast sampling: when mesh data can't be read, rays find the part's real outline instead
----------------------------------------------------------------------------------------------------
local RaySample = {byKey = {}, byPart = setmetatable({}, {__mode = "k"}), budget = 0}
do
	local sampleParams = RaycastParams.new()
	sampleParams.FilterType = Enum.RaycastFilterType.Include
	sampleParams.IgnoreWater = true

	local function sampleShape(part)
		local cf, size = part.CFrame, part.Size
		sampleParams.FilterDescendantsInstances = {part}
		local pts = {}
		local G = 6
		for axis = 1, 3 do
			for sign = -1, 1, 2 do
				for i = 0, G - 1 do
					local s = -0.495 + 0.99 * i / (G - 1)
					for j = 0, G - 1 do
						local t = -0.495 + 0.99 * j / (G - 1)
						local o, d
						if axis == 1 then
							o = V3(sign * (size.X / 2 + 1), s * size.Y, t * size.Z)
							d = V3(-sign * (size.X + 2), 0, 0)
						elseif axis == 2 then
							o = V3(s * size.X, sign * (size.Y / 2 + 1), t * size.Z)
							d = V3(0, -sign * (size.Y + 2), 0)
						else
							o = V3(s * size.X, t * size.Y, sign * (size.Z / 2 + 1))
							d = V3(0, 0, -sign * (size.Z + 2))
						end
						local hit = Workspace:Raycast(cf * o, cf:VectorToWorldSpace(d), sampleParams)
						if hit then
							local lp = cf:PointToObjectSpace(hit.Position)
							pts[#pts + 1] = V3(lp.X / size.X, lp.Y / size.Y, lp.Z / size.Z)
						end
					end
				end
			end
		end
		if #pts < 4 then
			return nil
		end
		return supportPoints(pts, false)
	end

	-- Normalized outline points, or nil. The second result is true when it should be asked again.
	function RaySample.get(part, key)
		local cache = key and RaySample.byKey or RaySample.byPart
		local k = key or part
		local hit = cache[k]
		if hit ~= nil then
			return hit or nil, false
		end
		if not part.CanQuery or not part:IsDescendantOf(Workspace) then
			return nil, false
		end
		if RaySample.budget <= 0 then
			return nil, true
		end
		RaySample.budget -= 1
		local pts = sampleShape(part)
		cache[k] = pts or false
		return pts, false
	end
end

----------------------------------------------------------------------------------------------------
-- Which shape a part has
----------------------------------------------------------------------------------------------------
do
	local PART_CAPSULE = nil
	pcall(function()
		PART_CAPSULE = Enum.PartType.Capsule
	end)

	local function segmentsFor(lod)
		local list = CONFIG.CurveSegments
		return list[lod] or list[#list] or 12
	end

	local function fallbackMeshShape(state, size, offset)
		if state.character then
			if state.accessory then
				return Shapes.ellipsoid(size * 0.45, 12, offset)
			end
			return Shapes.box(size * 0.9, offset)
		end
		if CONFIG.MissingMeshFallback == "Box" then
			return Shapes.box(size, offset)
		end
		return nil
	end

	local function meshPartShape(state, part, size)
		local content = part.MeshContent
		-- avatar meshes almost never allow reading, so characters go straight to ray sampling
		local entry = not state.character and MeshData.get(content) or nil
		if entry then
			if entry.status == "ready" then
				return Shapes.fromMesh(entry, size, ZERO)
			elseif waitForMesh(entry, state) then
				return nil, true
			end
		end
		if CONFIG.RaySampleMeshes then
			local uri = content and content.Uri
			local key = (uri and uri ~= "") and (uri .. "|" .. tostring(part.CollisionFidelity)) or nil
			local pts, busy = RaySample.get(part, key)
			if pts then
				return Shapes.fromPoints(key or ("i" .. state.id), pts, size, ZERO, true)
			elseif busy then
				return nil, true
			end
		end
		return fallbackMeshShape(state, size, nil)
	end

	local function unionShape(state, part, size)
		if not CONFIG.UnionShadows then
			return nil
		end
		if CONFIG.RaySampleMeshes then
			local pts, busy = RaySample.get(part, nil)
			if pts then
				return Shapes.fromPoints("u" .. state.id, pts, size, ZERO, true)
			elseif busy then
				return nil, true
			end
		end
		return Shapes.box(size)
	end

	local function specialMeshShape(state, mesh, size, segs)
		local scale, offset = mesh.Scale, mesh.Offset
		if mesh:IsA("SpecialMesh") then
			local meshType = mesh.MeshType
			if meshType == Enum.MeshType.FileMesh then
				local entry = not state.character and MeshData.get(mesh.MeshContent) or nil
				if entry then
					if entry.status == "ready" then
						return Shapes.fromMesh(entry, entry.size * scale, entry.center * scale + offset)
					elseif waitForMesh(entry, state) then
						return nil, true
					end
				end
				return fallbackMeshShape(state, size * scale, offset)
			elseif meshType == Enum.MeshType.Sphere then
				return Shapes.ellipsoid(size * scale * 0.5, segs, offset)
			elseif meshType == Enum.MeshType.Cylinder then
				return Shapes.cylinderY(size.Y * scale.Y, min(size.X * scale.X, size.Z * scale.Z), segs, offset)
			elseif meshType == Enum.MeshType.Head then
				return Shapes.cylinderY(size.Y * scale.Y, min(size.X, size.Y, size.Z) * scale.X, segs, offset)
			elseif meshType == Enum.MeshType.Wedge then
				return Shapes.wedge(size * scale, offset)
			elseif meshType == Enum.MeshType.CornerWedge then
				return Shapes.cornerWedge(size * scale, offset)
			end
			return Shapes.box(size * scale, offset)
		elseif mesh:IsA("CylinderMesh") then
			return Shapes.cylinderY(size.Y * scale.Y, min(size.X * scale.X, size.Z * scale.Z), segs, offset)
		end
		return Shapes.box(size * scale, offset)
	end

	local function resolveShape(state, lod)
		local part = state.part
		local size = part.Size
		if part:IsA("MeshPart") then
			return meshPartShape(state, part, size)
		elseif part:IsA("PartOperation") then
			return unionShape(state, part, size)
		end
		local className = part.ClassName
		if className == "WedgePart" then
			return Shapes.wedge(size)
		elseif className == "CornerWedgePart" then
			return Shapes.cornerWedge(size)
		elseif part:IsA("Part") then
			local segs = segmentsFor(lod)
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh then
				return specialMeshShape(state, mesh, size, segs)
			end
			local shape = part.Shape
			if shape == Enum.PartType.Ball then
				return Shapes.ball(size, segs)
			elseif shape == Enum.PartType.Cylinder then
				return Shapes.cylinderX(size, segs)
			elseif shape == Enum.PartType.Wedge then
				return Shapes.wedge(size)
			elseif shape == Enum.PartType.CornerWedge then
				return Shapes.cornerWedge(size)
			elseif PART_CAPSULE and shape == PART_CAPSULE then
				return Shapes.capsule(size, segs)
			end
		end
		return Shapes.box(size)
	end

	-- Shape for a part at a level of detail (1 = near, 3 = far). Returns shape, pending.
	getShape = function(state, lod)
		local cache = state.shapes
		if not cache or state.shapesVersion ~= state.shapeVersion then
			cache = {}
			state.shapes = cache
			state.shapesVersion = state.shapeVersion
		end
		local s = cache[lod]
		if s ~= nil then
			return s or nil, false
		end
		local shape, pending = resolveShape(state, lod)
		if pending then
			return nil, true
		end
		cache[lod] = shape or false
		return shape, false
	end
end

----------------------------------------------------------------------------------------------------
-- Caster geometry in world space, and its outline as seen from the light
----------------------------------------------------------------------------------------------------
do
	-- The silhouette of an ellipsoid c + e1*x + e2*y + e3*z (|xyz| <= 1) seen along L.
	local function ellipsoidRing(c, e1, e2, e3, L, segs, pts, n)
		local s1, s2, s3 = e1:Dot(e1), e2:Dot(e2), e3:Dot(e3)
		if s1 < 1e-12 or s2 < 1e-12 or s3 < 1e-12 then
			return n
		end
		local d = V3(L:Dot(e1) / s1, L:Dot(e2) / s2, L:Dot(e3) / s3)
		local dm = d.Magnitude
		if dm < 1e-12 then
			return n
		end
		d /= dm
		local p = (abs(d.X) < 0.9 and XAXIS or YAXIS):Cross(d).Unit
		local q = d:Cross(p)
		for k = 0, segs - 1 do
			local t = 2 * pi * k / segs
			local ct, st = cos(t), sin(t)
			n += 1
			pts[n] = c + e1 * (ct * p.X + st * q.X) + e2 * (ct * p.Y + st * q.Y) + e3 * (ct * p.Z + st * q.Z)
		end
		return n
	end

	local function computeGeom(state, shape, lod, g)
		g = g or {pts = {}, lx = {}, ly = {}, lz = {}, hull = {}}
		local cf = state.part.CFrame
		local L, a, b = Light.L, Light.a, Light.b
		local pts = g.pts
		local n = 0
		local kind = shape.kind
		g.kind = kind
		g.state = state
		g.edges = nil
		g.tris = nil
		g.ellCount = 0
		if kind == "poly" then
			local verts = shape.verts
			for i = 1, #verts do
				pts[i] = cf * verts[i]
			end
			n = #verts
			g.edges = shape.edges
		elseif kind == "round" then
			local ells = g.ells or {}
			g.ells = ells
			local segs = shape.segs
			for i, e in ipairs(shape.ellipsoids) do
				local we = ells[i] or {}
				ells[i] = we
				we.c = cf * e.c
				we.e1 = cf:VectorToWorldSpace(e.e1)
				we.e2 = cf:VectorToWorldSpace(e.e2)
				we.e3 = cf:VectorToWorldSpace(e.e3)
				we.first = n + 1
				n = ellipsoidRing(we.c, we.e1, we.e2, we.e3, L, segs, pts, n)
				we.last = n
				g.ellCount = i
			end
			g.segs = segs
		else
			local points = shape.points
			for i = 1, #points do
				pts[i] = cf * points[i]
			end
			n = #points
			if shape.tris and lod == 1 then
				local src = shape.tris
				local tv = g.triStore or {}
				g.triStore = tv
				for i = 1, #src do
					tv[i] = cf * src[i]
				end
				for i = #tv, #src + 1, -1 do
					tv[i] = nil
				end
				g.tris = tv
			end
		end
		for i = #pts, n + 1, -1 do
			pts[i] = nil
		end
		g.n = n
		local lx, ly, lz = g.lx, g.ly, g.lz
		local ax, ay, az = a.X, a.Y, a.Z
		local bx, by, bz = b.X, b.Y, b.Z
		local Lx, Ly, Lz = L.X, L.Y, L.Z
		local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
		for i = 1, n do
			local p = pts[i]
			local px, py, pz = p.X, p.Y, p.Z
			local x = px * ax + py * ay + pz * az
			local y = px * bx + py * by + pz * bz
			local z = px * Lx + py * Ly + pz * Lz
			lx[i], ly[i], lz[i] = x, y, z
			if x < minX then
				minX = x
			end
			if x > maxX then
				maxX = x
			end
			if y < minY then
				minY = y
			end
			if y > maxY then
				maxY = y
			end
			if z < minZ then
				minZ = z
			end
			if z > maxZ then
				maxZ = z
			end
		end
		if kind == "round" then
			-- the silhouette ring sits in the middle of the body: extend depth to its real front/back
			for i = 1, g.ellCount do
				local we = g.ells[i]
				local cz = we.c:Dot(L)
				local ext = sqrt(L:Dot(we.e1) ^ 2 + L:Dot(we.e2) ^ 2 + L:Dot(we.e3) ^ 2)
				if cz - ext < minZ then
					minZ = cz - ext
				end
				if cz + ext > maxZ then
					maxZ = cz + ext
				end
			end
		end
		g.minX, g.maxX, g.minY, g.maxY, g.minZ, g.maxZ = minX, maxX, minY, maxY, minZ, maxZ
		g.hullCount = n >= 3 and convexHull(lx, ly, n, g.hull) or 0
		g.tint = state.tint
		return g
	end

	function getGeom(state, shape, lod)
		local g = state.geom
		if g and g.shape == shape and g.lod == lod and g.lightVersion == Light.version then
			if state.dynamic then
				if g.frame == frameId then
					return g
				end
			elseif g.cfVersion == state.cfVersion then
				return g
			end
		end
		g = computeGeom(state, shape, lod, g)
		g.shape, g.lod, g.lightVersion, g.frame, g.cfVersion = shape, lod, Light.version, frameId, state.cfVersion
		state.geom = g
		return g
	end
end

----------------------------------------------------------------------------------------------------
-- Receiving faces in world space
----------------------------------------------------------------------------------------------------
do
	local function buildWorldFace(lf, cf, wf)
		local o = cf * lf.o
		local nrm = cf:VectorToWorldSpace(lf.n)
		local u = cf:VectorToWorldSpace(lf.u)
		local v = cf:VectorToWorldSpace(lf.v)
		local L, a, b = Light.L, Light.a, Light.b
		local s = -nrm:Dot(L)
		local lu, lv = L:Dot(u), L:Dot(v)
		wf.lf, wf.o, wf.n, wf.u, wf.v, wf.s, wf.lu, wf.lv = lf, o, nrm, u, v, s, lu, lv
		if s > 1e-6 then
			wf.ku, wf.kv = lu / s, lv / s
		else
			wf.ku, wf.kv = 0, 0
		end
		local oa, ob, oz = o:Dot(a), o:Dot(b), o:Dot(L)
		wf.zo = oz
		local ua, ub, va, vb = u:Dot(a), u:Dot(b), v:Dot(a), v:Dot(b)
		local xs, ys = lf.xs, lf.ys
		local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
		for i = 1, lf.count do
			local x, y = xs[i], ys[i]
			local px = oa + ua * x + va * y
			local py = ob + ub * x + vb * y
			local pz = oz + lu * x + lv * y
			if px < minX then
				minX = px
			end
			if px > maxX then
				maxX = px
			end
			if py < minY then
				minY = py
			end
			if py > maxY then
				maxY = py
			end
			if pz < minZ then
				minZ = pz
			end
			if pz > maxZ then
				maxZ = pz
			end
		end
		wf.minX, wf.maxX, wf.minY, wf.maxY, wf.minZ, wf.maxZ = minX, maxX, minY, maxY, minZ, maxZ
		return wf
	end

	function getWorldFaces(state, shape)
		if state.wfFrame == frameId and state.wfShape == shape and state.wfLight == Light.version then
			return state.wf
		end
		local list = state.wf or {}
		local faces = shape.faces
		local cf = state.part.CFrame
		for i = 1, #faces do
			list[i] = buildWorldFace(faces[i], cf, list[i] or {})
		end
		for i = #list, #faces + 1, -1 do
			list[i] = nil
		end
		state.wf, state.wfFrame, state.wfShape, state.wfLight = list, frameId, shape, Light.version
		return list
	end
end

----------------------------------------------------------------------------------------------------
-- Output: the shadow polygons produced by one job (world space)
----------------------------------------------------------------------------------------------------
local Out = {pts = {}, sizes = {}, tints = {}, np = 0, nPoly = 0}

do
	function resetOut()
		Out.np = 0
		Out.nPoly = 0
	end

	-- A polygon in a face's 2D coordinates, lifted slightly off the face.
	function emitFace(wf, xs, ys, n, tint)
		local o = wf.o + wf.n * CONFIG.SurfaceOffset
		local u, v = wf.u, wf.v
		local pts = Out.pts
		local np = Out.np
		for i = 1, n do
			np += 1
			pts[np] = o + u * xs[i] + v * ys[i]
		end
		Out.np = np
		local k = Out.nPoly + 1
		Out.nPoly = k
		Out.sizes[k] = n
		Out.tints[k] = tint or false
	end

	-- A world-space polygon, wound so its front faces `normal`.
	function emitWorld(poly, n, normal, tint)
		local nx, ny, nz = 0, 0, 0
		for i = 1, n do
			local p, q = poly[i], poly[i % n + 1]
			nx += (p.Y - q.Y) * (p.Z + q.Z)
			ny += (p.Z - q.Z) * (p.X + q.X)
			nz += (p.X - q.X) * (p.Y + q.Y)
		end
		local flip = nx * normal.X + ny * normal.Y + nz * normal.Z < 0
		local pts = Out.pts
		local np = Out.np
		for i = 1, n do
			np += 1
			pts[np] = flip and poly[n + 1 - i] or poly[i]
		end
		Out.np = np
		local k = Out.nPoly + 1
		Out.nPoly = k
		Out.sizes[k] = n
		Out.tints[k] = tint or false
	end
end

----------------------------------------------------------------------------------------------------
-- Projection: push a caster along the light onto one face, then cut it to fit that face
----------------------------------------------------------------------------------------------------
do
	local PX, PY = {}, {}    -- projected outline
	local SX, SY = {}, {}    -- loose points when the caster cuts through the face plane
	local SH = {}            -- hull indices
	local DD = {}            -- signed distance of each caster point to the face plane
	local LX, LY = {}, {}    -- output of the shadow-length clip
	local RING = {}          -- where a face plane slices an ellipsoid
	local TV, TDV = {}, {}   -- triangle being clipped
	local TRI_P, TRI_D = {}, {}

	function lightOverlap(g, wf)
		return g.maxX >= wf.minX and g.minX <= wf.maxX and g.maxY >= wf.minY and g.minY <= wf.maxY
			and wf.maxZ > g.minZ and wf.minZ < g.maxZ + CONFIG.MaxShadowLength
	end

	local function finishPolygon(count, wf, g, tint)
		local lf = wf.lf
		local n, xs, ys = clipByLines(PX, PY, count, lf.lines, lf.nLines)
		if n < 3 then
			return
		end
		local zLimit = g.maxZ + CONFIG.MaxShadowLength
		if wf.maxZ > zLimit then
			n = clipLine(xs, ys, n, -wf.lu, -wf.lv, zLimit - wf.zo, LX, LY)
			if n < 3 then
				return
			end
			xs, ys = LX, LY
		end
		if polyArea(xs, ys, n) < MIN_AREA then
			return
		end
		emitFace(wf, xs, ys, n, tint)
	end

	-- Points where the plane through `o` with normal `nrm` cuts an ellipsoid.
	local function planeRing(we, o, nrm, segs, out)
		local e1, e2, e3 = we.e1, we.e2, we.e3
		local m = V3(nrm:Dot(e1), nrm:Dot(e2), nrm:Dot(e3))
		local mm = m.Magnitude
		if mm < 1e-9 then
			return 0
		end
		local delta = nrm:Dot(o - we.c) / mm
		if delta <= -1 or delta >= 1 then
			return 0
		end
		local mh = m / mm
		local rho = sqrt(1 - delta * delta)
		local p = (abs(mh.X) < 0.9 and XAXIS or YAXIS):Cross(mh).Unit
		local q = mh:Cross(p)
		local c0 = mh * delta
		for k = 1, segs do
			local t = 2 * pi * k / segs
			local w = c0 + (p * cos(t) + q * sin(t)) * rho
			out[k] = we.c + e1 * w.X + e2 * w.Y + e3 * w.Z
		end
		return segs
	end

	local function projectCaster(g, wf, tint)
		local o, nrm, u, v = wf.o, wf.n, wf.u, wf.v
		local ox, oy, oz = o.X, o.Y, o.Z
		local nx, ny, nz = nrm.X, nrm.Y, nrm.Z
		local ux, uy, uz = u.X, u.Y, u.Z
		local vx, vy, vz = v.X, v.Y, v.Z
		local ku, kv = wf.ku, wf.kv
		local pts, n = g.pts, g.n
		local minD, maxD = huge, -huge
		for i = 1, n do
			local p = pts[i]
			local d = (p.X - ox) * nx + (p.Y - oy) * ny + (p.Z - oz) * nz
			DD[i] = d
			if d < minD then
				minD = d
			end
			if d > maxD then
				maxD = d
			end
		end
		local kind = g.kind
		if kind == "round" then
			-- the ring is only the middle of a round body: use each ellipsoid's true extent
			for i = 1, g.ellCount do
				local we = g.ells[i]
				local c = we.c
				local dc = (c.X - ox) * nx + (c.Y - oy) * ny + (c.Z - oz) * nz
				local ext = sqrt(nrm:Dot(we.e1) ^ 2 + nrm:Dot(we.e2) ^ 2 + nrm:Dot(we.e3) ^ 2)
				if dc - ext < minD then
					minD = dc - ext
				end
				if dc + ext > maxD then
					maxD = dc + ext
				end
			end
		end
		if maxD <= CONTACT then
			return
		end
		local count
		if minD >= -CONTACT then
			-- the whole caster is in front of the face: project its outline (stays convex)
			local hull, hc = g.hull, g.hullCount
			if hc < 3 then
				return
			end
			for k = 1, hc do
				local i = hull[k]
				local p = pts[i]
				local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
				local d = DD[i]
				PX[k] = rx * ux + ry * uy + rz * uz + d * ku
				PY[k] = rx * vx + ry * vy + rz * vz + d * kv
			end
			count = hc
			if polyArea(PX, PY, count) < 0 then
				reversePoly(PX, PY, count)
			end
		else
			-- the caster cuts through the face plane: only the part in front of it casts
			local m = 0
			for i = 1, n do
				local d = DD[i]
				if d >= -CONTACT then
					local p = pts[i]
					local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
					if d < 0 then
						d = 0
					end
					m += 1
					SX[m] = rx * ux + ry * uy + rz * uz + d * ku
					SY[m] = rx * vx + ry * vy + rz * vz + d * kv
				end
			end
			if kind == "poly" then
				local edges = g.edges
				for e = 1, #edges, 2 do
					local i, j = edges[e], edges[e + 1]
					local di, dj = DD[i], DD[j]
					if (di > CONTACT and dj < -CONTACT) or (dj > CONTACT and di < -CONTACT) then
						local p = pts[i]:Lerp(pts[j], di / (di - dj))
						local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
						m += 1
						SX[m] = rx * ux + ry * uy + rz * uz
						SY[m] = rx * vx + ry * vy + rz * vz
					end
				end
			elseif kind == "round" then
				for e = 1, g.ellCount do
					local we = g.ells[e]
					local first, last = we.first, we.last
					for i = first, last do
						local j = i == last and first or i + 1
						local di, dj = DD[i], DD[j]
						if (di > CONTACT and dj < -CONTACT) or (dj > CONTACT and di < -CONTACT) then
							local p = pts[i]:Lerp(pts[j], di / (di - dj))
							local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
							m += 1
							SX[m] = rx * ux + ry * uy + rz * uz
							SY[m] = rx * vx + ry * vy + rz * vz
						end
					end
					local rc = planeRing(we, o, nrm, g.segs, RING)
					for k = 1, rc do
						local p = RING[k]
						local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
						m += 1
						SX[m] = rx * ux + ry * uy + rz * uz
						SY[m] = rx * vx + ry * vy + rz * vz
					end
				end
			end
			if m < 3 then
				return
			end
			local hc = convexHull(SX, SY, m, SH)
			if hc < 3 then
				return
			end
			for k = 1, hc do
				local i = SH[k]
				PX[k] = SX[i]
				PY[k] = SY[i]
			end
			count = hc
		end
		finishPolygon(count, wf, g, tint)
	end

	-- Exact mesh shadows: every lit triangle is projected on its own. Overlaps don't matter because
	-- the Highlight merges everything.
	local function projectTriangles(g, wf, tint)
		local o, nrm, u, v = wf.o, wf.n, wf.u, wf.v
		local ox, oy, oz = o.X, o.Y, o.Z
		local nx, ny, nz = nrm.X, nrm.Y, nrm.Z
		local ux, uy, uz = u.X, u.Y, u.Z
		local vx, vy, vz = v.X, v.Y, v.Z
		local ku, kv = wf.ku, wf.kv
		local dir = Light.dir
		local tv = g.tris
		for t = 1, #tv - 2, 3 do
			local A, B, C = tv[t], tv[t + 1], tv[t + 2]
			if (B - A):Cross(C - A):Dot(dir) > 1e-9 then
				local da = (A.X - ox) * nx + (A.Y - oy) * ny + (A.Z - oz) * nz
				local db = (B.X - ox) * nx + (B.Y - oy) * ny + (B.Z - oz) * nz
				local dc = (C.X - ox) * nx + (C.Y - oy) * ny + (C.Z - oz) * nz
				if da > CONTACT or db > CONTACT or dc > CONTACT then
					local count = 0
					if da >= -CONTACT and db >= -CONTACT and dc >= -CONTACT then
						TRI_P[1], TRI_P[2], TRI_P[3] = A, B, C
						TRI_D[1], TRI_D[2], TRI_D[3] = max(da, 0), max(db, 0), max(dc, 0)
						count = 3
					else
						TV[1], TV[2], TV[3] = A, B, C
						TDV[1], TDV[2], TDV[3] = da, db, dc
						local pv, pd = C, dc
						for i = 1, 3 do
							local cv, cd = TV[i], TDV[i]
							if cd >= 0 then
								if pd < 0 then
									count += 1
									TRI_P[count] = pv:Lerp(cv, pd / (pd - cd))
									TRI_D[count] = 0
								end
								count += 1
								TRI_P[count] = cv
								TRI_D[count] = cd
							elseif pd >= 0 then
								count += 1
								TRI_P[count] = pv:Lerp(cv, pd / (pd - cd))
								TRI_D[count] = 0
							end
							pv, pd = cv, cd
						end
					end
					if count >= 3 then
						for k = 1, count do
							local p = TRI_P[k]
							local d = TRI_D[k]
							local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
							PX[k] = rx * ux + ry * uy + rz * uz + d * ku
							PY[k] = rx * vx + ry * vy + rz * vz + d * kv
						end
						local area = polyArea(PX, PY, count)
						if area < 0 then
							reversePoly(PX, PY, count)
							area = -area
						end
						if area > 1e-6 then
							finishPolygon(count, wf, g, tint)
						end
					end
				end
			end
		end
	end

	function castOnFace(g, wf)
		if g.tris then
			projectTriangles(g, wf, g.tint)
		else
			projectCaster(g, wf, g.tint)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Terrain: shadows are draped over the terrain surface using a small grid of raycasts
----------------------------------------------------------------------------------------------------
do
	local terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.IgnoreWater = true
	terrainParams.FilterDescendantsInstances = {Workspace.Terrain}

	local TERRAIN_STEP = {1.25, 2.5, 5}
	local gDepth, gX, gY = {}, {}, {}
	local HX, HY = {}, {}
	local TL = {}
	local DRAPE = {}

	local function drapeTriangle(ka, kb, kc, hc, tint)
		local da, db, dc = gDepth[ka], gDepth[kb], gDepth[kc]
		if not (da and db and dc) then
			return
		end
		local L, a, b = Light.L, Light.a, Light.b
		local xa, ya, xb, yb, xc, yc = gX[ka], gY[ka], gX[kb], gY[kb], gX[kc], gY[kc]
		local Pa = a * xa + b * ya + L * da
		local Pb = a * xb + b * yb + L * db
		local Pc = a * xc + b * yc + L * dc
		local nrm = (Pb - Pa):Cross(Pc - Pa)
		local nm = nrm.Magnitude
		if nm < 1e-9 then
			return
		end
		nrm /= nm
		local facing = -nrm:Dot(L)
		if facing < 0 then
			nrm = -nrm
			facing = -facing
		end
		if facing < 0.12 then
			return -- a cliff or step between samples, not a surface
		end
		setLine(TL, 0, xa, ya, xb, yb)
		setLine(TL, 1, xb, yb, xc, yc)
		setLine(TL, 2, xc, yc, xa, ya)
		local n, xs, ys = clipByLines(HX, HY, hc, TL, 3)
		if n < 3 then
			return
		end
		local det = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
		if abs(det) < 1e-12 then
			return
		end
		local off = nrm * TERRAIN_OFFSET
		for k = 1, n do
			local x, y = xs[k], ys[k]
			local wa = ((yb - yc) * (x - xc) + (xc - xb) * (y - yc)) / det
			local wb = ((yc - ya) * (x - xc) + (xa - xc) * (y - yc)) / det
			local wc = 1 - wa - wb
			DRAPE[k] = a * x + b * y + L * (wa * da + wb * db + wc * dc) + off
		end
		emitWorld(DRAPE, n, nrm, tint)
	end

	-- geoms: caster geometries sharing one ray grid (one part, or a whole character).
	function drapeOnTerrain(geoms, ng, minX, maxX, minY, maxY, minZ, maxZ, lod)
		local w, h = maxX - minX, maxY - minY
		if w <= 0 or h <= 0 then
			return
		end
		local step = max(TERRAIN_STEP[lod] or 5, w / 14, h / 14)
		local nx = max(1, ceil(w / step - 1e-6))
		local ny = max(1, ceil(h / step - 1e-6))
		local sx, sy = w / nx, h / ny
		local L, a, b = Light.L, Light.a, Light.b
		local z0 = minZ - 0.5
		local ray = L * ((maxZ - minZ) + CONFIG.MaxShadowLength + 1)
		local cols = nx + 1
		local any = false
		for j = 0, ny do
			local y = minY + j * sy
			for i = 0, nx do
				local x = minX + i * sx
				local k = j * cols + i + 1
				gX[k], gY[k] = x, y
				local hit = Workspace:Raycast(a * x + b * y + L * z0, ray, terrainParams)
				if hit then
					gDepth[k] = hit.Position:Dot(L)
					any = true
				else
					gDepth[k] = false
				end
			end
		end
		if not any then
			return
		end
		for gi = 1, ng do
			local g = geoms[gi]
			local hc = g.hullCount
			if hc >= 3 then
				local hull, glx, gly = g.hull, g.lx, g.ly
				for k = 1, hc do
					local idx = hull[k]
					HX[k], HY[k] = glx[idx], gly[idx]
				end
				for j = 0, ny - 1 do
					for i = 0, nx - 1 do
						local k00 = j * cols + i + 1
						local k10, k01, k11 = k00 + 1, k00 + cols, k00 + cols + 1
						if gX[k10] >= g.minX and gX[k00] <= g.maxX and gY[k01] >= g.minY and gY[k00] <= g.maxY then
							drapeTriangle(k00, k10, k11, hc, g.tint)
							drapeTriangle(k00, k11, k01, hc, g.tint)
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Rendering: Highlight-merged layers, EditableMesh pages, wedge-part fallback
----------------------------------------------------------------------------------------------------
local Render = {meshOk = false, batch = false, layers = {}, lastSweep = 0}
do
	local PAGE_CELL = 256      -- pages cover a 256-stud grid cell...
	local PAGE_HALF = 256      -- ...plus up to 128 studs of overhang, inside fixed +-256 bounds
	local PAGE_TRIS = 18000    -- EditableMesh limits are 20,000 triangles / 60,000 vertices
	local PAGE_VERTS = 50000
	local BATCH_TRIS = 3000
	local PAGE_OPTIONS = {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise}
	local pageSets = {}
	local dirtyPages = {}
	local allPages = {}

	local function styleShadowPart(p, layer)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Massless = true
		p.Locked = true
		p.Material = layer.material
		p.Color = layer.color
		p.Transparency = layer.transparency
	end

	local function makeLayer(name, containerName, highlight, transparency, material, color)
		local model = Instance.new("Model")
		model.Name = containerName
		if highlight then
			-- A Humanoid makes the Highlight draw on these 99.9% transparent parts.
			local hum = Instance.new("Humanoid")
			hum.Name = "HighlightHost"
			pcall(function()
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				hum.NameDisplayDistance = 0
				hum.HealthDisplayDistance = 0
				hum.RequiresNeck = false
				hum.BreakJointsOnDeath = false
				hum.EvaluateStateMachine = false
			end)
			hum.Parent = model
			local hl = Instance.new("Highlight")
			hl.Name = "StencilFill"
			hl.FillColor = CONFIG.ShadowColor
			hl.FillTransparency = CONFIG.ShadowTransparency
			hl.OutlineTransparency = 1
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.Adornee = model
			hl.Parent = model
		end
		local layer = {name = name, model = model, transparency = transparency, material = material, color = color, pool = {}}
		Render.layers[name] = layer
		return layer
	end

	-- Two specks at opposite corners pin the mesh bounds, so the MeshPart never rescales the mesh.
	local function addAnchors(em)
		local h, e = PAGE_HALF, 0.002
		local a1 = em:AddVertex(V3(-h, -h, -h))
		local a2 = em:AddVertex(V3(-h + e, -h, -h))
		local a3 = em:AddVertex(V3(-h, -h + e, -h))
		em:AddTriangle(a1, a2, a3)
		local b1 = em:AddVertex(V3(h, h, h))
		local b2 = em:AddVertex(V3(h - e, h, h))
		local b3 = em:AddVertex(V3(h, h - e, h))
		em:AddTriangle(b1, b2, b3)
	end

	local function createPage(layer, setKey, key, center)
		local okMesh, em = pcall(function()
			return AssetService:CreateEditableMesh()
		end)
		if not okMesh or not em then
			return nil -- memory budget used up
		end
		local ok, part = pcall(function()
			addAnchors(em)
			return AssetService:CreateMeshPartAsync(Content.fromObject(em), PAGE_OPTIONS)
		end)
		if not ok or not part then
			pcall(em.Destroy, em)
			warnOnce("page", "Couldn't create a shadow mesh (" .. tostring(part) .. "), using parts instead.")
			return nil
		end
		part.Name = "ShadowPage"
		styleShadowPart(part, layer)
		pcall(function()
			part.DoubleSided = true
		end)
		part.Size = V3(PAGE_HALF * 2, PAGE_HALF * 2, PAGE_HALF * 2)
		part.CFrame = CFrame.new(center)
		part.Parent = layer.model
		local page = {mesh = em, part = part, center = center, tris = 2, verts = 6, garbage = 0,
			setKey = setKey, key = key, alive = true, emptySince = nil}
		local set = pageSets[setKey]
		if not set then
			set = {}
			pageSets[setKey] = set
		end
		local list = set[key]
		if not list then
			list = {}
			set[key] = list
		end
		list[#list + 1] = page
		allPages[page] = true
		stats.pages += 1
		return page
	end

	local function destroyPage(pg)
		pg.alive = false
		allPages[pg] = nil
		dirtyPages[pg] = nil
		local set = pageSets[pg.setKey]
		local list = set and set[pg.key]
		if list then
			for i = #list, 1, -1 do
				if list[i] == pg then
					tremove(list, i)
				end
			end
			if #list == 0 then
				set[pg.key] = nil
			end
		end
		pcall(pg.part.Destroy, pg.part)
		pcall(pg.mesh.Destroy, pg.mesh)
		stats.pages -= 1
	end

	local function flushPage(pg)
		if pg.garbage > 0 and pg.alive then
			pcall(pg.mesh.RemoveUnused, pg.mesh)
			pg.garbage = 0
		end
	end

	local function pageFor(layer, pool, ix, iy, iz, center, tris, verts)
		local setKey = layer.name .. pool
		local key = cellKey(ix, iy, iz)
		local set = pageSets[setKey]
		local list = set and set[key]
		if list then
			for i = 1, #list do
				local pg = list[i]
				if pg.alive and pg.tris + tris <= PAGE_TRIS then
					if pg.verts + pg.garbage + verts > PAGE_VERTS then
						flushPage(pg)
					end
					if pg.verts + verts <= PAGE_VERTS then
						return pg
					end
				end
			end
		end
		return createPage(layer, setKey, key, center)
	end

	local function pageAdd(pg, pts, sizes, nPoly, np)
		local mesh, center = pg.mesh, pg.center
		local positions = tcreate(np)
		for i = 1, np do
			positions[i] = pts[i] - center
		end
		local faces = {}
		local base = 0
		for p = 1, nPoly do
			local k = sizes[p]
			for j = 2, k - 1 do
				faces[#faces + 1] = {base + 1, base + j, base + j + 1}
			end
			base += k
		end
		local fids
		if Render.batch then
			local vids = mesh:BatchAdd(Enum.MeshAttribute.Vertex, positions)
			for i = 1, #faces do
				local f = faces[i]
				f[1], f[2], f[3] = vids[f[1]], vids[f[2]], vids[f[3]]
			end
			fids = mesh:BatchAdd(Enum.MeshAttribute.Face, faces)
		else
			local vids = tcreate(np)
			for i = 1, np do
				vids[i] = mesh:AddVertex(positions[i])
			end
			fids = tcreate(#faces)
			for i = 1, #faces do
				local f = faces[i]
				fids[i] = mesh:AddTriangle(vids[f[1]], vids[f[2]], vids[f[3]])
			end
		end
		pg.tris += #fids
		pg.verts += np
		pg.emptySince = nil
		return fids
	end

	local function releaseMesh(rec)
		local handles = rec.mesh
		for i = #handles, 1, -1 do
			local h = handles[i]
			handles[i] = nil
			local pg = h.page
			if pg.alive then
				local mesh = pg.mesh
				local ok = Render.batch and pcall(mesh.BatchRemove, mesh, h.fids)
				if not ok then
					for _, fid in ipairs(h.fids) do
						pcall(mesh.RemoveFace, mesh, fid)
					end
				end
				pg.tris -= #h.fids
				pg.verts -= h.verts
				pg.garbage += h.verts
				dirtyPages[pg] = true
			end
		end
	end

	local function acquireWedge(layer)
		local pool = layer.pool
		local w = pool[#pool]
		if w then
			pool[#pool] = nil
		else
			w = Instance.new("WedgePart")
			w.Name = "ShadowTri"
			styleShadowPart(w, layer)
			stats.wedges += 1
		end
		w.Parent = layer.model
		return w
	end

	local function releaseWedge(layer, w)
		local pool = layer.pool
		if #pool < 4000 then
			w.Parent = nil
			pool[#pool + 1] = w
		else
			w:Destroy()
			stats.wedges -= 1
		end
	end

	-- Any triangle = two right-angled wedges.
	local function placeTriangle(w1, w2, a, b, c)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local r = ac:Cross(ab)
		local rm, bm = r.Magnitude, bc.Magnitude
		if rm < 1e-6 or bm < 1e-6 then
			return false
		end
		local right = r / rm
		local back = bc / bm
		local up = back:Cross(right)
		local height = abs(ab:Dot(up))
		w1.Size = V3(WEDGE_THICKNESS, height, abs(ab:Dot(back)))
		w1.CFrame = CFrame.fromMatrix((a + b) * 0.5, right, up, back)
		w2.Size = V3(WEDGE_THICKNESS, height, abs(ac:Dot(back)))
		w2.CFrame = CFrame.fromMatrix((a + c) * 0.5, -right, up, -back)
		return true
	end

	-- tris: flat list of triangle corners; colors: one Color3 per triangle (tinted layer) or nil.
	local function commitWedges(rec, layer, tris, colors)
		local parts = rec.parts
		if not parts then
			if not tris then
				return
			end
			parts = {}
			rec.parts = parts
		end
		local list = parts[layer.name]
		if not list then
			if not tris then
				return
			end
			list = {}
			parts[layer.name] = list
		end
		local used = 0
		if tris then
			for t = 1, #tris - 2, 3 do
				local w1 = list[used + 1]
				if not w1 then
					w1 = acquireWedge(layer)
					list[used + 1] = w1
				end
				local w2 = list[used + 2]
				if not w2 then
					w2 = acquireWedge(layer)
					list[used + 2] = w2
				end
				if placeTriangle(w1, w2, tris[t], tris[t + 1], tris[t + 2]) then
					if colors then
						local c = colors[(t + 2) / 3]
						w1.Color = c
						w2.Color = c
					end
					used += 2
				end
			end
		end
		for i = #list, used + 1, -1 do
			releaseWedge(layer, list[i])
			list[i] = nil
		end
	end

	local function fan(pts, s, k, tris, colors, color)
		for j = 1, k - 2 do
			local n = #tris
			tris[n + 1] = pts[s]
			tris[n + 2] = pts[s + j]
			tris[n + 3] = pts[s + j + 1]
			if colors then
				colors[#colors + 1] = color
			end
		end
	end

	-- Binning: each mesh page covers one grid cell; big polygons are cut along cell borders.
	local cellBatches = {}
	local cellOrder = {}
	local commitRec, commitPool, commitFallback = nil, nil, nil
	local CA, CB = {}, {}

	local function flushBatch(batch)
		if batch.n == 0 then
			return
		end
		local main = Render.layers.main
		local pg = Render.meshOk and pageFor(main, commitPool, batch.ix, batch.iy, batch.iz, batch.center, batch.tris, batch.np)
		local done = false
		if pg then
			local ok, fids = pcall(pageAdd, pg, batch.pts, batch.sizes, batch.n, batch.np)
			if ok then
				local handles = commitRec.mesh
				handles[#handles + 1] = {page = pg, fids = fids, verts = batch.np}
				done = true
			else
				-- something is badly wrong with EditableMesh here: switch to parts for good
				warnOnce("pageAdd", "EditableMesh write failed (" .. tostring(fids) .. "), switching to parts.")
				Render.meshOk = false
				destroyPage(pg)
				rebuildRequested = true
			end
		end
		if not done then
			local s = 1
			for p = 1, batch.n do
				local k = batch.sizes[p]
				fan(batch.pts, s, k, commitFallback)
				s += k
			end
		end
		batch.n, batch.np, batch.tris = 0, 0, 0
	end

	local function addToCell(ix, iy, iz, center, pts, s, k)
		local key = cellKey(ix, iy, iz)
		local batch = cellBatches[key]
		if not batch then
			batch = {ix = ix, iy = iy, iz = iz, center = center, pts = {}, sizes = {}, n = 0, np = 0, tris = 0, listed = false}
			cellBatches[key] = batch
		end
		if not batch.listed then
			batch.listed = true
			cellOrder[#cellOrder + 1] = batch
		end
		if batch.tris + k - 2 > BATCH_TRIS then
			flushBatch(batch)
		end
		local bp = batch.pts
		local np = batch.np
		for i = 0, k - 1 do
			bp[np + i + 1] = pts[s + i]
		end
		batch.np = np + k
		batch.n += 1
		batch.sizes[batch.n] = k
		batch.tris += k - 2
	end

	local function clipAxis(src, n, axis, bound, keepBelow, dst)
		if n == 0 then
			return 0
		end
		local m = 0
		local prev = src[n]
		local pv = axis == 1 and prev.X or (axis == 2 and prev.Y or prev.Z)
		local pd = keepBelow and (bound - pv) or (pv - bound)
		for i = 1, n do
			local cur = src[i]
			local cv = axis == 1 and cur.X or (axis == 2 and cur.Y or cur.Z)
			local cd = keepBelow and (bound - cv) or (cv - bound)
			if cd >= 0 then
				if pd < 0 then
					m += 1
					dst[m] = prev:Lerp(cur, pd / (pd - cd))
				end
				m += 1
				dst[m] = cur
			elseif pd >= 0 then
				m += 1
				dst[m] = prev:Lerp(cur, pd / (pd - cd))
			end
			prev, pd = cur, cd
		end
		return m
	end

	local function binPolygon(pts, s, k)
		local p0 = pts[s]
		local minV, maxV, sum = p0, p0, ZERO
		for i = s, s + k - 1 do
			local p = pts[i]
			minV = minV:Min(p)
			maxV = maxV:Max(p)
			sum += p
		end
		local c = sum / k
		local ix, iy, iz = floor(c.X / PAGE_CELL), floor(c.Y / PAGE_CELL), floor(c.Z / PAGE_CELL)
		local center = V3((ix + 0.5) * PAGE_CELL, (iy + 0.5) * PAGE_CELL, (iz + 0.5) * PAGE_CELL)
		local lim = PAGE_HALF - 1
		local lo, hi = minV - center, maxV - center
		if lo.X > -lim and lo.Y > -lim and lo.Z > -lim and hi.X < lim and hi.Y < lim and hi.Z < lim then
			addToCell(ix, iy, iz, center, pts, s, k)
			return
		end
		-- too big for one page: cut it along the cell grid
		for cx = floor(minV.X / PAGE_CELL), floor(maxV.X / PAGE_CELL) do
			for cy = floor(minV.Y / PAGE_CELL), floor(maxV.Y / PAGE_CELL) do
				for cz = floor(minV.Z / PAGE_CELL), floor(maxV.Z / PAGE_CELL) do
					for i = 1, k do
						CA[i] = pts[s + i - 1]
					end
					local m = clipAxis(CA, k, 1, cx * PAGE_CELL, false, CB)
					m = clipAxis(CB, m, 1, (cx + 1) * PAGE_CELL, true, CA)
					m = clipAxis(CA, m, 2, cy * PAGE_CELL, false, CB)
					m = clipAxis(CB, m, 2, (cy + 1) * PAGE_CELL, true, CA)
					m = clipAxis(CA, m, 3, cz * PAGE_CELL, false, CB)
					m = clipAxis(CB, m, 3, (cz + 1) * PAGE_CELL, true, CA)
					if m >= 3 then
						local cc = V3((cx + 0.5) * PAGE_CELL, (cy + 0.5) * PAGE_CELL, (cz + 0.5) * PAGE_CELL)
						addToCell(cx, cy, cz, cc, CA, 1, m)
					end
				end
			end
		end
	end

	-- Replaces everything a record drew with the polygons in `out`.
	function Render.commit(rec, out, pool)
		releaseMesh(rec)
		local nPoly = out.nPoly
		local pts, sizes, tints = out.pts, out.sizes, out.tints
		local wedgeTris, tintTris, tintColors = nil, nil, nil
		commitRec, commitPool, commitFallback = rec, pool, {}
		local s = 1
		local useMesh = Render.meshOk
		for p = 1, nPoly do
			local k = sizes[p]
			local tint = tints[p]
			if tint then
				tintTris = tintTris or {}
				tintColors = tintColors or {}
				fan(pts, s, k, tintTris, tintColors, tint)
			elseif useMesh then
				binPolygon(pts, s, k)
			else
				wedgeTris = wedgeTris or {}
				fan(pts, s, k, wedgeTris)
			end
			s += k
		end
		if useMesh then
			for i = 1, #cellOrder do
				local batch = cellOrder[i]
				flushBatch(batch)
				batch.listed = false
				cellOrder[i] = nil
			end
			if #commitFallback > 0 then
				wedgeTris = commitFallback
			end
		end
		commitWedges(rec, Render.layers.main, wedgeTris, nil)
		commitWedges(rec, Render.layers.tint, tintTris, tintColors)
		commitRec, commitFallback = nil, nil
	end

	function Render.clear(rec)
		releaseMesh(rec)
		local parts = rec.parts
		if parts then
			for name, list in pairs(parts) do
				local layer = Render.layers[name]
				for i = #list, 1, -1 do
					if layer then
						releaseWedge(layer, list[i])
					else
						pcall(list[i].Destroy, list[i])
					end
					list[i] = nil
				end
			end
		end
	end

	function Render.flush(now)
		for pg in pairs(dirtyPages) do
			dirtyPages[pg] = nil
			flushPage(pg)
			if pg.tris <= 2 then
				pg.emptySince = pg.emptySince or now
			end
		end
		if now - Render.lastSweep > 5 then
			Render.lastSweep = now
			for pg in pairs(allPages) do
				if pg.tris <= 2 and pg.emptySince and now - pg.emptySince > 15 then
					destroyPage(pg)
				end
			end
		end
	end

	function Render.setVisible(on)
		for _, layer in pairs(Render.layers) do
			local target = on and Workspace or nil
			if layer.model.Parent ~= target then
				layer.model.Parent = target
			end
		end
	end

	function Render.init()
		local direct = CONFIG.RenderStyle == "Direct"
		makeLayer("main", CONTAINER_NAME, not direct, direct and CONFIG.DirectTransparency or 0.999,
			Enum.Material.Neon, CONFIG.ShadowColor)
		makeLayer("tint", TINT_CONTAINER_NAME, false, CONFIG.TransparentShadowTransparency,
			Enum.Material.SmoothPlastic, Color3.new(0.5, 0.5, 0.5))
		local ok, em = pcall(function()
			return AssetService:CreateEditableMesh()
		end)
		if not ok or not em then
			warnOnce("api", "EditableMesh isn't available in this game (Game Settings > Security > "
				.. "Allow Mesh / Image APIs), so shadows are drawn with parts.")
			return
		end
		MeshData.allowed = true
		local okBatch, batchFn = pcall(function()
			return em.BatchAdd
		end)
		Render.batch = okBatch and type(batchFn) == "function"
		if CONFIG.Backend ~= "Parts" then
			local okPart, part = pcall(function()
				addAnchors(em)
				return AssetService:CreateMeshPartAsync(Content.fromObject(em), PAGE_OPTIONS)
			end)
			if okPart and part then
				Render.meshOk = true
				part:Destroy()
			else
				warnOnce("meshpart", "Couldn't create EditableMesh parts (" .. tostring(part) .. "), using parts.")
			end
		end
		pcall(em.Destroy, em)
	end

	function Render.destroyAll()
		for pg in pairs(allPages) do
			pcall(pg.mesh.Destroy, pg.mesh)
		end
		table.clear(allPages)
		for _, layer in pairs(Render.layers) do
			pcall(layer.model.Destroy, layer.model)
			for _, w in ipairs(layer.pool) do
				pcall(w.Destroy, w)
			end
			table.clear(layer.pool)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Shadow jobs ("records"): each one owns the shadow geometry it produced last
----------------------------------------------------------------------------------------------------
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

do
	local function newRecord(owner, pool)
		stats.records += 1
		return {owner = owner, pool = pool, mesh = {}, parts = nil, receivers = nil, lightVersion = -1, lod = 0, cfVersion = -1}
	end

	local function unlinkReceivers(rec)
		local list = rec.receivers
		if not list then
			return
		end
		for i = #list, 1, -1 do
			local r = list[i]
			list[i] = nil
			local deps = r.dependents
			if deps then
				deps[rec] = nil
			end
		end
	end

	function dropRecord(rec)
		if not rec then
			return
		end
		unlinkReceivers(rec)
		Render.clear(rec)
		stats.records -= 1
	end

	-- Every part whose bounds touch a box given in light space (x along a, y along b, z along L).
	function queryBox(minX, maxX, minY, maxY, minZ, maxZ)
		local a, b, L = Light.a, Light.b, Light.L
		local center = a * ((minX + maxX) * 0.5) + b * ((minY + maxY) * 0.5) + L * ((minZ + maxZ) * 0.5)
		local size = V3(max(maxX - minX, 0.05), max(maxY - minY, 0.05), max(maxZ - minZ, 0.05))
		return Workspace:GetPartBoundsInBox(CFrame.fromMatrix(center, a, b, L), size, overlapParams)
	end

	local function emitBackFaces(state, shape)
		local faces = getWorldFaces(state, shape)
		for i = 1, #faces do
			local wf = faces[i]
			if wf.s < MIN_LIT then
				local lf = wf.lf
				emitFace(wf, lf.xs, lf.ys, lf.count, false)
			end
		end
	end

	local GEOMS = {}

	-- A still part: shadows onto still parts and terrain, plus its own dark sides.
	function buildStaticCaster(state, lod)
		local shape, pending = getShape(state, lod)
		if pending then
			return false
		end
		local rec = state.casterRec
		if not rec then
			rec = newRecord(state, "static")
			state.casterRec = rec
		end
		unlinkReceivers(rec)
		resetOut()
		if shape and state.isCaster and Light.valid then
			local g = getGeom(state, shape, lod)
			if g.hullCount >= 3 then
				local touched = rec.receivers
				if not touched then
					touched = {}
					rec.receivers = touched
				end
				local parts = queryBox(g.minX - MARGIN, g.maxX + MARGIN, g.minY - MARGIN, g.maxY + MARGIN,
					g.minZ - MARGIN, g.maxZ + CONFIG.MaxShadowLength)
				for i = 1, #parts do
					local r = states[parts[i]]
					if r and r ~= state and r.isReceiver and not r.dynamic then
						local rshape = getShape(r, lod)
						if rshape and rshape.faces then
							local before = Out.nPoly
							local faces = getWorldFaces(r, rshape)
							for f = 1, #faces do
								local wf = faces[f]
								if wf.s > MIN_LIT and lightOverlap(g, wf) then
									castOnFace(g, wf)
								end
							end
							if Out.nPoly > before then
								touched[#touched + 1] = r
								local deps = r.dependents
								if not deps then
									deps = {}
									r.dependents = deps
								end
								deps[rec] = true
							end
						end
					end
				end
				if terrainPresent and CONFIG.TerrainShadows then
					GEOMS[1] = g
					drapeOnTerrain(GEOMS, 1, g.minX, g.maxX, g.minY, g.maxY, g.minZ, g.maxZ, lod)
					GEOMS[1] = nil
				end
			end
			if CONFIG.ShadeBackFaces and shape.shade and not state.tint then
				emitBackFaces(state, shape)
			end
		end
		Render.commit(rec, Out, "static")
		rec.lightVersion = Light.version
		rec.lod = lod
		state.dirty = false
		return true
	end

	-- Moving casters (a character, or one moving part): shadows onto still parts and terrain.
	function buildDynamicCaster(owner, members, lod)
		local rec = owner.casterRec
		if not rec then
			rec = newRecord(owner, "dynamic")
			owner.casterRec = rec
		end
		resetOut()
		if Light.valid then
			local geoms, ng = {}, 0
			local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
			for i = 1, #members do
				local st = members[i]
				if st.isCaster and not st.dead then
					local shape = getShape(st, lod)
					if shape then
						local g = getGeom(st, shape, lod)
						if g.hullCount >= 3 then
							ng += 1
							geoms[ng] = g
							minX, maxX = min(minX, g.minX), max(maxX, g.maxX)
							minY, maxY = min(minY, g.minY), max(maxY, g.maxY)
							minZ, maxZ = min(minZ, g.minZ), max(maxZ, g.maxZ)
						end
						if CONFIG.ShadeBackFaces and shape.shade and not st.tint then
							emitBackFaces(st, shape)
						end
					end
				end
			end
			if ng > 0 then
				local parts = queryBox(minX - MARGIN, maxX + MARGIN, minY - MARGIN, maxY + MARGIN,
					minZ - MARGIN, maxZ + CONFIG.MaxShadowLength)
				for i = 1, #parts do
					local r = states[parts[i]]
					if r and r.isReceiver and not r.dynamic then
						local rshape = getShape(r, lod)
						if rshape and rshape.faces then
							local faces = getWorldFaces(r, rshape)
							for f = 1, #faces do
								local wf = faces[f]
								if wf.s > MIN_LIT then
									for k = 1, ng do
										local g = geoms[k]
										if lightOverlap(g, wf) then
											castOnFace(g, wf)
										end
									end
								end
							end
						end
					end
				end
				if terrainPresent and CONFIG.TerrainShadows then
					drapeOnTerrain(geoms, ng, minX, maxX, minY, maxY, minZ, maxZ, lod)
				end
			end
		end
		Render.commit(rec, Out, "dynamic")
		rec.lightVersion = Light.version
		rec.lod = lod
	end

	local RECV = {}
	-- Shadows that land ON a character or a loose part, from anything between it and the light.
	function buildReceiverRecord(owner, members, lod)
		local rec = owner.recvRec
		if not rec then
			rec = newRecord(owner, "dynamic")
			owner.recvRec = rec
		end
		resetOut()
		if Light.valid then
			local nr = 0
			local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
			for i = 1, #members do
				local st = members[i]
				if st.isReceiver and not st.dead and st.part.LocalTransparencyModifier < 0.5 then
					local shape = getShape(st, lod)
					if shape and shape.faces then
						local faces = getWorldFaces(st, shape)
						if #faces > 0 then
							nr += 1
							RECV[nr] = st
							for f = 1, #faces do
								local wf = faces[f]
								minX, maxX = min(minX, wf.minX), max(maxX, wf.maxX)
								minY, maxY = min(minY, wf.minY), max(maxY, wf.maxY)
								minZ, maxZ = min(minZ, wf.minZ), max(maxZ, wf.maxZ)
							end
						end
					end
				end
			end
			if nr > 0 then
				local parts = queryBox(minX - MARGIN, maxX + MARGIN, minY - MARGIN, maxY + MARGIN,
					minZ - CONFIG.MaxShadowLength, maxZ + MARGIN)
				for i = 1, #parts do
					local c = states[parts[i]]
					if c and c.isCaster and not c.dead then
						local cshape = getShape(c, lod)
						if cshape then
							local g = getGeom(c, cshape, lod)
							if g.hullCount >= 3 then
								for k = 1, nr do
									local st = RECV[k]
									if st ~= c then
										local faces = st.wf
										for f = 1, #faces do
											local wf = faces[f]
											if wf.s > MIN_LIT and lightOverlap(g, wf) then
												castOnFace(g, wf)
											end
										end
									end
								end
							end
						end
					end
				end
			end
			for k = 1, nr do
				RECV[k] = nil
			end
		end
		Render.commit(rec, Out, "dynamic")
		rec.lightVersion = Light.version
	end

	function safeCall(fn, ...)
		local ok, res = pcall(fn, ...)
		if not ok then
			errorCount += 1
			if errorCount <= 10 then
				warn("[StencilShadows] " .. tostring(res))
			end
			return nil, true
		end
		return res, false
	end
end

----------------------------------------------------------------------------------------------------
-- Part registry
----------------------------------------------------------------------------------------------------
do
	local humanoidModels = setmetatable({}, {__mode = "k"})

	local function characterModelOf(part)
		local inst = part.Parent
		while inst and inst ~= Workspace do
			if inst:IsA("Model") then
				local has = humanoidModels[inst]
				if has == nil then
					has = inst:FindFirstChildOfClass("Humanoid") ~= nil
					humanoidModels[inst] = has
				end
				if has then
					return inst
				end
			end
			inst = inst.Parent
		end
		return nil
	end

	local function isIgnored(part)
		local attr = CONFIG.IgnoreAttribute
		if not attr or attr == "" then
			return false
		end
		local inst = part
		while inst and inst ~= Workspace do
			if inst:GetAttribute(attr) then
				return true
			end
			inst = inst.Parent
		end
		return false
	end

	-- Decides whether a part casts and / or receives shadows.
	local function evaluate(state)
		local part = state.part
		local size = part.Size
		local t = part.Transparency
		local visible = t < 0.98 and max(size.X, size.Y, size.Z) >= CONFIG.MinPartSize and not state.ignored
		state.isReceiver = visible
		local caster = visible and (state.castShadow or not CONFIG.RespectCastShadow)
		if caster and state.character and not CONFIG.CharacterShadows then
			caster = false
		end
		if caster and state.accessory and not CONFIG.AccessoryShadows then
			caster = false
		end
		state.tint = false
		if caster and t > CONFIG.OpaqueThreshold then
			if CONFIG.TransparentShadows then
				local c = part.Color
				state.tint = Color3.new(c.R * 0.55, c.G * 0.55, c.B * 0.55)
			else
				caster = false
			end
		end
		state.isCaster = caster
	end

	markDirty = function(state)
		state.dirty = true
		local ch = state.chunk
		if ch then
			ch.needsScan = true
			ch.rescan = true
		end
	end

	local function markUrgent(state)
		markDirty(state)
		if not state.urgent then
			state.urgent = true
			qpush(urgentQ, state)
		end
	end

	-- Everything that drew a shadow on this part has to redraw.
	markDependentsDirty = function(state)
		local deps = state.dependents
		if not deps then
			return
		end
		state.dependents = nil
		for rec in pairs(deps) do
			local owner = rec.owner
			if owner and not owner.dead and owner.part then
				markUrgent(owner)
			end
		end
	end

	addToChunk = function(state)
		if state.chunk or state.dynamic or not state.isCaster then
			return
		end
		local pos = state.part.Position
		local size = CONFIG.ChunkSize
		local ix, iy, iz = floor(pos.X / size), floor(pos.Y / size), floor(pos.Z / size)
		local key = cellKey(ix, iy, iz)
		local ch = chunks[key]
		if not ch then
			ch = {key = key, center = V3((ix + 0.5) * size, (iy + 0.5) * size, (iz + 0.5) * size), list = {},
				active = false, lod = 0, needsScan = true, cursor = 1, rescan = false, dist = 0, reach = size * 0.87}
			chunks[key] = ch
			refreshSoon = true
		end
		-- big parts reach far outside their chunk: keep the chunk loaded while any of it is near
		local reach = (pos - ch.center).Magnitude + state.part.Size.Magnitude * 0.5
		if reach > ch.reach then
			ch.reach = reach
		end
		local list = ch.list
		list[#list + 1] = state
		state.chunk = ch
		state.chunkIndex = #list
		if initialScanDone then
			markUrgent(state) -- a part that just appeared or came to rest: shadow right away
		else
			markDirty(state) -- first load goes chunk by chunk, nearest first
		end
	end

	removeFromChunk = function(state)
		local ch = state.chunk
		if not ch then
			return
		end
		local list = ch.list
		local i = state.chunkIndex
		local last = list[#list]
		list[i] = last
		last.chunkIndex = i
		list[#list] = nil
		if i < ch.cursor then
			ch.rescan = true -- an unscanned part moved behind the scan cursor
		end
		state.chunk = nil
		state.chunkIndex = nil
		if state.casterRec and state.casterRec.pool == "static" then
			dropRecord(state.casterRec)
			state.casterRec = nil
		end
		if #list == 0 then
			chunks[ch.key] = nil
		end
	end

	queueUpstream = function(state)
		if not state.upstreamQueued then
			state.upstreamQueued = true
			qpush(upstreamQ, state)
		end
	end

	function register(part)
		if states[part] or not alive then
			return
		end
		if part:IsA("Terrain") or part:IsA("NegateOperation") then
			return
		end
		local parent = part.Parent
		local main, tint = Render.layers.main, Render.layers.tint
		if parent == nil or parent == main.model or parent == tint.model then
			return
		end
		if not part:IsDescendantOf(Workspace) then
			return
		end
		local camera = Workspace.CurrentCamera
		if camera and part:IsDescendantOf(camera) then
			return
		end
		nextStateId += 1
		local state = {
			part = part,
			id = nextStateId,
			shapeVersion = 0,
			cfVersion = 0,
			castShadow = part.CastShadow,
			ignored = isIgnored(part),
			lastCF = part.CFrame,
			lastSize = part.Size,
			lastT = part.Transparency,
			lastMove = 0,
			dynamic = false,
			dirty = true,
		}
		local model = characterModelOf(part)
		if model then
			state.character = model
			state.accessory = parent:IsA("Accoutrement")
		end
		evaluate(state)
		states[part] = state
		stats.parts += 1
		if model then
			state.dynamic = true
			state.alwaysDynamic = true
			local info = characters[model]
			if not info then
				info = {model = model, members = {}, isLocal = false, dist = 0, sortDist = 0}
				characters[model] = info
			end
			info.members[#info.members + 1] = state
			state.charInfo = info
		else
			state.conn = part.Changed:Connect(function(prop)
				onPartChanged(state, prop)
			end)
			if not part.Anchored then
				physList[#physList + 1] = state
				state.inPhys = true
			end
			addToChunk(state)
			if initialScanDone and state.isReceiver then
				queueUpstream(state)
			end
		end
	end

	function unregister(state)
		if state.dead then
			return
		end
		state.dead = true
		states[state.part] = nil
		stats.parts -= 1
		if state.conn then
			state.conn:Disconnect()
			state.conn = nil
		end
		if state.casterRec then
			dropRecord(state.casterRec)
			state.casterRec = nil
		end
		if state.recvRec then
			dropRecord(state.recvRec)
			state.recvRec = nil
		end
		removeFromChunk(state)
		dynamicStates[state] = nil
		markDependentsDirty(state)
		local info = state.charInfo
		if info then
			local members = info.members
			for i = #members, 1, -1 do
				if members[i] == state then
					tremove(members, i)
					break
				end
			end
			if #members == 0 then
				dropRecord(info.casterRec)
				info.casterRec = nil
				dropRecord(info.recvRec)
				info.recvRec = nil
				characters[info.model] = nil
			end
		end
	end

	local function becomeDynamic(state)
		if state.dynamic then
			return
		end
		state.dynamic = true
		dynamicStates[state] = true
		removeFromChunk(state)
		markDependentsDirty(state)
	end

	local function becomeStatic(state)
		if not state.dynamic or state.alwaysDynamic then
			return
		end
		state.dynamic = false
		dynamicStates[state] = nil
		if state.casterRec then
			dropRecord(state.casterRec)
			state.casterRec = nil
		end
		if state.recvRec then
			dropRecord(state.recvRec)
			state.recvRec = nil
		end
		state.lastCF = state.part.CFrame
		addToChunk(state)
		if state.isReceiver then
			queueUpstream(state)
		end
	end

	local function onMoved(state, now)
		state.cfVersion += 1
		state.lastMove = now
		if not state.dynamic then
			becomeDynamic(state)
		end
	end

	-- The part's size, shape, mesh, transparency or CastShadow changed.
	onShapeChanged = function(state)
		state.shapeVersion += 1
		state.geom = nil
		evaluate(state)
		if state.dynamic then
			return
		end
		if state.isCaster and not state.chunk then
			addToChunk(state)
		elseif not state.isCaster and state.chunk then
			removeFromChunk(state)
		end
		if state.chunk then
			markUrgent(state)
		end
		markDependentsDirty(state)
		if state.isReceiver then
			queueUpstream(state)
		end
	end

	local MOVE_PROPS = {CFrame = true, Position = true, Orientation = true, Rotation = true}
	local SHAPE_PROPS = {Size = true, Shape = true, MeshId = true, MeshContent = true}
	local LOOK_PROPS = {Transparency = true, CastShadow = true, Color = true}

	onPartChanged = function(state, prop)
		if state.dead then
			return
		end
		if MOVE_PROPS[prop] then
			state.chMove = true
		elseif SHAPE_PROPS[prop] then
			state.chShape = true
		elseif LOOK_PROPS[prop] then
			if prop == "Color" and not state.tint then
				return
			end
			state.chLook = true
		elseif prop == "Anchored" then
			state.chAnchor = true
		else
			return
		end
		if not state.changeQueued then
			state.changeQueued = true
			qpush(changeQ, state)
		end
	end

	function processChanges(now)
		while true do
			local st = qpop(changeQ)
			if not st then
				return
			end
			st.changeQueued = false
			if not st.dead then
				if st.chAnchor then
					st.chAnchor = false
					if not st.part.Anchored and not st.inPhys then
						physList[#physList + 1] = st
						st.inPhys = true
					end
				end
				if st.chShape or st.chLook then
					if st.chLook then
						st.castShadow = st.part.CastShadow
					end
					st.chShape, st.chLook = false, false
					onShapeChanged(st)
				end
				if st.chMove then
					st.chMove = false
					local cf = st.part.CFrame
					if not cf:FuzzyEq(st.lastCF, 1e-3) then
						st.lastCF = cf
						onMoved(st, now)
					end
				end
			end
		end
	end

	function processRemovals()
		while true do
			local st = qpop(removeQ)
			if not st then
				return
			end
			st.removeQueued = false
			if not st.dead then
				local part = st.part
				unregister(st)
				if part.Parent and part:IsDescendantOf(Workspace) then
					qpush(addQ, part) -- only moved somewhere else inside the workspace
				end
			end
		end
	end

	function processAdds(deadline, limit)
		local count = 0
		while count < limit do
			local part = qpop(addQ)
			if not part then
				initialScanDone = true
				return
			end
			if part.Parent ~= nil and not states[part] then
				register(part)
			end
			count += 1
			if count % 100 == 0 and clock() > deadline then
				return
			end
		end
	end

	-- A Humanoid appeared in / left a model: register its parts again as character / map parts.
	function processCharacterChanges()
		while true do
			local model = qpop(charQ)
			if not model then
				return
			end
			humanoidModels[model] = nil
			if model.Parent then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						local st = states[d]
						if st then
							unregister(st)
						end
						qpush(addQ, d)
					end
				end
			end
		end
	end

	function processMeshReady()
		while true do
			local entry = qpop(MeshData.ready)
			if not entry then
				return
			end
			local users = entry.users
			entry.users = nil
			if users then
				for st in pairs(users) do
					if not st.dead then
						onShapeChanged(st)
					end
				end
			end
		end
	end

	local function boxLightBounds(cf, size)
		local a, b, L = Light.a, Light.b, Light.L
		local r, u, l = cf.RightVector * (size.X * 0.5), cf.UpVector * (size.Y * 0.5), cf.LookVector * (size.Z * 0.5)
		local p = cf.Position
		local ca, cb, cl = p:Dot(a), p:Dot(b), p:Dot(L)
		local ea = abs(r:Dot(a)) + abs(u:Dot(a)) + abs(l:Dot(a))
		local eb = abs(r:Dot(b)) + abs(u:Dot(b)) + abs(l:Dot(b))
		local el = abs(r:Dot(L)) + abs(u:Dot(L)) + abs(l:Dot(L))
		return ca - ea, ca + ea, cb - eb, cb + eb, cl - el, cl + el
	end

	-- A new still surface appeared: casters above it have to include it.
	function processUpstream(deadline)
		while clock() < deadline do
			local st = qpop(upstreamQ)
			if not st then
				return
			end
			st.upstreamQueued = false
			if not st.dead and st.isReceiver and not st.dynamic and Light.valid then
				local part = st.part
				local x0, x1, y0, y1, z0, z1 = boxLightBounds(part.CFrame, part.Size)
				local parts = queryBox(x0 - MARGIN, x1 + MARGIN, y0 - MARGIN, y1 + MARGIN,
					z0 - CONFIG.MaxShadowLength - 1, z1 + MARGIN)
				for i = 1, #parts do
					local c = states[parts[i]]
					if c and c ~= st and c.chunk then
						markDirty(c)
					end
				end
			end
		end
	end

	function pollPhysics(now)
		for st in pairs(dynamicStates) do
			if not st.dead then
				local part = st.part
				if not part.Anchored then
					local cf = part.CFrame
					if not cf:FuzzyEq(st.lastCF, 5e-3) then
						st.lastCF = cf
						st.cfVersion += 1
						st.lastMove = now
					end
				end
				if now - st.lastMove > CONFIG.RestTime then
					becomeStatic(st)
				end
			end
		end
		local n = #physList
		if n == 0 then
			return
		end
		local budget = min(CONFIG.PollPerFrame, n)
		local i = physCursor
		local checked = 0
		while checked < budget and n > 0 do
			if i > n then
				i = 1
			end
			local st = physList[i]
			if st.dead or st.part.Anchored then
				physList[i] = physList[n]
				physList[n] = nil
				n -= 1
				st.inPhys = false
			else
				if not st.dynamic then
					local cf = st.part.CFrame
					if not cf:FuzzyEq(st.lastCF, 5e-3) then
						st.lastCF = cf
						onMoved(st, now)
					end
				end
				i += 1
			end
			checked += 1
		end
		physCursor = i
	end

	function refreshCharacters()
		for model, info in pairs(characters) do
			info.isLocal = LocalPlayer ~= nil and LocalPlayer.Character == model
			for _, st in ipairs(info.members) do
				local part = st.part
				local size, t = part.Size, part.Transparency
				if size ~= st.lastSize or t ~= st.lastT then
					st.lastSize, st.lastT = size, t
					st.shapeVersion += 1
					st.castShadow = part.CastShadow
					evaluate(st)
					info.dirty = true
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Scheduling: nearest map chunks first, inside a per-frame time budget
----------------------------------------------------------------------------------------------------
do
	local staticQueue = {}
	local staticHead = 1
	local lastRefresh = -1
	local lastTerrainCheck = -100
	local lastCharacterRefresh = 0

	local function lodFor(d, current)
		local h = (current == nil or current == 0) and 0 or 10
		local near = CONFIG.NearDetail + (current == 1 and h or -h)
		local mid = CONFIG.MidDetail + ((current == 1 or current == 2) and h or -h)
		if d < near then
			return 1
		elseif d < mid then
			return 2
		end
		return 3
	end

	local function chunkLess(x, y)
		return x.dist < y.dist
	end

	local function refreshChunks(camPos)
		local R = CONFIG.ShadowDistance
		local queue = {}
		for _, ch in pairs(chunks) do
			local d = max(0, (ch.center - camPos).Magnitude - ch.reach)
			ch.dist = d
			if d <= R then
				if not ch.active then
					ch.active = true
					ch.needsScan = true
				end
				local lod = lodFor(d, ch.lod)
				if lod ~= ch.lod then
					ch.lod = lod
					ch.needsScan = true
				end
				if ch.needsScan then
					queue[#queue + 1] = ch
				end
			elseif ch.active and d > R + CONFIG.ChunkSize then
				-- far away now: free its shadows
				ch.active = false
				ch.lod = 0
				ch.cursor = 1
				local list = ch.list
				for i = 1, #list do
					local st = list[i]
					if st.casterRec then
						dropRecord(st.casterRec)
						st.casterRec = nil
					end
				end
			end
		end
		tsort(queue, chunkLess)
		staticQueue = queue
		staticHead = 1
	end

	local function staleIn(st, ch)
		if not st.isCaster or st.dead or st.dynamic then
			return false
		end
		local rec = st.casterRec
		return st.dirty or rec == nil or rec.lightVersion ~= Light.version or rec.lod ~= ch.lod
	end

	local function buildStatic(st, lod)
		local built, failed = safeCall(buildStaticCaster, st, lod)
		if failed then
			st.dirty = false -- don't retry a broken part every frame
			return true
		end
		return built
	end

	local function processStatic(deadline)
		while clock() < deadline do
			local st = qpop(urgentQ)
			if not st then
				break
			end
			st.urgent = false
			local ch = st.chunk
			if ch and ch.active and staleIn(st, ch) then
				if not buildStatic(st, ch.lod) then
					ch.rescan = true
				end
			end
		end
		while clock() < deadline do
			local ch = staticQueue[staticHead]
			if not ch then
				return
			end
			if not ch.active or not ch.needsScan then
				staticHead += 1
			else
				local list = ch.list
				local i = ch.cursor
				if i == 1 then
					ch.rescan = false
				end
				while i <= #list do
					local st = list[i]
					i += 1
					if staleIn(st, ch) then
						if not buildStatic(st, ch.lod) then
							ch.rescan = true
						end
						if clock() >= deadline then
							break
						end
					end
				end
				if i > #list then
					ch.cursor = 1
					if not ch.rescan then
						ch.needsScan = false
					end
					staticHead += 1
				else
					ch.cursor = i
					return
				end
			end
		end
	end

	local CHAR_LIST, MOVE_LIST = {}, {}
	local movingGroups = {}            -- assembly root / model -> group of moving parts
	local MAX_RECEIVER_GROUP = 40      -- bigger moving groups only cast (receiving would cost too much)

	local function groupKeyOf(st)
		local part = st.part
		if not part.Anchored then
			local root = part.AssemblyRootPart
			if root then
				return root
			end
		end
		local parent = part.Parent
		if parent and parent ~= Workspace and parent.ClassName == "Model" then
			return parent
		end
		return part
	end

	local function distLess(x, y)
		return x.sortDist < y.sortDist
	end

	local function characterRoot(info)
		local root = info.model.PrimaryPart
		if root then
			return root
		end
		local first = info.members[1]
		return first and first.part
	end

	-- True when any body part moved (or parts were added / removed) since the last check.
	local function characterMoved(info)
		local last = info.lastCFs
		if not last then
			last = {}
			info.lastCFs = last
		end
		local members = info.members
		local moved = info.dirty or info.memberCount ~= #members
		info.dirty = false
		info.memberCount = #members
		for i = 1, #members do
			local st = members[i]
			local cf = st.part.CFrame
			local prev = last[st]
			if not prev or not cf:FuzzyEq(prev, 1e-4) then
				last[st] = cf
				moved = true
			end
		end
		return moved
	end

	local function processDynamic(camPos, now, deadline)
		-- characters: the local player first, then the nearest
		local nc = 0
		for model, info in pairs(characters) do
			local root = characterRoot(info)
			if root and model.Parent then
				local d = (root.Position - camPos).Magnitude
				info.dist = d
				info.sortDist = info.isLocal and -1 or d
				nc += 1
				CHAR_LIST[nc] = info
			end
		end
		for i = #CHAR_LIST, nc + 1, -1 do
			CHAR_LIST[i] = nil
		end
		if nc > 1 then
			tsort(CHAR_LIST, distLess)
		end
		local casting, receiving = 0, 0
		for i = 1, nc do
			local info = CHAR_LIST[i]
			local lod = info.dist < CONFIG.NearDetail and 1 or 2
			local inBudget = i == 1 or clock() < deadline
			-- a character standing perfectly still keeps its shadows (animated ones always move)
			local moved = characterMoved(info)
			if CONFIG.CharacterShadows and casting < CONFIG.MaxCharacters and info.dist <= CONFIG.DynamicDistance then
				casting += 1
				local rec = info.casterRec
				if inBudget and (moved or not rec or rec.lightVersion ~= Light.version or rec.lod ~= lod) then
					safeCall(buildDynamicCaster, info, info.members, lod)
				end
			elseif info.casterRec then
				dropRecord(info.casterRec)
				info.casterRec = nil
			end
			if receiving < CONFIG.MaxCharacterReceivers and info.dist <= CONFIG.ReceiverDistance then
				receiving += 1
				local rec = info.recvRec
				if inBudget and (moved or not rec or rec.lightVersion ~= Light.version or now - (rec.builtAt or 0) > 0.2) then
					safeCall(buildReceiverRecord, info, info.members, lod)
					if info.recvRec then
						info.recvRec.builtAt = now
					end
				end
			elseif info.recvRec then
				dropRecord(info.recvRec)
				info.recvRec = nil
			end
		end
		-- moving parts, grouped by assembly: a whole car (or a tweened door model) is one job
		for _, grp in pairs(movingGroups) do
			grp.n, grp.sig, grp.ids = 0, 0, 0
		end
		for st in pairs(dynamicStates) do
			if not st.dead then
				local key = groupKeyOf(st)
				local grp = movingGroups[key]
				if not grp then
					grp = {members = {}, n = 0, sig = 0, ids = 0, builtSig = -1, builtIds = -1, recvSig = -1, recvIds = -1}
					movingGroups[key] = grp
				end
				local n = grp.n + 1
				grp.n = n
				grp.members[n] = st
				grp.sig += st.cfVersion
				grp.ids += st.id
			end
		end
		local ng = 0
		for key, grp in pairs(movingGroups) do
			local members = grp.members
			for i = #members, grp.n + 1, -1 do
				members[i] = nil
			end
			if grp.n == 0 then
				dropRecord(grp.casterRec)
				dropRecord(grp.recvRec)
				movingGroups[key] = nil
			else
				grp.sortDist = (members[1].part.Position - camPos).Magnitude
				ng += 1
				MOVE_LIST[ng] = grp
			end
		end
		for i = #MOVE_LIST, ng + 1, -1 do
			MOVE_LIST[i] = nil
		end
		if ng > 1 then
			tsort(MOVE_LIST, distLess)
		end
		local moving, loose = 0, 0
		for i = 1, ng do
			local grp = MOVE_LIST[i]
			local d = grp.sortDist
			local lod = d < CONFIG.NearDetail and 1 or (d < CONFIG.MidDetail and 2 or 3)
			if moving < CONFIG.MaxMovingShadows and d <= CONFIG.DynamicDistance then
				moving += 1
				local rec = grp.casterRec
				local changed = grp.sig ~= grp.builtSig or grp.ids ~= grp.builtIds
				if (changed or not rec or rec.lightVersion ~= Light.version or rec.lod ~= lod) and clock() < deadline then
					safeCall(buildDynamicCaster, grp, grp.members, lod)
					grp.builtSig, grp.builtIds = grp.sig, grp.ids
				end
			elseif grp.casterRec then
				dropRecord(grp.casterRec)
				grp.casterRec = nil
			end
			if loose < CONFIG.MaxLooseReceivers and d <= CONFIG.ReceiverDistance and grp.n <= MAX_RECEIVER_GROUP then
				loose += 1
				local rec = grp.recvRec
				local changed = grp.sig ~= grp.recvSig or grp.ids ~= grp.recvIds
				if (changed or not rec or now - (rec.builtAt or 0) > 0.15) and clock() < deadline then
					safeCall(buildReceiverRecord, grp, grp.members, lod)
					grp.recvSig, grp.recvIds = grp.sig, grp.ids
					if grp.recvRec then
						grp.recvRec.builtAt = now
					end
				end
			elseif grp.recvRec then
				dropRecord(grp.recvRec)
				grp.recvRec = nil
			end
		end
	end

	function step(dt)
		frameId += 1
		local now = clock()
		RaySample.budget = 3
		local loading = not initialScanDone or staticHead <= #staticQueue
		local budget = (loading and dt < 1 / 40) and CONFIG.LoadingBudget or CONFIG.FrameBudget
		local deadline = now + budget / 1000

		processRemovals()
		processCharacterChanges()
		processAdds(initialScanDone and now + 0.0015 or deadline, initialScanDone and 500 or CONFIG.RegisterPerFrame)
		processChanges(now)
		processMeshReady()
		if not enabled then
			return
		end

		if now - lastTerrainCheck > 10 then
			lastTerrainCheck = now
			local ok, cells = pcall(function()
				return Workspace.Terrain:CountCells()
			end)
			terrainPresent = ok and cells > 0
		end
		local lightChanged = updateLight()
		if rebuildRequested then
			rebuildRequested = false
			Light.version += 1
			lightChanged = true
		end
		if lightChanged then
			-- every map chunk rebuilds, nearest first (old shadows stay up until replaced)
			for _, ch in pairs(chunks) do
				ch.needsScan = true
			end
			lastRefresh = -1
		end
		Render.setVisible(Light.valid)
		if not Light.valid then
			return
		end

		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or ZERO
		pollPhysics(now)
		if now - lastCharacterRefresh > 0.5 then
			lastCharacterRefresh = now
			refreshCharacters()
		end
		if refreshSoon or now - lastRefresh > 0.25 then
			refreshSoon = false
			lastRefresh = now
			refreshChunks(camPos)
		end
		processDynamic(camPos, now, deadline)
		if initialScanDone then
			processUpstream(deadline)
			processStatic(deadline)
		end
		Render.flush(now)
		stats.frameMs = (clock() - now) * 1000
	end
end

----------------------------------------------------------------------------------------------------
-- Toggle, Roblox shadows, API, start-up
----------------------------------------------------------------------------------------------------
local function applyRobloxShadows(customOn)
	if not CONFIG.DisableRobloxShadows then
		return
	end
	pcall(function()
		Lighting.GlobalShadows = (not customOn) and savedGlobalShadows
	end)
end

local function setEnabled(on)
	if on == enabled or not alive then
		return
	end
	enabled = on
	Render.setVisible(on and Light.valid)
	applyRobloxShadows(on)
end

local API = {Config = CONFIG}

local function shutdown()
	if not alive then
		return
	end
	alive = false
	for i = 1, #connections do
		pcall(function()
			connections[i]:Disconnect()
		end)
	end
	for _, st in pairs(states) do
		if st.conn then
			pcall(function()
				st.conn:Disconnect()
			end)
		end
	end
	pcall(Render.destroyAll)
	if CONFIG.DisableRobloxShadows then
		pcall(function()
			Lighting.GlobalShadows = savedGlobalShadows
		end)
	end
	pcall(function()
		Lighting:SetAttribute(SAVED_SHADOWS_ATTR, nil)
	end)
	if _G.StencilShadows == API then
		_G.StencilShadows = nil
	end
	if _G.__StencilShadowsCleanup == shutdown then
		_G.__StencilShadowsCleanup = nil
	end
end

function API.SetEnabled(on)
	setEnabled(on and true or false)
end

function API.Toggle()
	setEnabled(not enabled)
end

function API.IsEnabled()
	return enabled
end

function API.Rebuild()
	rebuildRequested = true
end

function API.GetStats()
	return table.clone(stats)
end

function API.Destroy()
	shutdown()
end

local function onDescendantAdded(inst)
	if not alive then
		return
	end
	local parent = inst.Parent
	local main, tint = Render.layers.main, Render.layers.tint
	if parent == main.model or parent == tint.model then
		return
	end
	if inst:IsA("BasePart") then
		qpush(addQ, inst)
	elseif inst:IsA("Humanoid") then
		if parent then
			qpush(charQ, parent)
		end
	elseif inst:IsA("DataModelMesh") then
		local st = parent and states[parent]
		if st then
			onPartChanged(st, "Shape")
		end
	end
end

local function onDescendantRemoving(inst)
	if not alive then
		return
	end
	if inst:IsA("BasePart") then
		local st = states[inst]
		if st and not st.removeQueued then
			st.removeQueued = true
			qpush(removeQ, st)
		end
	elseif inst:IsA("Humanoid") then
		local parent = inst.Parent
		local main = Render.layers.main
		if parent and parent ~= main.model then
			qpush(charQ, parent)
		end
	elseif inst:IsA("DataModelMesh") then
		local st = inst.Parent and states[inst.Parent]
		if st then
			onPartChanged(st, "Shape")
		end
	end
end

local function mainLoop()
	while alive do
		local dt = RunService.Heartbeat:Wait()
		if not alive then
			break
		end
		local ok, err = pcall(step, dt)
		if not ok then
			errorCount += 1
			if errorCount <= 10 then
				warn("[StencilShadows] " .. tostring(err))
			end
		end
	end
end

-- start
Render.init()
overlapParams.FilterDescendantsInstances = {Render.layers.main.model, Render.layers.tint.model}

do
	local saved = Lighting:GetAttribute(SAVED_SHADOWS_ATTR)
	if type(saved) ~= "boolean" then
		saved = Lighting.GlobalShadows
		pcall(function()
			Lighting:SetAttribute(SAVED_SHADOWS_ATTR, saved)
		end)
	end
	savedGlobalShadows = saved
end

connect(Workspace.DescendantAdded, onDescendantAdded)
connect(Workspace.DescendantRemoving, onDescendantRemoving)
connect(UserInputService.InputBegan, function(input, processed)
	if processed or not alive then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		setEnabled(not enabled)
	end
end)
connect(Lighting:GetPropertyChangedSignal("GlobalShadows"), function()
	-- something else switched Roblox shadows back on: remember that, keep them off while enabled
	if alive and enabled and CONFIG.DisableRobloxShadows and Lighting.GlobalShadows then
		savedGlobalShadows = true
		pcall(function()
			Lighting:SetAttribute(SAVED_SHADOWS_ATTR, true)
		end)
		Lighting.GlobalShadows = false
	end
end)
if typeof(script) == "Instance" then
	connect(script.Destroying, shutdown)
end

for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("BasePart") then
		qpush(addQ, d)
	end
end

if enabled then
	applyRobloxShadows(true)
end
Render.setVisible(false) -- shown once the light has been read

_G.StencilShadows = API
_G.__StencilShadowsCleanup = shutdown

task.spawn(mainLoop)
