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
	   triangles and written into EditableMeshes (or, where EditableMesh isn't allowed, thin wedge
	   parts and blocks). Blocks use their corners, meshes their real triangles or a sampled
	   outline, balls and cylinders the old engine's 16 x 8 facets (their dark side in steps).
	 * Shadows are drawn as plain see-through geometry with smooth edges ("Direct"); where two
	   shadows overlap on a surface one is cut away, so nothing is ever darker than one shadow -
	   which is exactly what made stencil shadows look the way they did. ("Highlight" instead
	   merges everything with one Highlight, whose edges look jagged on phones.)
	 * At the start the game pauses for a moment (no loading screen) while the shadows are built
	   - the whole map, unless it's huge - then they all appear at once. Moving parts, vehicles
	   and characters are rebuilt whenever they move. Shadows also land on players and loose
	   parts, drape over terrain, and the sides of parts that face away from the light are dark,
	   as if inside the old shadow volumes.
	 * Characters cast their exact silhouette on flat floors (a black copy seen from the light),
	   and real avatar outlines elsewhere. Their dark sides come from copies of their meshes
	   (dynamic heads and hair too); a character fully in shade is darkened by one Highlight.
	 * Shadows follow the sun, and the moon at night. In the 2013 edition (DynamicLights) lamps
	   light up shadows where they shine and cast stencil shadows of their own there.

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
	RenderStyle = "Direct",               -- "Direct":    plain see-through geometry with smooth
	                                      --              (anti-aliased) edges; overlapping shadows
	                                      --              are cut apart so they never stack
	                                      -- "Highlight": merged by one Highlight (Roblox draws
	                                      --              Highlights without anti-aliasing, so
	                                      --              their edges look jagged on phones)
	DirectTransparency = 0.62,            -- part transparency used by the "Direct" style
	SurfaceOffset = 0.04,                 -- how far shadows float off a surface (stops z-fighting)
	CharacterSurfaceOffset = 0.012,       -- the same on characters (seen up close: kept tight)
	ShadeBackFaces = true,                -- sides facing away from the light are shadowed too
	RoundShading = "Blocky",              -- dark sides of balls / cylinders: "Blocky" = in steps,
	                                      -- facet by facet, like the old engine's low-poly balls;
	                                      -- "Smooth" = along the real curve (balls only with
	                                      -- EditableMesh); false = left to Roblox's own shading
	GlowingPartsStayLit = true,           -- Neon parts give off light: shadows don't darken them
	TransparentShadows = false,           -- TRANSPARENT_SHADOWS_ENABLED: see-through parts cast
	TransparentShadowTransparency = 0.75, -- ...lighter shadows tinted with their own color

	-- Lamps (the 2013 edition turns this on) -----------------------------------------------------
	DynamicLights = false,                -- PointLights, SpotLights and SurfaceLights light up the
	                                      -- sun's shadows where they shine and cast stencil shadows
	                                      -- of their own there (in 2013 both were in the game)
	LightPoolSize = 0.6,                  -- how much of a lamp's Range takes the shadow away fully
	LightFade = true,                     -- a lighter ring around each pool of light

	-- Renderer ----------------------------------------------------------------------------------
	Backend = "Auto",                     -- "Auto" | "EditableMesh" | "Parts"
	                                      -- EditableMesh needs Game Settings > Security >
	                                      -- "Allow Mesh / Image APIs". Auto falls back to parts.

	-- Light -------------------------------------------------------------------------------------
	UseMoon = true,
	MinLightElevation = 1.5,              -- degrees; sun AND moon lower than this = no shadows
	MinShadowElevation = 8,               -- degrees; a lower light is raised to this angle
	LightUpdateAngle = 0.6,               -- degrees the light must move before map shadows rebuild
	MaxShadowLength = 600,                -- studs a shadow can reach past its caster

	-- Range & detail ----------------------------------------------------------------------------
	ShadowDistance = 520,                 -- map shadows are kept within this distance of the camera
	PartsShadowDistance = 300,            -- the same when drawing with parts (no EditableMesh)
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
	AvatarOutlines = true,                -- real avatar outlines from hidden hull copies of their meshes
	ExactSilhouettes = true,              -- on flat lit floors, characters cast their exact silhouette
	MaxSilhouettes = 4,                   -- characters (nearest first) that can have one at a time
	ShadowsOnAvatars = true,              -- package avatars darken in shadow (real mesh shape)
	IgnoreAttribute = "NoStencilShadow",  -- set this attribute to true on a part / model to skip it

	-- Moving things -----------------------------------------------------------------------------
	DynamicDistance = 260,                -- moving parts and characters cast shadows within this range
	MaxCharacters = 8,
	MaxMovingShadows = 150,               -- moving objects with shadows (a whole vehicle counts once)
	RestTime = 1.5,                       -- seconds a moved part must stay still to rejoin the map
	ReceiverDistance = 120,               -- players / loose parts this close get shadows drawn on them
	MaxCharacterReceivers = 3,
	MaxLooseReceivers = 24,

	-- Performance -------------------------------------------------------------------------------
	FrameBudget = 4.2,                    -- milliseconds of work per frame
	LoadingBudget = 9,                    -- milliseconds per frame while shadows are still loading
	RegisterPerFrame = 4000,              -- instances scanned per frame at startup (also time-limited)
	PollPerFrame = 250,                   -- resting unanchored parts checked for movement per frame

	-- Roblox's own shadows ----------------------------------------------------------------------
	DisableRobloxShadows = true,          -- Lighting.GlobalShadows is off while this is enabled

	-- Start-up ----------------------------------------------------------------------------------
	LoadPause = true,                     -- freeze the game for a moment at the start (no loading
	                                      -- screen) so every nearby shadow appears at once
	LoadPauseMax = 5,                     -- seconds the start-up pause may last at most
	LoadPauseSlice = 1.2,                 -- it freezes in slices this long, with one frame between
	LoadWholeMap = true,                  -- maps up to the size below are built completely during
	                                      -- the pause and kept: nothing loads while you walk around
	                                      -- (bigger maps load around you as you go)
	WholeMapParts = 12000,                -- most parts for a whole-map load with EditableMesh...
	PartsWholeMapParts = 4000,            -- ...and when drawing with parts
	WholeMapPauseMax = 20,                -- seconds the pause may last for a whole-map load
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
local PROBE_NAME = "__StencilShadowsProbe"
local SILHOUETTE_NAME = "__StencilShadowsSilhouettes"
local LIT_CONTAINER_NAME = "__StencilShadowsLampRing"
local SILHOUETTE_GUI = "StencilSilhouette"
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
	-- the older engine kept its cleanup in getgenv() when it was run from an executor
	local envs = {_G}
	if typeof(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" and env ~= _G then
			envs[2] = env
		end
	end
	for _, env in ipairs(envs) do
		for _, key in ipairs({"__StencilShadowsCleanup", "__StencilShadowEngineCleanup"}) do
			local fn = env[key]
			if type(fn) == "function" then
				pcall(fn)
				env[key] = nil
			end
		end
	end
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			if child.Name == SILHOUETTE_GUI then
				pcall(child.Destroy, child)
			end
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		local name = child.Name
		if name == CONTAINER_NAME or name == TINT_CONTAINER_NAME or name == PROBE_NAME or name == SILHOUETTE_NAME
			or name == LIT_CONTAINER_NAME
			or name == "__StencilShadowReceivers" then
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
local wholeMap = false        -- the whole map is built and kept (LoadWholeMap)
local savedGlobalShadows = true
local errorCount = 0
local rebuildRequested = false
local refreshSoon = false      -- a new map chunk appeared: activate it next frame
local meshMode = false         -- shadows are drawn into EditableMesh pages (not parts)
local holdHidden = false       -- shadows stay hidden while the start-up pause builds them
local started = false          -- the start-up pause is over
local newCharacter = false     -- a character appeared since the last character refresh

local stats = {parts = 0, records = 0, pages = 0, wedges = 0, meshLoads = 0, frameMs = 0, backend = "Parts", loadPauseMs = 0}

-- Functions shared between sections. Each section below is its own do-block so the script stays
-- far below Luau's limit of 200 locals per function.
local getShape, onShapeChanged, onPartChanged
local markDirty, markDependentsDirty, addToChunk, removeFromChunk, queueUpstream
local convexHull, clipLine, clipByLines, polyArea, reversePoly, edgeLines, setLine
local updateLight, supportPoints, waitForMesh, getGeom, getWorldFaces
local resetOut, emitFace, emitPlain, emitWorld, emitCore, lightOverlap, castOnFace, drapeOnTerrain, grownFace
local queryBox, dropRecord, buildStaticCaster, buildDynamicCaster, buildReceiverRecord, safeCall
local register, unregister, processChanges, processRemovals, processAdds, processCharacterChanges
local processMeshReady, processProbeReady, processUpstream, pollPhysics, refreshCharacters, step

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
	-- points are sorted on coordinates rounded to 1e-5 studs, so points that land on (almost) the
	-- same spot sit next to each other and are merged
	local QX, QY = {}, {}
	local function hullLess(i, j)
		local a, b = QX[i], QX[j]
		if a ~= b then
			return a < b
		end
		return QY[i] < QY[j]
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
		for i = 1, n do
			QX[i] = floor(px[i] * 1e5 + 0.5)
			QY[i] = floor(py[i] * 1e5 + 0.5)
		end
		tsort(order, hullLess)
		-- points that land on the same spot (the top and bottom of an upright prism seen from
		-- straight above) would trip the chains below: keep one of each
		local m, lx, ly = 0, nil, nil
		for t = 1, n do
			local i = order[t]
			local x, y = QX[i], QY[i]
			if x ~= lx or y ~= ly then
				m += 1
				order[m] = i
				lx, ly = x, y
			end
		end
		n = m
		if n < 3 then
			for i = 1, n do
				out[i] = order[i]
			end
			return n
		end
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

	-- Shadows float a little off a face (`lift`). Where two faces meet at an edge, their lifted
	-- shadows would leave a thin lit line along it, so each face's shadow area is grown past its
	-- edges until it meets the neighbour's: by lift * tan(half the angle between the two faces'
	-- normals), which is exactly `lift` at a right-angled edge. ks: that tangent per edge line
	-- (nil = 1 for every edge).
	local function growFace(face, ks)
		face.ks = ks or false
	end

	-- The face's outline and edge lines grown for a lift (cached per lift: one shape can be shared
	-- by a map part and a character part, which use different lifts).
	grownFace = function(face, lift)
		if face.ks == nil or lift <= 0 then
			return face
		end
		local cache = face.grown
		if not cache then
			cache = {}
			face.grown = cache
		end
		local g = cache[lift]
		if g then
			return g
		end
		local ks = face.ks
		local lines, nLines = face.lines, face.nLines
		local el = tcreate(nLines * 3)
		for l = 0, nLines - 1 do
			local b = l * 3
			el[b + 1] = lines[b + 1]
			el[b + 2] = lines[b + 2]
			el[b + 3] = lines[b + 3] + lift * (ks and ks[l + 1] or 1)
		end
		-- the grown outline: where consecutive grown edge lines cross
		local exs, eys, m = {}, {}, 0
		for l = 0, nLines - 1 do
			local p = ((l - 1) % nLines) * 3
			local q = l * 3
			local A1, B1, C1 = el[p + 1], el[p + 2], el[p + 3]
			local A2, B2, C2 = el[q + 1], el[q + 2], el[q + 3]
			local det = A1 * B2 - A2 * B1
			if abs(det) > 1e-9 then
				m += 1
				exs[m] = (B1 * C2 - B2 * C1) / det
				eys[m] = (A2 * C1 - A1 * C2) / det
			end
		end
		if m < 3 then
			g = face
		else
			g = {lines = el, nLines = nLines, xs = exs, ys = eys, count = m}
		end
		cache[lift] = g
		return g
	end

	-- tan(half the angle) between each face and the face across each of its edges
	local function growFaces(faces)
		for fi = 1, #faces do
			local f = faces[fi]
			local o, u, v, n = f.o, f.u, f.v, f.n
			local xs, ys, count = f.xs, f.ys, f.count
			local ks = {}
			for i = 1, count do
				local j = i % count + 1
				local ax, ay, bx, by = xs[i], ys[i], xs[j], ys[j]
				local ex, ey = bx - ax, by - ay
				if sqrt(ex * ex + ey * ey) > 1e-7 then -- the same edges edgeLines keeps
					local pa, pb = o + u * ax + v * ay, o + u * bx + v * by
					local tol = 1e-4 * (1 + pa.Magnitude + pb.Magnitude)
					local k = 1
					for gi = 1, #faces do
						local g = faces[gi]
						if gi ~= fi and abs((pa - g.o):Dot(g.n)) < tol and abs((pb - g.o):Dot(g.n)) < tol then
							local c = n:Dot(g.n)
							k = min(4, n:Cross(g.n).Magnitude / max(1 + c, 1e-3))
							break
						end
					end
					ks[#ks + 1] = k
				end
			end
			growFace(f, ks)
		end
	end

	-- Convex polyhedron from vertices and face index loops (outward normals worked out here).
	local function makePolyhedron(verts, faceLists, skipGrowth)
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
		if not skipGrowth then
			growFaces(faces)
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
		if shape.core then
			copy.core = {c = shape.core.c + offset, r = shape.core.r}
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
		if shape.terms then
			local ts = {}
			for i, t in ipairs(shape.terms) do
				ts[i] = {c = t.c + offset, axis = t.axis, rinv2 = t.rinv2}
			end
			copy.terms = ts
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

	-- Cylinder outline: a prism whose flat sides touch the real curve (`phase` 0: its corners sit at
	-- whole steps around instead of half steps).
	local function prism(len, r, segs, axis, phase)
		local rc = r / cos(pi / segs)
		local h = len / 2
		local verts = {}
		for i = 0, segs - 1 do
			local t = (i + (phase or 0.5)) * 2 * pi / segs
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
		return makePolyhedron(verts, faces, true)
	end

	-- Round surfaces get their own facets that wrap the real curve from just outside it. The
	-- corners sit only as far out as needed for every facet to clear the curve, neighbouring
	-- facets share their corners (so there are no cracks), and every facet knows the true surface
	-- normal there ("term"), so a dark side is cut exactly where the real surface turns away from
	-- the light instead of following the facets.
	local SURFACE_FLOAT = {0.07, 0.15, 0.35} -- studs a facet corner may float off the curve: near / mid / far

	local function outlineSegments(lod)
		local list = CONFIG.CurveSegments
		return list[lod] or list[#list] or 12
	end

	-- How many facets go around a curve (largest radius R, smallest r), and the clearance they
	-- keep from it as a fraction of r.
	local function surfaceSegments(R, r, lod, sphere)
		local mrel = max(0.004, 0.012 / max(r, 1e-3))
		local slack = (SURFACE_FLOAT[lod] or 0.3) / max(R, 1e-3) - mrel
		-- with parts every facet costs parts of its own, so fewer of them
		local most = sphere and (meshMode and 36 or 20) or (meshMode and 64 or 24)
		local m = huge
		if slack > 1e-4 then
			-- a facet's corners are about this angle away from its middle
			local delta = sqrt(2 * slack)
			m = ceil(2 * pi / (delta * (sphere and 1.4142 or 2)))
		end
		-- (the third value: how many it would take, before the caps)
		return max(sphere and 16 or 12, min(most, m)), mrel, m
	end

	-- Smallest distance from the centre to the plane of any facet of a unit lat-long sphere
	-- (m facets around, k rows from pole to pole).
	local function sphereClearance(m, k)
		local dmin = 1
		local c, s = cos(2 * pi / m), sin(2 * pi / m)
		for i = 0, k - 1 do
			local t1, t2 = pi * i / k, pi * (i + 1) / k
			local p1 = V3(sin(t1), cos(t1), 0)
			local p2 = V3(sin(t1) * c, cos(t1), sin(t1) * s)
			local p3 = V3(sin(t2) * c, cos(t2), sin(t2) * s)
			local p4 = V3(sin(t2), cos(t2), 0)
			local loop
			if i == 0 then
				loop = {p1, p3, p4}
			elseif i == k - 1 then
				loop = {p1, p2, p3}
			else
				loop = {p1, p2, p3, p4}
			end
			local nrm = newellNormal(loop)
			if nrm.Magnitude > 1e-12 then
				local d = abs(nrm.Unit:Dot(p1))
				if d < dmin then
					dmin = d
				end
			end
		end
		return dmin
	end

	-- A facet whose corners are already in order around it (either way round). `inside` is any
	-- point inside the (convex) shape.
	local function quickFace(verts, inside, term)
		local count = #verts
		local o = averageOf(verts)
		local nrm = newellNormal(verts)
		local mag = nrm.Magnitude
		if mag < 1e-12 then
			return nil
		end
		nrm /= mag
		if nrm:Dot(o - inside) < 0 then
			nrm = -nrm
			local flipped = tcreate(count)
			for i = 1, count do
				flipped[i] = verts[count + 1 - i]
			end
			verts = flipped
		end
		local u = verts[2] - verts[1]
		u -= nrm * u:Dot(nrm)
		local um = u.Magnitude
		if um < 1e-9 then
			return nil
		end
		u /= um
		local v = nrm:Cross(u)
		local xs, ys = tcreate(count), tcreate(count)
		for i = 1, count do
			local d = verts[i] - o
			xs[i], ys[i] = d:Dot(u), d:Dot(v)
		end
		if polyArea(xs, ys, count) < 1e-9 then
			return nil
		end
		local lines, nLines = edgeLines(xs, ys, count)
		if nLines < 3 then
			return nil
		end
		-- lift 0: the facets already float just off the curve
		return {o = o, n = nrm, u = u, v = v, xs = xs, ys = ys, count = count, lines = lines, nLines = nLines,
			lift = 0, term = term}
	end

	-- Facets of a surface of revolution around `axis` (e1, e2 complete the frame). rings:
	-- {t, rho, term} from one end to the other, t = position along the axis, rho = radius
	-- (0 = a pole); `term` belongs to the facets between that ring and the next. An end ring with
	-- rho > 0 gets a flat cap with no term. `scale` (optional) stretches everything (ellipsoids).
	local function latheShell(axis, e1, e2, rings, m, scale, faces, tag)
		local verts = {}
		local nr = #rings
		for i = 1, nr do
			local t, rho = rings[i][1], rings[i][2]
			local list = {}
			if rho <= 0 then
				list[0] = axis * t
			else
				for j = 0, m - 1 do
					local phi = 2 * pi * j / m
					list[j] = axis * t + (e1 * cos(phi) + e2 * sin(phi)) * rho
				end
			end
			if scale then
				for j, p in pairs(list) do
					list[j] = p * scale
				end
			end
			verts[i] = list
		end
		for i = 1, nr - 1 do
			local A, B = verts[i], verts[i + 1]
			local aPole, bPole = rings[i][2] <= 0, rings[i + 1][2] <= 0
			local term = rings[i][3]
			if not (aPole and bPole) then
				for j = 0, m - 1 do
					local j2 = (j + 1) % m
					local loop
					if aPole then
						loop = {A[0], B[j], B[j2]}
					elseif bPole then
						loop = {A[j], A[j2], B[0]}
					else
						loop = {A[j], A[j2], B[j2], B[j]}
					end
					local f = quickFace(loop, ZERO, term)
					if f then
						faces[#faces + 1] = f
						if tag then
							tag(f, i, j, loop)
						end
					end
				end
			end
		end
		for _, i in ipairs({1, nr}) do
			if rings[i][2] > 0 then
				local cap = tcreate(m)
				for j = 0, m - 1 do
					cap[j + 1] = verts[i][j]
				end
				local f = quickFace(cap, ZERO, nil)
				if f then
					faces[#faces + 1] = f
				end
			end
		end
	end

	-- "Blocky" round parts. The old engine drew balls with 16 x 8 flat facets (and cylinders with 16
	-- sides), so their dark side came in steps, facet by facet. Here each of those classic facets
	-- decides dark or lit for a patch of finer facets that hug the real curve (so nothing floats
	-- off it), and the shadow a ball casts has the classic facets' outline.
	local BLOCKY = CONFIG.RoundShading == "Blocky"
	local CLASSIC_SIDES, CLASSIC_ROWS = 16, 8
	-- Looser than SURFACE_FLOAT further away: those facets are a pixel or less off the curve
	-- there, and every finer facet costs parts.
	local BLOCKY_FLOAT = {0.07, 0.25, 0.5}

	-- How many times finer than the classic facets the drawn ones are.
	local function blockyRefine(R, r, lod, sphere)
		local mrel = max(0.004, 0.012 / max(r, 1e-3))
		local slack = (BLOCKY_FLOAT[lod] or 0.5) / max(R, 1e-3) - mrel
		local want = huge
		if slack > 1e-4 then
			want = 2 * pi / (sqrt(2 * slack) * (sphere and 1.4142 or 2))
		end
		local most = sphere and (meshMode and 3 or 2) or (meshMode and 4 or 2)
		return max(1, min(most, ceil(want / CLASSIC_SIDES - 1e-6))), mrel
	end

	local function unitPoint(th, ph)
		local s = sin(th)
		return V3(s * cos(ph), cos(th), s * sin(ph))
	end

	-- Largest angle between a unit direction and any of `points` (seen from the centre).
	local function angularRadius(dir, points)
		local worst = 1
		for i = 1, #points do
			local c = dir:Dot(points[i].Unit)
			if c < worst then
				worst = c
			end
		end
		return math.acos(max(-1, min(1, worst)))
	end

	local function blockyCylinder(len, r, axisName, lod, offset)
		local q, mrel = blockyRefine(r, r, lod, false)
		local m = CLASSIC_SIDES * q
		return cached(string.format("U%s%.3f,%.3f/%d", axisName, len, r, q), offset, function()
			-- the outline: the classic 16 sides, corners on the curve
			local shape = prism(len, r * cos(pi / CLASSIC_SIDES), CLASSIC_SIDES, axisName, 0)
			local axis, e1, e2 = YAXIS, ZAXIS, XAXIS
			if axisName == "X" then
				axis, e1, e2 = XAXIS, YAXIS, ZAXIS
			end
			local rv = r * (1 + mrel) / cos(pi / m)
			local h = len / 2 + CONFIG.SurfaceOffset
			local faces = {}
			latheShell(axis, e1, e2, {{-h, rv}, {h, rv}}, m, nil, faces, function(f, _, j)
				local phi = 2 * pi * (floor(j / q) + 0.5) / CLASSIC_SIDES
				f.cn = e1 * cos(phi) + e2 * sin(phi)
			end)
			shape.faces = faces
			shape.blocky = true
			return shape
		end)
	end

	local function cylinderShape(len, r, axisName, lod, offset)
		r = max(r, 1e-3)
		if BLOCKY then
			return blockyCylinder(len, r, axisName, lod, offset)
		end
		local segs = outlineSegments(lod)
		local m, mrel = surfaceSegments(r, r, lod, false)
		local key = string.format("%s%.3f,%.3f/%d/%d", axisName, len, r, segs, m)
		return cached(key, offset, function()
			local shape = prism(len, r, segs, axisName)
			local axis, e1, e2 = YAXIS, ZAXIS, XAXIS
			if axisName == "X" then
				axis, e1, e2 = XAXIS, YAXIS, ZAXIS
			end
			-- the round side floats just off the curve; the flat ends float SurfaceOffset like
			-- any flat face, and the side reaches out to meet them
			local rv = r * (1 + mrel) / cos(pi / m)
			local h = len / 2 + CONFIG.SurfaceOffset
			local faces = {}
			latheShell(axis, e1, e2, {{-h, rv, 1}, {h, rv, 1}}, m, nil, faces)
			shape.faces = faces
			shape.terms = {{c = ZERO, axis = axis}}
			return shape
		end)
	end

	function Shapes.cylinderX(size, lod, offset)
		return cylinderShape(size.X, min(size.Y, size.Z) / 2, "X", lod, offset)
	end

	function Shapes.cylinderY(height, diameter, lod, offset)
		return cylinderShape(height, diameter / 2, "Y", lod, offset)
	end

	local function sphereAt(c, r)
		return {c = c, e1 = V3(r, 0, 0), e2 = V3(0, r, 0), e3 = V3(0, 0, r)}
	end

	local function ellipsoidAt(c, radii)
		return {c = c, e1 = V3(radii.X, 0, 0), e2 = V3(0, radii.Y, 0), e3 = V3(0, 0, radii.Z)}
	end

	local MIN_RADII = V3(1e-3, 1e-3, 1e-3)

	-- A classic 16 x 8 ball (see blockyCylinder), stretched to `radii`.
	local function blockyEllipsoid(radii, lod, offset)
		local R, r = max(radii.X, radii.Y, radii.Z), min(radii.X, radii.Y, radii.Z)
		local q, mrel = blockyRefine(R, r, lod, true)
		return cached("Q" .. vkey(radii) .. "/" .. q, offset, function()
			local SIDES, ROWS = CLASSIC_SIDES, CLASSIC_ROWS
			local round = R - r < 1e-4 * R
			-- the classic facets: their outline casts the shadow, their normals decide dark or lit
			local verts = {V3(0, radii.Y, 0), V3(0, -radii.Y, 0)}
			local function vid(i, j)
				if i == 0 then
					return 1
				elseif i == ROWS then
					return 2
				end
				return 3 + (i - 1) * SIDES + j % SIDES
			end
			for i = 1, ROWS - 1 do
				for j = 0, SIDES - 1 do
					verts[vid(i, j)] = unitPoint(pi * i / ROWS, 2 * pi * j / SIDES) * radii
				end
			end
			local loops, cells = {}, {}
			for i = 0, ROWS - 1 do
				for j = 0, SIDES - 1 do
					local loop
					if i == 0 then
						loop = {vid(0, 0), vid(1, j + 1), vid(1, j)}
					elseif i == ROWS - 1 then
						loop = {vid(i, j), vid(i, j + 1), vid(ROWS, 0)}
					else
						loop = {vid(i, j), vid(i, j + 1), vid(i + 1, j + 1), vid(i + 1, j)}
					end
					loops[#loops + 1] = loop
					local pts = {}
					for t = 1, #loop do
						pts[t] = verts[loop[t]]
					end
					local nrm = newellNormal(pts).Unit
					if nrm:Dot(averageOf(pts)) < 0 then
						nrm = -nrm
					end
					local cell = {n = nrm}
					if round then
						-- where it sits on the ball, and how far it reaches from there (radians)
						local t1, t2 = pi * i / ROWS, pi * (i + 1) / ROWS
						local p1, p2 = 2 * pi * j / SIDES, 2 * pi * (j + 1) / SIDES
						cell.d = unitPoint((t1 + t2) / 2, (p1 + p2) / 2)
						cell.r = angularRadius(cell.d, {unitPoint(t1, p1), unitPoint(t1, p2), unitPoint(t2, p1),
							unitPoint(t2, p2), unitPoint(t1, (p1 + p2) / 2), unitPoint(t2, (p1 + p2) / 2)})
					end
					cells[i * SIDES + j + 1] = cell
				end
			end
			local shape = makePolyhedron(verts, loops, true)
			-- the drawn facets: q x q of them per classic facet, just off the curve
			local m, k = SIDES * q, ROWS * q
			local push = (1 + mrel) / sphereClearance(m, k)
			local rings = {}
			for i = 0, k do -- unit sphere, +Y pole to -Y pole
				local th = pi * i / k
				rings[i + 1] = {cos(th) * push, (i == 0 or i == k) and 0 or sin(th) * push}
			end
			local faces = {}
			latheShell(YAXIS, XAXIS, ZAXIS, rings, m, radii, faces, function(f, i, j, loop)
				local cell = cells[floor((i - 1) / q) * SIDES + floor(j / q) + 1]
				f.cn = cell.n
				if round then
					f.cd = f.o.Unit
					f.cr = angularRadius(f.cd, loop)
				end
			end)
			shape.faces = faces
			shape.cells = cells
			shape.blocky = true
			shape.radius = R * push
			-- a round ball's dark middle is drawn by one ball-shaped part (see emitBackFaces)
			shape.core = round and {c = ZERO, r = R} or nil
			return shape
		end)
	end

	function Shapes.ellipsoid(radii, lod, offset)
		radii = radii:Max(MIN_RADII)
		if BLOCKY then
			return blockyEllipsoid(radii, lod, offset)
		end
		local R = max(radii.X, radii.Y, radii.Z)
		local m, mrel = surfaceSegments(R, min(radii.X, radii.Y, radii.Z), lod, true)
		local segs = outlineSegments(lod)
		return cached("E" .. vkey(radii) .. "/" .. segs .. "/" .. m, offset, function()
			local k = max(2, ceil(m / 2))
			local push = (1 + mrel) / sphereClearance(m, k)
			local rings = {}
			for i = 0, k do -- unit sphere, +Y pole to -Y pole
				local th = pi * i / k
				rings[i + 1] = {cos(th) * push, (i == 0 or i == k) and 0 or sin(th) * push, 1}
			end
			local faces = {}
			latheShell(YAXIS, XAXIS, ZAXIS, rings, m, radii, faces)
			return {
				kind = "round",
				segs = segs,
				shade = true,
				ellipsoids = {ellipsoidAt(ZERO, radii)},
				faces = faces,
				terms = {{c = ZERO, rinv2 = V3(1 / (radii.X * radii.X), 1 / (radii.Y * radii.Y), 1 / (radii.Z * radii.Z))}},
				radius = R * push,
			}
		end)
	end

	function Shapes.ball(size, lod)
		local r = min(size.X, size.Y, size.Z) / 2
		return Shapes.ellipsoid(V3(r, r, r), lod)
	end

	-- Facets around a cylinder between two half-ellipsoid ends, along the X or Y axis: a capsule
	-- (round ends) or the classic head (flatter ends). half: half the straight middle, r: radius,
	-- depth: how far each end sticks out past the middle.
	local function cappedShell(axisName, half, r, depth, m, mrel)
		local kh = max(1, ceil(m / 4))
		local p = (1 + mrel) / sphereClearance(m, kh * 2)
		local rings = {}
		for i = 0, kh do -- the negative end, from its pole to its rim
			local th = (pi / 2) * i / kh
			rings[#rings + 1] = {-half - cos(th) * depth * p, i == 0 and 0 or sin(th) * r * p, 2}
		end
		rings[#rings][3] = 3 -- the straight middle
		for i = kh, 0, -1 do -- the positive end, from its rim to its pole
			local th = (pi / 2) * i / kh
			rings[#rings + 1] = {half + cos(th) * depth * p, i == 0 and 0 or sin(th) * r * p, 1}
		end
		local axis, e1, e2 = YAXIS, ZAXIS, XAXIS
		local endInv = V3(1 / (r * r), 1 / (depth * depth), 1 / (r * r))
		if axisName == "X" then
			axis, e1, e2 = XAXIS, YAXIS, ZAXIS
			endInv = V3(1 / (depth * depth), 1 / (r * r), 1 / (r * r))
		end
		local faces = {}
		latheShell(axis, e1, e2, rings, m, nil, faces)
		local terms = {
			{c = axis * half, rinv2 = endInv},
			{c = axis * -half, rinv2 = endInv},
			{c = ZERO, axis = axis},
		}
		return faces, terms, p
	end

	function Shapes.capsule(size, lod)
		local r = min(size.Y, size.Z) / 2
		local half = size.X / 2 - r
		if half < 0.01 then
			return Shapes.ball(size, lod)
		end
		local segs = outlineSegments(lod)
		local m, mrel = surfaceSegments(r, r, lod, true)
		return cached("K" .. vkey(size) .. "/" .. segs .. "/" .. m, nil, function()
			local faces, terms, p = cappedShell("X", half, r, r, m, mrel)
			return {
				kind = "round",
				segs = segs,
				shade = true,
				ellipsoids = {sphereAt(V3(-half, 0, 0), r), sphereAt(V3(half, 0, 0), r)},
				faces = faces,
				terms = terms,
				radius = half + r * p,
			}
		end)
	end

	-- Outline-only shapes (no facets, so no dark sides and nothing drawn on them) for parts whose
	-- exact look isn't known, like avatar parts and hats when their meshes can't be read.
	function Shapes.solidEllipsoid(radii, lod, offset)
		radii = radii:Max(MIN_RADII)
		local segs = outlineSegments(lod)
		return cached("S" .. vkey(radii) .. "/" .. segs, offset, function()
			return {kind = "round", segs = segs, shade = false, ellipsoids = {ellipsoidAt(ZERO, radii)},
				radius = max(radii.X, radii.Y, radii.Z)}
		end)
	end

	-- The classic head: a cylinder with rounded top and bottom. Its real mesh isn't exactly this,
	-- so it gets no dark side of its own, but it does take shadows (a roof's, a hat's) on facets
	-- that fit it closely.
	function Shapes.classicHead(height, diameter, lod, offset)
		local segs = outlineSegments(lod)
		local r, depth = max(diameter * 0.49, 1e-3), max(height * 0.3, 1e-3)
		local half = max(height * 0.5 - depth, 0)
		local m, mrel = surfaceSegments(max(r, depth), min(r, depth), lod, true)
		return cached(string.format("H%.3f,%.3f/%d/%d", height, diameter, segs, m), offset, function()
			local faces, terms = cappedShell("Y", half, r, depth, m, mrel)
			return {
				kind = "round",
				segs = segs,
				shade = false,
				ellipsoids = {ellipsoidAt(V3(0, half, 0), V3(r, depth, r)), ellipsoidAt(V3(0, -half, 0), V3(r, depth, r))},
				faces = faces,
				terms = terms,
				radius = max(r, height * 0.5) * 1.42,
			}
		end)
	end

	-- A block with rounded edges that fills `size`: k sets the rounding (as a fraction of the
	-- smallest side). Used for avatar parts whose mesh can't be read: it keeps each part's real
	-- size and bulk, so the shadow still has the avatar's build.
	local OCTANT = {
		V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1),
		V3(0.7071, 0.7071, 0), V3(0.7071, 0, 0.7071), V3(0, 0.7071, 0.7071),
		V3(0.5774, 0.5774, 0.5774),
	}

	function Shapes.roundedBlock(size, k)
		return cached(string.format("R%s/%.2f", vkey(size), k), nil, function()
			local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
			local rho = min(k * min(size.X, size.Y, size.Z), hx, hy, hz)
			local pts = {}
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = V3(sx * (hx - rho), sy * (hy - rho), sz * (hz - rho))
						for _, d in ipairs(OCTANT) do
							pts[#pts + 1] = c + V3(sx * d.X, sy * d.Y, sz * d.Z) * rho
						end
					end
				end
			end
			return {kind = "mesh", points = pts, shade = false, radius = (size * 0.5).Magnitude}
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
			local triCount = entry.triCount
			if verts and triCount <= CONFIG.ExactMeshTriangles then
				local tv = tcreate(#tris)
				for i = 1, #tris do
					tv[i] = verts[tris[i]] * mul + add
				end
				shape.tris = tv
			end
			if verts and triCount <= CONFIG.MeshReceiverTriangles then
				local faces = {}
				for t = 1, #tris, 3 do
					local A = verts[tris[t]] * mul + add
					local B = verts[tris[t + 1]] * mul + add
					local C = verts[tris[t + 2]] * mul + add
					local nrm = (B - A):Cross(C - A)
					if nrm.Magnitude > 1e-9 then
						local f = makeFace(nrm.Unit, {A, B, C})
						if f then
							growFace(f, nil)
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

	-- Only the outline of real mesh data (avatar parts: cheap to redo every frame, no dark sides).
	function Shapes.fromMeshHull(entry, mul, add)
		return cached("O" .. entry.id .. "|" .. vkey(mul) .. "|" .. vkey(add), nil, function()
			local hull = entry.hull
			local pts = tcreate(#hull)
			for i = 1, #hull do
				pts[i] = hull[i] * mul + add
			end
			return {kind = "mesh", points = pts, shade = false, radius = (mul:Abs() * 0.5).Magnitude + add.Magnitude}
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
			entry.size, entry.center = V3(sx, sy, sz), center
			entry.hull = supportPoints(verts, true)
			entry.triCount = nt / 3
			-- big meshes only ever use their outline points: don't keep all their triangles in memory
			if entry.triCount <= max(CONFIG.ExactMeshTriangles, CONFIG.MeshReceiverTriangles) then
				entry.verts, entry.tris = verts, tris
			end
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

	MeshData.keyOf = meshKey

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
		-- Hits that all land on the faces of one box mean the part only has box collisions (the
		-- usual avatar setting), which says nothing about how the mesh really looks.
		local lo, hi = pts[1], pts[1]
		for i = 2, #pts do
			lo = lo:Min(pts[i])
			hi = hi:Max(pts[i])
		end
		local tol = (hi - lo) * 0.02
		local onBox = 0
		for i = 1, #pts do
			local p = pts[i]
			if p.X - lo.X <= tol.X or hi.X - p.X <= tol.X or p.Y - lo.Y <= tol.Y or hi.Y - p.Y <= tol.Y
				or p.Z - lo.Z <= tol.Z or hi.Z - p.Z <= tol.Z then
				onBox += 1
			end
		end
		local out = supportPoints(pts, false)
		out.boxy = onBox >= #pts * 0.95
		return out
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
-- Avatar outlines. Games rarely let scripts read avatar meshes, and usually give avatars plain box
-- collisions. But any script may create a MeshPart from a mesh with an exact convex-hull collision
-- shape: raycasting such a hidden copy (once per mesh) gives the mesh's real outline.
----------------------------------------------------------------------------------------------------
local MeshProbe = {entries = {}, queue = newQueue(), first = newQueue(), ready = newQueue(), running = false,
	busy = 0, model = nil}
do
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Include
	probeParams.IgnoreWater = true
	local SPOT = CFrame.new(0, 4000, 0) -- far away from everything else

	-- 6 sides, 12 edges, 8 corners: rays come at the copy from all of them
	local DIRS = {}
	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				if x ~= 0 or y ~= 0 or z ~= 0 then
					DIRS[#DIRS + 1] = V3(x, y, z).Unit
				end
			end
		end
	end

	local function probeModel()
		local m = MeshProbe.model
		if m == nil or m.Parent == nil then
			m = Instance.new("Model")
			m.Name = PROBE_NAME
			m.Parent = Workspace
			MeshProbe.model = m
		end
		return m
	end

	-- Points on the copy's surface, normalized to -0.5..0.5 of its size.
	local function sampleCopy(part)
		local cf, size = part.CFrame, part.Size
		probeParams.FilterDescendantsInstances = {part}
		local R = size.Magnitude * 0.5 + 0.5
		local pts = {}
		local G = 7
		local cast = 0
		for _, d in ipairs(DIRS) do
			local p = (abs(d.Y) < 0.9 and YAXIS or XAXIS):Cross(d).Unit
			local q = d:Cross(p)
			for i = 0, G - 1 do
				local s = (i / (G - 1) * 2 - 1) * R
				for j = 0, G - 1 do
					local t = (j / (G - 1) * 2 - 1) * R
					local o = d * (R + 1) + p * s + q * t
					local hit = Workspace:Raycast(cf * o, cf:VectorToWorldSpace(d * -(2 * R + 2)), probeParams)
					if hit then
						local lp = cf:PointToObjectSpace(hit.Position)
						pts[#pts + 1] = V3(lp.X / size.X, lp.Y / size.Y, lp.Z / size.Z)
					end
					cast += 1
					if cast % 500 == 0 then
						task.wait() -- spread over a few frames
					end
				end
			end
		end
		if #pts < 4 then
			return nil
		end
		return supportPoints(pts, true)
	end

	local function probe(entry)
		local part = AssetService:CreateMeshPartAsync(entry.content, {
			CollisionFidelity = Enum.CollisionFidelity.Hull,
			RenderFidelity = Enum.RenderFidelity.Performance,
		})
		if not part then
			error("no MeshPart returned", 0)
		end
		local ok, err = pcall(function()
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = true
			part.CastShadow = false
			part.Transparency = 1
			part.CFrame = SPOT
			entry.size = part.Size
			part.Parent = probeModel()
			entry.pts = sampleCopy(part)
		end)
		pcall(part.Destroy, part)
		if not ok then
			error(err, 0)
		end
		if not entry.pts then
			error("the copy had no collision shape", 0)
		end
	end

	local function loader()
		while alive do
			-- your own character's meshes go first
			local entry = qpop(MeshProbe.first) or qpop(MeshProbe.queue)
			if not entry then
				break
			end
			entry.status = "loading"
			local ok = pcall(probe, entry)
			entry.status = ok and "ready" or "dead"
			MeshProbe.busy -= 1
			qpush(MeshProbe.ready, entry)
			task.wait()
		end
		MeshProbe.running = false
	end

	-- The outline entry for a mesh (nil when it can't be had); `state` is redrawn when it's done.
	function MeshProbe.get(content, state)
		if not CONFIG.AvatarOutlines then
			return nil
		end
		local key = MeshData.keyOf(content)
		if type(key) ~= "string" then
			return nil
		end
		local entry = MeshProbe.entries[key]
		if not entry then
			entry = {key = key, content = content, status = "queued", users = setmetatable({}, {__mode = "k"})}
			MeshProbe.entries[key] = entry
			MeshProbe.busy += 1
			local info = state and state.charInfo
			qpush((info and info.isLocal) and MeshProbe.first or MeshProbe.queue, entry)
			if not MeshProbe.running and alive then
				MeshProbe.running = true
				task.spawn(loader)
			end
		end
		if state then
			state.probe = entry
			if entry.status ~= "ready" and entry.status ~= "dead" then
				entry.users[state] = true
			end
		end
		return entry
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

	-- Avatar parts whose mesh can't be read become blocks with rounded edges that fill the part
	-- (so the shadow keeps the avatar's real build). How round, as a fraction of the smallest side:
	-- limbs are nearly round across, torsos are boxier.
	local BODY_ROUNDING = {
		Head = 0.42, UpperTorso = 0.24, LowerTorso = 0.24, Torso = 0.2,
		LeftUpperArm = 0.42, RightUpperArm = 0.42, LeftLowerArm = 0.44, RightLowerArm = 0.44,
		LeftHand = 0.45, RightHand = 0.45,
		LeftUpperLeg = 0.4, RightUpperLeg = 0.4, LeftLowerLeg = 0.42, RightLowerLeg = 0.42,
		LeftFoot = 0.4, RightFoot = 0.4,
		["Left Arm"] = 0.4, ["Right Arm"] = 0.4, ["Left Leg"] = 0.38, ["Right Leg"] = 0.38,
	}
	-- R15 body part -> the HumanoidDescription field that says which body is worn there
	local DESC_FIELD = {
		UpperTorso = "Torso", LowerTorso = "Torso",
		LeftUpperArm = "LeftArm", LeftLowerArm = "LeftArm", LeftHand = "LeftArm",
		RightUpperArm = "RightArm", RightLowerArm = "RightArm", RightHand = "RightArm",
		LeftUpperLeg = "LeftLeg", LeftLowerLeg = "LeftLeg", LeftFoot = "LeftLeg",
		RightUpperLeg = "RightLeg", RightLowerLeg = "RightLeg", RightFoot = "RightLeg",
	}
	-- R6 body part -> the CharacterMesh body part that swaps its block for a package mesh
	local R6_MESH = {
		Torso = "Torso", ["Left Arm"] = "LeftArm", ["Right Arm"] = "RightArm",
		["Left Leg"] = "LeftLeg", ["Right Leg"] = "RightLeg",
	}

	local function fallbackMeshShape(state, size, offset, lod)
		if state.character then
			-- a hat, hair or tool mesh that can't be read: a smooth blob filling most of it
			return Shapes.solidEllipsoid(size * 0.47, lod, offset)
		end
		if CONFIG.MissingMeshFallback == "Box" then
			return Shapes.box(size, offset)
		end
		return nil
	end

	local function rayKey(part, content)
		local uri = content and content.Uri
		return (uri and uri ~= "") and (uri .. "|" .. tostring(part.CollisionFidelity)) or nil
	end

	-- A MeshPart of a character: body part, hat, hair or tool. Its shadow is the real outline of
	-- its mesh whenever that can be had; dark sides and shadows on it come from mesh copies (see
	-- BodyShade), so nothing ever sticks out of the avatar.
	local function avatarMeshShape(state, part, size, lod)
		local name = part.Name
		local info = state.charInfo
		local field = DESC_FIELD[name]
		state.polyReceive = nil
		if field and info and info.blocky and info.blocky[field] then
			state.shadeKind = nil -- exact faces take shadows the normal way
			return Shapes.box(size) -- the default blocky body: these parts really are boxes
		end
		-- body parts, hair and hats: dark sides and shade from copies of their real mesh
		state.shadeKind = "mesh"
		local content = part.MeshContent
		-- 1. the real mesh, when the game lets meshes be read
		local entry = MeshData.allowed and MeshData.get(content) or nil
		if entry then
			if entry.status == "ready" then
				return Shapes.fromMeshHull(entry, size, ZERO)
			end
			waitForMesh(entry, state) -- redrawn when it arrives
		end
		-- 2. a hidden copy of the mesh with an exact hull collision shape, raycast once per mesh
		local probe = MeshProbe.get(content, state)
		if probe and probe.status == "ready" then
			return Shapes.fromPoints("h" .. probe.key, probe.pts, size, ZERO, false)
		end
		-- 3. the avatar's own collision shape, unless that's just a box (it usually is)
		if CONFIG.RaySampleMeshes and (probe == nil or probe.status == "dead") then
			local key = rayKey(part, content)
			local pts, busy = RaySample.get(part, key)
			if pts and not pts.boxy then
				return Shapes.fromPoints(key or ("i" .. state.id), pts, size, ZERO, false)
			elseif busy then
				return nil, true
			end
		end
		-- 4. a stand-in with the part's real size (until the outline arrives, or if it never can)
		if state.accessory then
			return Shapes.solidEllipsoid(size * 0.47, lod)
		end
		return Shapes.roundedBlock(size, BODY_ROUNDING[name] or 0.3)
	end

	-- Character Parts that aren't the plain blocks they look like: the classic head, and R6 limbs
	-- dressed in a package mesh (CharacterMesh). nil = use the normal (exact) rules.
	local function avatarPartShape(state, part, size, lod)
		local name = part.Name
		state.charMesh = nil
		state.shadeKind = nil
		state.polyReceive = nil
		if name == "Head" then
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh and mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.Head then
				-- shadows land on it as polygons; its dark side comes from a copy (see BodyShade)
				state.shadeKind = "part"
				state.polyReceive = true
				local scale = mesh.Scale
				return Shapes.classicHead(size.Y * scale.Y, min(size.X, size.Y, size.Z) * scale.X, lod, mesh.Offset)
			end
		end
		local info = state.charInfo
		local bodyPart = R6_MESH[name]
		local meshId = bodyPart and info and info.charMeshes and info.charMeshes[bodyPart]
		if meshId then
			-- the package mesh is drawn at its own size, centred on the limb
			state.charMesh = meshId
			state.shadeKind = "charmesh"
			local okContent, content = pcall(Content.fromUri, "rbxassetid://" .. tostring(meshId))
			local probe = okContent and MeshProbe.get(content, state) or nil
			if probe and probe.status == "ready" then
				return Shapes.fromPoints("h" .. probe.key, probe.pts, probe.size, ZERO, false)
			end
			return Shapes.roundedBlock(size, BODY_ROUNDING[name] or 0.35)
		end
		return nil
	end

	local function meshPartShape(state, part, size, lod)
		if state.character then
			return avatarMeshShape(state, part, size, lod)
		end
		local content = part.MeshContent
		local entry = MeshData.get(content)
		if entry then
			if entry.status == "ready" then
				return Shapes.fromMesh(entry, size, ZERO)
			elseif waitForMesh(entry, state) then
				return nil, true
			end
		end
		if CONFIG.RaySampleMeshes then
			local key = rayKey(part, content)
			local pts, busy = RaySample.get(part, key)
			if pts then
				return Shapes.fromPoints(key or ("i" .. state.id), pts, size, ZERO, true)
			elseif busy then
				return nil, true
			end
		end
		return fallbackMeshShape(state, size, nil, lod)
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

	local function specialMeshShape(state, mesh, size, lod)
		local scale, offset = mesh.Scale, mesh.Offset
		if mesh:IsA("SpecialMesh") then
			local meshType = mesh.MeshType
			if meshType == Enum.MeshType.FileMesh then
				local character = state.character
				local entry = (not character or MeshData.allowed) and MeshData.get(mesh.MeshContent) or nil
				if entry then
					if entry.status == "ready" then
						local mul, add = entry.size * scale, entry.center * scale + offset
						if character then
							return Shapes.fromMeshHull(entry, mul, add)
						end
						return Shapes.fromMesh(entry, mul, add)
					elseif waitForMesh(entry, state) and not character then
						return nil, true
					end
				end
				if character then
					-- a classic hat or package head: the outline of its mesh, at the mesh's own size,
					-- and its shading from copies of it (see BodyShade)
					state.shadeKind = "part"
					local probe = MeshProbe.get(mesh.MeshContent, state)
					if probe and probe.status == "ready" then
						return Shapes.fromPoints("h" .. probe.key, probe.pts, probe.size * scale, offset, false)
					end
				end
				return fallbackMeshShape(state, size * scale, offset, lod)
			elseif meshType == Enum.MeshType.Sphere then
				return Shapes.ellipsoid(size * scale * 0.5, lod, offset)
			elseif meshType == Enum.MeshType.Cylinder then
				return Shapes.cylinderY(size.Y * scale.Y, min(size.X * scale.X, size.Z * scale.Z), lod, offset)
			elseif meshType == Enum.MeshType.Head then
				return Shapes.cylinderY(size.Y * scale.Y, min(size.X, size.Y, size.Z) * scale.X, lod, offset)
			elseif meshType == Enum.MeshType.Wedge then
				return Shapes.wedge(size * scale, offset)
			elseif meshType == Enum.MeshType.CornerWedge then
				return Shapes.cornerWedge(size * scale, offset)
			end
			return Shapes.box(size * scale, offset)
		elseif mesh:IsA("CylinderMesh") then
			return Shapes.cylinderY(size.Y * scale.Y, min(size.X * scale.X, size.Z * scale.Z), lod, offset)
		end
		return Shapes.box(size * scale, offset)
	end

	local function resolveShape(state, lod)
		local part = state.part
		local size = part.Size
		if part:IsA("MeshPart") then
			return meshPartShape(state, part, size, lod)
		elseif part:IsA("PartOperation") then
			return unionShape(state, part, size)
		end
		local className = part.ClassName
		if className == "WedgePart" then
			return Shapes.wedge(size)
		elseif className == "CornerWedgePart" then
			return Shapes.cornerWedge(size)
		elseif part:IsA("Part") then
			if state.character then
				local s = avatarPartShape(state, part, size, lod)
				if s then
					return s
				end
			end
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh then
				return specialMeshShape(state, mesh, size, lod)
			end
			local shape = part.Shape
			if shape == Enum.PartType.Ball then
				return Shapes.ball(size, lod)
			elseif shape == Enum.PartType.Cylinder then
				return Shapes.cylinderX(size, lod)
			elseif shape == Enum.PartType.Wedge then
				return Shapes.wedge(size)
			elseif shape == Enum.PartType.CornerWedge then
				return Shapes.cornerWedge(size)
			elseif PART_CAPSULE and shape == PART_CAPSULE then
				return Shapes.capsule(size, lod)
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
			if shape.tris and lod == 1 and CONFIG.RenderStyle ~= "Direct" then
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
	local function buildWorldFace(lf, cf, wf, lift)
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
		lift = lf.lift or lift
		wf.lift = lift
		local grown = grownFace(lf, lift)
		local xs, ys = grown.xs, grown.ys
		local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
		for i = 1, grown.count do
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
		if state.wfShape == shape and state.wfLight == Light.version then
			-- moving parts: once per frame; still parts: until they move (round parts have many faces)
			if state.dynamic then
				if state.wfFrame == frameId then
					return state.wf
				end
			elseif state.wfCf == state.cfVersion then
				return state.wf
			end
		end
		local list = state.wf or {}
		local faces = shape.faces
		local cf = state.part.CFrame
		-- characters are seen up close: their shadows sit tighter on them
		local lift = state.character and CONFIG.CharacterSurfaceOffset or CONFIG.SurfaceOffset
		local dl = shape.blocky and cf:VectorToObjectSpace(Light.dir)
		for i = 1, #faces do
			local lf = faces[i]
			local wf = buildWorldFace(lf, cf, list[i] or {}, lift)
			list[i] = wf
			if dl and lf.cn and lf.cn:Dot(dl) < MIN_LIT then
				-- part of a dark classic facet: drawn dark already, no shadows go on it
				wf.s = -1
			end
		end
		for i = #list, #faces + 1, -1 do
			list[i] = nil
		end
		state.wf, state.wfFrame, state.wfShape, state.wfLight, state.wfCf = list, frameId, shape, Light.version, state.cfVersion
		return list
	end
end

----------------------------------------------------------------------------------------------------
-- Output: the shadow polygons produced by one job (world space)
----------------------------------------------------------------------------------------------------
local Lamps = {active = false, rec = nil}
local Out = {pts = {}, sizes = {}, tints = {}, np = 0, nPoly = 0, cores = {}, nCores = 0}

do
	function resetOut()
		Out.np = 0
		Out.nPoly = 0
		Out.nCores = 0
	end

	-- The dark middle of a round ball, drawn as one ball-shaped part (see emitBackFaces): centre c,
	-- radius r, `a` the way to the dark side, k = 1 - cos(how far from `a` it reaches).
	function emitCore(c, a, r, k)
		local n = Out.nCores + 1
		Out.nCores = n
		local t = Out.cores[n]
		if not t then
			t = {}
			Out.cores[n] = t
		end
		t.c, t.a, t.r, t.k = c, a, r, k
	end

	-- A polygon in a face's 2D coordinates, lifted slightly off the face (facets of round parts
	-- already float off the curve: lift 0). tint "dim": the lighter ring around a lamp's light.
	local function emitRaw(wf, xs, ys, n, tint)
		local o = wf.o + wf.n * wf.lift
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

	emitPlain = emitRaw

	function emitFace(wf, xs, ys, n, tint)
		if Lamps.active and not tint and Lamps.carve(wf, xs, ys, n, emitRaw) then
			return -- lamps light some of it up (see Lamps)
		end
		emitRaw(wf, xs, ys, n, tint)
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
		-- cut to the face, grown past its edges so shadows on neighbouring faces meet
		local grown = grownFace(lf, wf.lift)
		local n, xs, ys = clipByLines(PX, PY, count, grown.lines, grown.nLines)
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
			if kind == "mesh" and not g.tris then
				-- an outline point cloud (convex): where it crosses the surface is the hull of the
				-- crossings of every line between a point in front and a point behind (so a foot
				-- that sinks a little into the floor still casts right up to it)
				local behind, nb = SH, 0
				for i = 1, n do
					if DD[i] < -CONTACT then
						nb += 1
						behind[nb] = i
					end
				end
				local stepB = max(1, ceil(nb * (m + 1) / 600)) -- keeps it to a few hundred pairs
				for i = 1, n do
					local di = DD[i]
					if di > CONTACT then
						local front = pts[i]
						for k = 1, nb, stepB do
							local j = behind[k]
							local p = front:Lerp(pts[j], di / (di - DD[j]))
							local rx, ry, rz = p.X - ox, p.Y - oy, p.Z - oz
							m += 1
							SX[m] = rx * ux + ry * uy + rz * uz
							SY[m] = rx * vx + ry * vy + rz * vz
						end
					end
				end
			elseif kind == "poly" then
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
local Render = {meshOk = false, batch = false, layers = {}, lastSweep = 0, cores = {}, camPos = Vector3.zero}
local BodyShade = {}
local Silhouette = {holder = nil}
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
		local layer = {name = name, model = model, transparency = transparency, material = material, color = color,
			pool = {}, blockPool = {}, orbPool = {}}
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

	-- kind "w": a WedgePart (half of a triangle), kind "b": a thin block (a whole rectangle),
	-- kind "o": a ball (the dark middle of a round ball)
	local function poolOf(layer, kind)
		return kind == "b" and layer.blockPool or (kind == "o" and layer.orbPool or layer.pool)
	end

	local function acquirePart(layer, kind)
		local pool = poolOf(layer, kind)
		local w = pool[#pool]
		if w then
			pool[#pool] = nil
		else
			w = Instance.new(kind == "w" and "WedgePart" or "Part")
			w.Name = kind == "b" and "ShadowQuad" or (kind == "o" and "ShadowCore" or "ShadowTri")
			if kind == "o" then
				w.Shape = Enum.PartType.Ball
			end
			styleShadowPart(w, layer)
			stats.wedges += 1
		end
		w.Parent = layer.model
		return w
	end

	local function releasePart(layer, kind, w)
		local pool = poolOf(layer, kind)
		if kind == "o" then
			Render.cores[w] = nil
		end
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

	-- One wedge for a right-angled triangle: right angle at P, Q and R the other two corners.
	local function placeRight(w, P, Q, R)
		local back, up = P - Q, R - P
		local d, h = back.Magnitude, up.Magnitude
		if d < 1e-6 or h < 1e-6 then
			return false
		end
		back /= d
		up /= h
		w.Size = V3(WEDGE_THICKNESS, h, d)
		w.CFrame = CFrame.fromMatrix((Q + R) * 0.5, up:Cross(back), up, back)
		return true
	end

	-- A 4-point polygon with two parallel sides (p1p2 and p4p3): a rectangle with a right-angled
	-- triangle at either end, or nil. Returns the rectangle (CFrame, X size, Z size) and the two
	-- triangles as {P, Q, R} lists (right angle at P; either may be false).
	local TRAP_L, TRAP_R = {}, {}
	local function trapezoidOf(p1, p2, p3, p4)
		local e = p2 - p1
		local a2 = e.Magnitude
		if a2 < 1e-4 then
			return nil
		end
		e /= a2
		local top = p3 - p4
		local tl = top.Magnitude
		if tl < 1e-4 or e:Cross(top).Magnitude > 1e-4 * tl or e:Dot(top) < 0 then
			return nil
		end
		local s4 = p4 - p1
		local a4 = s4:Dot(e)
		local hv = s4 - e * a4
		local H = hv.Magnitude
		if H < 1e-4 then
			return nil
		end
		hv /= H
		local a3 = (p3 - p1):Dot(e)
		local lo, hi = max(0, a4), min(a2, a3)
		if hi - lo < 1e-4 then
			return nil
		end
		local left, right = false, false
		if a4 > 1e-5 then
			TRAP_L[1], TRAP_L[2], TRAP_L[3] = p1 + e * a4, p1, p4
			left = TRAP_L
		elseif a4 < -1e-5 then
			TRAP_L[1], TRAP_L[2], TRAP_L[3] = p4 - e * a4, p4, p1
			left = TRAP_L
		end
		if a3 < a2 - 1e-5 then
			TRAP_R[1], TRAP_R[2], TRAP_R[3] = p1 + e * a3, p2, p3
			right = TRAP_R
		elseif a3 > a2 + 1e-5 then
			TRAP_R[1], TRAP_R[2], TRAP_R[3] = p3 - e * (a3 - a2), p3, p2
			right = TRAP_R
		end
		local center = p1 + e * ((lo + hi) * 0.5) + hv * (H * 0.5)
		return CFrame.fromMatrix(center, e, e:Cross(hv)), hi - lo, H, left, right
	end

	-- A 4-point polygon that is a rectangle: its CFrame (X along the first edge, Y = normal) and size.
	local function rectangleOf(p1, p2, p3, p4)
		local e1, e2 = p2 - p1, p4 - p1
		local l1, l2 = e1.Magnitude, e2.Magnitude
		if l1 < 1e-4 or l2 < 1e-4 or abs(e1:Dot(e2)) > 1e-4 * l1 * l2 then
			return nil
		end
		if (p1 + e1 + e2 - p3).Magnitude > 1e-4 * (l1 + l2) then
			return nil
		end
		return CFrame.fromMatrix((p1 + p3) * 0.5, e1 / l1, e1:Cross(e2) / (l1 * l2)), l1, l2
	end

	local function partList(rec, layer, kind)
		local parts = rec.parts
		if not parts then
			parts = {}
			rec.parts = parts
		end
		local key = layer.name .. kind
		local list = parts[key]
		if not list then
			list = {layer = layer, kind = kind}
			parts[key] = list
		end
		return list
	end

	-- polys: {start, count, start, count, ...} into pts; colors: one Color3 per polygon or nil.
	-- Rectangles become one thin block, everything else two wedges per triangle.
	local function commitParts(rec, layer, pts, polys, colors)
		if #polys == 0 and not rec.parts then
			return
		end
		local wl, bl = partList(rec, layer, "w"), partList(rec, layer, "b")
		local nw, nb = 0, 0
		for i = 1, #polys - 1, 2 do
			local s, k = polys[i], polys[i + 1]
			local color = colors and colors[(i + 1) / 2]
			local placed = false
			if k == 4 then
				local p1, p2, p3, p4 = pts[s], pts[s + 1], pts[s + 2], pts[s + 3]
				local cf, sx, sz = rectangleOf(p1, p2, p3, p4)
				local left, right = false, false
				if not cf then
					-- a trapezoid (like the facets of a ball): one block and two wedges, not four
					cf, sx, sz, left, right = trapezoidOf(p1, p2, p3, p4)
					if not cf then
						cf, sx, sz, left, right = trapezoidOf(p2, p3, p4, p1)
					end
				end
				if cf then
					local b = bl[nb + 1]
					if not b then
						b = acquirePart(layer, "b")
						bl[nb + 1] = b
					end
					b.Size = V3(sx, WEDGE_THICKNESS, sz)
					b.CFrame = cf
					if color then
						b.Color = color
					end
					nb += 1
					for _, tri in ipairs({left, right}) do
						if tri then
							local w = wl[nw + 1]
							if not w then
								w = acquirePart(layer, "w")
								wl[nw + 1] = w
							end
							if placeRight(w, tri[1], tri[2], tri[3]) then
								if color then
									w.Color = color
								end
								nw += 1
							end
						end
					end
					placed = true
				end
			end
			if not placed then
				for j = 1, k - 2 do
					local w1 = wl[nw + 1]
					if not w1 then
						w1 = acquirePart(layer, "w")
						wl[nw + 1] = w1
					end
					local w2 = wl[nw + 2]
					if not w2 then
						w2 = acquirePart(layer, "w")
						wl[nw + 2] = w2
					end
					if placeTriangle(w1, w2, pts[s], pts[s + j], pts[s + j + 1]) then
						if color then
							w1.Color = color
							w2.Color = color
						end
						nw += 2
					end
				end
			end
		end
		for i = #wl, nw + 1, -1 do
			releasePart(layer, "w", wl[i])
			wl[i] = nil
		end
		for i = #bl, nb + 1, -1 do
			releasePart(layer, "b", bl[i])
			bl[i] = nil
		end
	end

	-- Binning: each mesh page covers one grid cell; big polygons are cut along cell borders.
	local cellBatches = {}
	local cellOrder = {}
	local commitRec, commitPool = nil, nil
	local fallbackPts, fallbackPolys = {}, {}   -- polygons that couldn't go into a mesh page
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
				meshMode = false
				stats.backend = "Parts"
				destroyPage(pg)
				rebuildRequested = true
			end
		end
		if not done then
			local s = 1
			for p = 1, batch.n do
				local k = batch.sizes[p]
				local base = #fallbackPts
				for j = 0, k - 1 do
					fallbackPts[base + j + 1] = batch.pts[s + j]
				end
				fallbackPolys[#fallbackPolys + 1] = base + 1
				fallbackPolys[#fallbackPolys + 1] = k
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

	local NO_POLYS = {}

	-- A core ball pokes out of the real ball by `h` in the middle of its dark side and meets it
	-- exactly where the classic facets' steps begin (see emitBackFaces). Further away, `h` grows,
	-- so the two never fight over the same pixels.
	local function fitCore(part, info, camPos)
		local R, k = info.r, info.k
		local h = min(0.02 + (info.c - camPos).Magnitude * 0.0004, R * 0.1)
		local d = h * (h + 2 * R) / (2 * R * k + 2 * h)
		local r2 = 2 * (R + h - d)
		part.Size = V3(r2, r2, r2)
		part.CFrame = CFrame.new(info.c + info.a * d)
		info.h = h
	end

	local function commitCores(rec, layer, out)
		local n = out.nCores
		local parts = rec.parts
		if n == 0 and not (parts and parts[layer.name .. "o"]) then
			return
		end
		local list = partList(rec, layer, "o")
		local camPos = Render.camPos
		for i = 1, n do
			local part = list[i]
			if not part then
				part = acquirePart(layer, "o")
				list[i] = part
			end
			local src = out.cores[i]
			local info = Render.cores[part] or {}
			info.c, info.a, info.r, info.k = src.c, src.a, src.r, src.k
			Render.cores[part] = info
			fitCore(part, info, camPos)
		end
		for i = #list, n + 1, -1 do
			releasePart(layer, "o", list[i])
			list[i] = nil
		end
	end

	-- Keeps every core's bulge right for how far away the camera is now.
	function Render.updateCores(camPos)
		Render.camPos = camPos
		for part, info in pairs(Render.cores) do
			local want = min(0.02 + (info.c - camPos).Magnitude * 0.0004, info.r * 0.1)
			if abs(want - info.h) > 0.2 * info.h then
				fitCore(part, info, camPos)
			end
		end
	end

	-- Replaces everything a record drew with the polygons in `out`.
	function Render.commit(rec, out, pool)
		releaseMesh(rec)
		local nPoly = out.nPoly
		local pts, sizes, tints = out.pts, out.sizes, out.tints
		local mainPolys, tintPolys, tintColors, dimPolys = {}, nil, nil, nil
		commitRec, commitPool = rec, pool
		table.clear(fallbackPts)
		table.clear(fallbackPolys)
		local s = 1
		local useMesh = Render.meshOk
		for p = 1, nPoly do
			local k = sizes[p]
			local tint = tints[p]
			if tint == "dim" then
				dimPolys = dimPolys or {}
				dimPolys[#dimPolys + 1] = s
				dimPolys[#dimPolys + 1] = k
			elseif tint then
				tintPolys = tintPolys or {}
				tintColors = tintColors or {}
				tintPolys[#tintPolys + 1] = s
				tintPolys[#tintPolys + 1] = k
				tintColors[#tintColors + 1] = tint
			elseif useMesh then
				binPolygon(pts, s, k)
			else
				mainPolys[#mainPolys + 1] = s
				mainPolys[#mainPolys + 1] = k
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
			commitParts(rec, Render.layers.main, fallbackPts, fallbackPolys, nil)
		else
			commitParts(rec, Render.layers.main, pts, mainPolys, nil)
		end
		commitParts(rec, Render.layers.tint, pts, tintPolys or NO_POLYS, tintColors)
		if Render.layers.dim then
			commitParts(rec, Render.layers.dim, pts, dimPolys or NO_POLYS, nil)
		end
		commitCores(rec, Render.layers.main, out)
		commitRec = nil
	end

	function Render.clear(rec)
		releaseMesh(rec)
		local parts = rec.parts
		if parts then
			for _, list in pairs(parts) do
				for i = #list, 1, -1 do
					releasePart(list.layer, list.kind, list[i])
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

	-- A copy of an avatar part, darkened by the Highlight like any shadow (see BodyShade).
	function Render.styleShade(part)
		styleShadowPart(part, Render.layers.main)
	end

	function Render.setVisible(on)
		on = on and not holdHidden
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
		if CONFIG.DynamicLights then
			-- the lighter ring around a lamp's light: half as dark as a shadow
			local layer = makeLayer("dim", LIT_CONTAINER_NAME, not direct,
				direct and (1 - (1 - CONFIG.DirectTransparency) * 0.5) or 0.999, Enum.Material.Neon, CONFIG.ShadowColor)
			local hl = layer.model:FindFirstChildOfClass("Highlight")
			if hl then
				hl.FillTransparency = 1 - (1 - CONFIG.ShadowTransparency) * 0.5
			end
		end
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
				meshMode = true
				stats.backend = "EditableMesh"
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
			for _, pool in ipairs({layer.pool, layer.blockPool, layer.orbPool}) do
				for _, w in ipairs(pool) do
					pcall(w.Destroy, w)
				end
				table.clear(pool)
			end
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

	-- Which round surfaces get their dark side drawn. Cylinder sides are cheap even with parts
	-- (each facet is one thin block); ball-like surfaces need many triangles, so with parts they
	-- keep Roblox's own shading unless CurvedShading is true.
	local function curvedShading(term)
		if CONFIG.RoundShading == false then
			return false
		end
		return term.axis ~= nil or Render.meshOk
	end

	local sunParams = RaycastParams.new()
	sunParams.FilterType = Enum.RaycastFilterType.Exclude
	sunParams.IgnoreWater = true
	local sunSkip = {}

	-- The still shadow caster between this point and the light, if any (sunParams set by the caller).
	local function sunBlocker(origin)
		local dir = Light.dir
		local len = CONFIG.MaxShadowLength
		for _ = 1, 4 do
			local hit = Workspace:Raycast(origin, dir * len, sunParams)
			if not hit then
				return nil
			end
			local st = states[hit.Instance]
			if st and st.isCaster and not st.dead and not st.dynamic and not st.character then
				return st
			end
			local step = hit.Distance + 0.05
			len -= step
			if len <= 0 then
				return nil
			end
			origin += dir * step
		end
		return nil
	end

	local CORE_EDGE = rad(6) -- facets are still drawn this far inside the core's edge
	local arccos = math.acos

	-- Blocky round parts (see blockyEllipsoid): each classic facet is dark or lit as a whole, so
	-- the dark side ends in steps. A round ball's dark middle (everything up to the nearest lit
	-- classic facet) is one ball-shaped part that pokes out of it a hair; facets do the rest.
	local function emitBlocky(state, shape, faces, rec)
		local cf = state.part.CFrame
		local dl = cf:VectorToObjectSpace(Light.dir)
		local core, a, reach = shape.core, -dl, nil
		if core and CONFIG.RenderStyle ~= "Direct" then
			local nearest = pi
			for _, cell in ipairs(shape.cells) do
				if cell.n:Dot(dl) >= MIN_LIT then
					local ang = arccos(max(-1, min(1, cell.d:Dot(a)))) - cell.r
					if ang < nearest then
						nearest = ang
					end
				end
			end
			local theta0 = nearest - rad(1)
			if theta0 > rad(35) then
				emitCore(cf * core.c, cf:VectorToWorldSpace(a), core.r, 1 - cos(theta0))
				reach = theta0 - CORE_EDGE
			end
		end
		local filterSet = false
		for i = 1, #faces do
			local wf = faces[i]
			local lf = wf.lf
			local cn = lf.cn
			if cn then
				if cn:Dot(dl) < MIN_LIT then
					if not (reach and reach > lf.cr and lf.cd:Dot(a) > cos(reach - lf.cr)) then
						emitFace(wf, lf.xs, lf.ys, lf.count, false)
					end
				elseif wf.s < MIN_LIT and rec and not state.dynamic then
					-- a lit classic facet where the real curve already turns from the light: shadows
					-- can't be cast onto it, so look for something in the way of the light directly
					if not filterSet then
						filterSet = true
						sunSkip[1], sunSkip[2], sunSkip[3] = state.part, Render.layers.main.model, Render.layers.tint.model
						sunParams.FilterDescendantsInstances = sunSkip
					end
					local blocker = sunBlocker(wf.o + wf.n * 0.05)
					if blocker then
						emitFace(wf, lf.xs, lf.ys, lf.count, false)
						-- redraw when that blocker moves or goes
						local deps = blocker.dependents
						if not deps then
							deps = {}
							blocker.dependents = deps
						end
						if not deps[rec] then
							deps[rec] = true
							local touched = rec.receivers
							if not touched then
								touched = {}
								rec.receivers = touched
							end
							touched[#touched + 1] = blocker
						end
					end
				end
			elseif wf.s < MIN_LIT then
				local grown = grownFace(lf, wf.lift)
				emitFace(wf, grown.xs, grown.ys, grown.count, false)
			end
		end
	end

	local DX, DY = {}, {}
	-- The sides of a part that face away from the light are inside its own shadow volume.
	local function emitBackFaces(state, shape, rec)
		local faces = getWorldFaces(state, shape)
		if shape.blocky then
			emitBlocky(state, shape, faces, rec)
			return
		end
		local terms = shape.terms
		local planes = nil
		if terms then
			-- where each round surface turns away from the light: a plane through its centre
			planes = {}
			local cf = state.part.CFrame
			local dl = cf:VectorToObjectSpace(Light.dir)
			for i, t in ipairs(terms) do
				if curvedShading(t) then
					local nl = t.axis and (dl - t.axis * t.axis:Dot(dl)) or dl * t.rinv2
					planes[i] = {cf * t.c, cf:VectorToWorldSpace(nl)}
				else
					planes[i] = false
				end
			end
		end
		for i = 1, #faces do
			local wf = faces[i]
			local lf = wf.lf
			local ti = lf.term
			if ti then
				local plane = planes and planes[ti]
				if plane then
					-- cut the facet exactly where the real curve turns away (a smooth edge)
					local nw = plane[2]
					local A, B, C = wf.u:Dot(nw), wf.v:Dot(nw), (wf.o - plane[1]):Dot(nw)
					local xs, ys, cnt = lf.xs, lf.ys, lf.count
					local lit = 0
					for k = 1, cnt do
						if A * xs[k] + B * ys[k] + C >= 0 then
							lit += 1
						end
					end
					if lit == 0 then
						emitFace(wf, xs, ys, cnt, false)
					elseif lit < cnt then
						local n = clipLine(xs, ys, cnt, -A, -B, -C, DX, DY)
						if n >= 3 and polyArea(DX, DY, n) > MIN_AREA then
							emitFace(wf, DX, DY, n, false)
						end
					end
				end
			elseif wf.s < MIN_LIT then
				local grown = grownFace(lf, wf.lift)
				emitFace(wf, grown.xs, grown.ys, grown.count, false)
			end
		end
	end

	local GEOMS = {}

	------------------------------------------------------------------------------------------------
	-- "Direct" style: shadows are plain see-through parts, so where two overlap they'd be darker.
	-- Every shadow polygon on a face has the shadows that come before it on that face cut out of
	-- it (still parts in a fixed order, then moving ones): the face ends up shaded once.
	------------------------------------------------------------------------------------------------
	local DIRECT = CONFIG.RenderStyle == "Direct"
	local UX, UY, VX, VY = {}, {}, {}, {}
	local PLANES = {}          -- this record's polygons so far, per plane (cleared per record)
	local function ALWAYS_FIRST()
		return true
	end

	-- Polygons Out holds from index `from` on, taken back out, in the face's 2D coordinates:
	-- {xs, ys, n, tint}.
	local function takeOut(wf, from)
		local o = wf.o + wf.n * wf.lift
		local u, v = wf.u, wf.v
		local list = {}
		local start = Out.np + 1
		for k = from, Out.nPoly do
			start -= Out.sizes[k]
		end
		local s = start
		for k = from, Out.nPoly do
			local n = Out.sizes[k]
			local xs, ys = tcreate(n), tcreate(n)
			for i = 1, n do
				local d = Out.pts[s + i - 1] - o
				xs[i], ys[i] = d:Dot(u), d:Dot(v)
			end
			list[#list + 1] = {xs, ys, n, Out.tints[k]}
			s += n
		end
		Out.nPoly = from - 1
		Out.np = start - 1
		return list
	end

	-- P minus a convex Q (both CCW 2D): appends P's pieces outside Q to `out`.
	local function cutAway(xs, ys, n, qx, qy, qn, tint, out)
		local curX, curY, cn = xs, ys, n
		for i = 1, qn do
			local j = i % qn + 1
			local ax, ay, bx, by = qx[i], qy[i], qx[j], qy[j]
			local A, B = -(by - ay), bx - ax
			local C = -(A * ax + B * ay)
			local k = clipLine(curX, curY, cn, -A, -B, -C, UX, UY)
			if k >= 3 and polyArea(UX, UY, k) > MIN_AREA then
				local px, py = tcreate(k), tcreate(k)
				for t = 1, k do
					px[t], py[t] = UX[t], UY[t]
				end
				out[#out + 1] = {px, py, k, tint}
			end
			cn = clipLine(curX, curY, cn, A, B, C, VX, VY)
			if cn < 3 then
				return
			end
			local nx, ny = tcreate(cn), tcreate(cn)
			for t = 1, cn do
				nx[t], ny[t] = VX[t], VY[t]
			end
			curX, curY = nx, ny
		end
	end

	local function ccwPoly(pc)
		if polyArea(pc[1], pc[2], pc[3]) < 0 then
			reversePoly(pc[1], pc[2], pc[3])
		end
	end

	-- The polygons this caster just put on `wf` (Out from `from` on) lose whatever earlier ones
	-- on the same face already cover: `others` (casters that come first) and its own earlier ones.
	-- `first(c)`: does caster c come before this one? `rec` (still records) is redrawn when they move.
	local function unstack(wf, from, receiver, first, lod, rec)
		if Out.nPoly < from then
			return
		end
		-- where these polygons are, seen from the light (only casters over them matter)
		local a, b = Light.a, Light.b
		local x0, x1, y0, y1 = huge, -huge, huge, -huge
		local start = Out.np + 1
		for k = from, Out.nPoly do
			start -= Out.sizes[k]
		end
		for i = start, Out.np do
			local p = Out.pts[i]
			local x, y = p:Dot(a), p:Dot(b)
			x0, x1 = min(x0, x), max(x1, x)
			y0, y1 = min(y0, y), max(y1, y)
		end
		local mine = takeOut(wf, from)
		-- the shadows that come first on this face: still casters between it and the light, over
		-- these polygons (a query around them, so a huge baseplate costs no more than a small part)
		local cover = {}
		local near = queryBox(x0 - MARGIN, x1 + MARGIN, y0 - MARGIN, y1 + MARGIN,
			wf.minZ - CONFIG.MaxShadowLength, wf.maxZ + MARGIN)
		for i = 1, #near do
			local c = states[near[i]]
			if c and c ~= receiver and c.isCaster and not c.dead and not c.dynamic and first(c) then
				local cshape = getShape(c, lod)
				if cshape then
					local g = getGeom(c, cshape, lod)
					if g.hullCount >= 3 and g.maxX >= x0 and g.minX <= x1 and g.maxY >= y0 and g.minY <= y1
						and lightOverlap(g, wf) then
						local mark = Out.nPoly + 1
						castOnFace(g, wf)
						if Out.nPoly >= mark then
							for _, pc in ipairs(takeOut(wf, mark)) do
								cover[#cover + 1] = pc
							end
							if rec then
								local deps = c.dependents
								if not deps then
									deps = {}
									c.dependents = deps
								end
								if not deps[rec] then
									deps[rec] = true
									rec.receivers = rec.receivers or {}
									rec.receivers[#rec.receivers + 1] = c
								end
							end
						end
					end
				end
			end
		end
		-- this record's polygons on other faces in the same plane (floor tiles side by side:
		-- each one's shadow reaches a hair past its edge), in this face's coordinates
		local o = wf.o + wf.n * wf.lift
		local key = string.format("%.3f,%.3f,%.3f|%.2f", wf.n.X, wf.n.Y, wf.n.Z, o:Dot(wf.n))
		local sameRec = PLANES[key]
		if not sameRec then
			sameRec = {}
			PLANES[key] = sameRec
		end
		local done = {}
		for _, wp in ipairs(sameRec) do
			local n = #wp - 1
			local xs, ys = tcreate(n), tcreate(n)
			for i = 1, n do
				local d = wp[i] - o
				xs[i], ys[i] = d:Dot(wf.u), d:Dot(wf.v)
			end
			done[#done + 1] = {xs, ys, n, wp[n + 1]}
		end
		-- cut, piece by piece (a ring piece only gives way to ring pieces, a shadow to shadows)
		for _, pc in ipairs(mine) do
			ccwPoly(pc)
			local pieces = {pc}
			local against = {}
			for _, q in ipairs(cover) do
				against[#against + 1] = q
			end
			for _, q in ipairs(done) do
				against[#against + 1] = q
			end
			for _, q in ipairs(against) do
				if (q[4] == "dim") == (pc[4] == "dim") then
					ccwPoly(q)
					local nextPieces = {}
					for _, piece in ipairs(pieces) do
						cutAway(piece[1], piece[2], piece[3], q[1], q[2], q[3], piece[4], nextPieces)
					end
					pieces = nextPieces
					if #pieces == 0 then
						break
					end
				end
			end
			done[#done + 1] = pc
			local wp = tcreate(pc[3] + 1)
			for i = 1, pc[3] do
				wp[i] = o + wf.u * pc[1][i] + wf.v * pc[2][i]
			end
			wp[pc[3] + 1] = pc[4]
			sameRec[#sameRec + 1] = wp
			for _, piece in ipairs(pieces) do
				emitPlain(wf, piece[1], piece[2], piece[3], piece[4])
			end
		end
	end

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
		table.clear(PLANES)
		Lamps.rec = rec
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
									local from = Out.nPoly + 1
									castOnFace(g, wf)
									if DIRECT and Out.nPoly >= from then
										local myId = state.id
										unstack(wf, from, r, function(c)
											return c.id < myId
										end, lod, rec)
									end
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
			if CONFIG.ShadeBackFaces and shape.shade and not state.tint and not state.glow then
				emitBackFaces(state, shape, rec)
			end
		end
		Lamps.rec = nil
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
		table.clear(PLANES)
		owner.retry = false
		if Light.valid then
			local geoms, ng = {}, 0
			local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
			for i = 1, #members do
				local st = members[i]
				-- ltmLevel: the camera is fading this body part out (1) or has hidden it (2, first person)
				local fade = st.ltmLevel or 0
				if st.isCaster and not st.dead and fade < 2 then
					local shape, pending = getShape(st, lod)
					if pending then
						owner.retry = true -- its shape isn't known yet (raycasts are rationed): redo next frame
					end
					if shape then
						local g = getGeom(st, shape, lod)
						if g.hullCount >= 3 then
							ng += 1
							geoms[ng] = g
							minX, maxX = min(minX, g.minX), max(maxX, g.maxX)
							minY, maxY = min(minY, g.minY), max(maxY, g.maxY)
							minZ, maxZ = min(minZ, g.minZ), max(maxZ, g.maxZ)
						end
						if CONFIG.ShadeBackFaces and shape.shade and not st.tint and not st.glow and fade == 0
							and not owner.fullShade then
							emitBackFaces(st, shape)
						end
					end
				end
			end
			if ng > 0 then
				local parts = queryBox(minX - MARGIN, maxX + MARGIN, minY - MARGIN, maxY + MARGIN,
					minZ - MARGIN, maxZ + CONFIG.MaxShadowLength)
				-- the floor plane showing the exact silhouette gets no polygons from this character
				local plane = owner.silPlane
				local pn, pd = plane and plane.n, plane and plane.d
				for i = 1, #parts do
					local r = states[parts[i]]
					if r and r.isReceiver and not r.dynamic then
						local rshape = getShape(r, lod)
						if rshape and rshape.faces then
							local faces = getWorldFaces(r, rshape)
							for f = 1, #faces do
								local wf = faces[f]
								if wf.s > MIN_LIT and not (pn and wf.n:Dot(pn) > 0.999 and abs(wf.o:Dot(pn) - pd) < 0.03) then
									local from = Out.nPoly + 1
									for k = 1, ng do
										local g = geoms[k]
										if lightOverlap(g, wf) then
											castOnFace(g, wf)
										end
									end
									if DIRECT and Out.nPoly >= from then
										unstack(wf, from, r, ALWAYS_FIRST, lod, nil)
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
	-- Hair (or a helmet) wraps around the head: its outline is a blob holding the whole head, so
	-- its "shadow" would black out the head and lie like a dark collar on the shoulders. Hair and
	-- hats don't shadow their own character (they still shadow everything else).
	local function wrapsAround(c, st)
		return c.accessory == true and c.charInfo ~= nil and c.charInfo == st.charInfo
	end

	-- Shadows that land ON a character or a loose part, from anything between it and the light.
	function buildReceiverRecord(owner, members, lod)
		local rec = owner.recvRec
		if not rec then
			rec = newRecord(owner, "dynamic")
			owner.recvRec = rec
		end
		resetOut()
		if Light.valid and not owner.fullShade then -- (a whole shaded character has one Highlight)
			local nr = 0
			local minX, maxX, minY, maxY, minZ, maxZ = huge, -huge, huge, -huge, huge, -huge
			for i = 1, #members do
				local st = members[i]
				if st.isReceiver and not st.dead and (st.ltmLevel or 0) == 0 then
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
									if st ~= c and not wrapsAround(c, st) then
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
-- Lamps (DynamicLights, the 2013 edition). In 2013 PointLights, SpotLights and SurfaceLights shone
-- alongside the stencil shadows. Where a lamp shines strongly, the sun's shadow is taken away
-- (a softer ring around it), except where something stands between the lamp and the surface:
-- there the lamp casts a stencil shadow of its own.
----------------------------------------------------------------------------------------------------
do
	local tracked = {}          -- Light instance -> lamp
	local active = {}           -- lamps that shine now
	local lastRefresh = -1
	local SEGS = 24
	local POOL_OUTER = 0.92     -- of Range: where a lamp's light has faded out
	local queryParams = OverlapParams.new()
	queryParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	function Lamps.track(light)
		if CONFIG.DynamicLights and not tracked[light] then
			tracked[light] = {inst = light, sig = "", changedAt = -1}
		end
	end

	-- Where a lamp is and how it shines, read from its instance (nil: it doesn't shine).
	local function readLamp(lamp)
		local light = lamp.inst
		local okAll, res = pcall(function()
			if light.Parent == nil or not light:IsDescendantOf(Workspace) then
				return "gone"
			end
			if not light.Enabled or light.Brightness < 0.2 or light.Range < 0.5 then
				return nil
			end
			local parent = light.Parent
			local cf, size, part
			if parent:IsA("BasePart") then
				cf, size, part = parent.CFrame, parent.Size, parent
			elseif parent:IsA("Attachment") then
				cf, size = parent.WorldCFrame, Vector3.zero
				part = parent.Parent
			else
				return nil
			end
			local kind = light:IsA("SpotLight") and "spot" or (light:IsA("SurfaceLight") and "surface" or "point")
			local dir, corners = nil, nil
			if kind ~= "point" then
				local normal = Vector3.FromNormalId(light.Face)
				dir = cf:VectorToWorldSpace(normal)
				if kind == "surface" then
					-- the lit face of the part: light leaves all of it
					local half = size * 0.5
					local a = math.abs(normal.X) > 0.5 and V3(0, half.Y, 0) or V3(half.X, 0, 0)
					local b = math.abs(normal.Z) > 0.5 and V3(0, half.Y, 0) or V3(0, 0, half.Z)
					if math.abs(normal.Y) > 0.5 then
						a, b = V3(half.X, 0, 0), V3(0, 0, half.Z)
					end
					local c = normal * half
					corners = {cf * (c + a + b), cf * (c + a - b), cf * (c - a + b), cf * (c - a - b)}
					cf = cf + cf:VectorToWorldSpace(c)
				end
			end
			local spread = kind == "point" and 180 or math.clamp(light.Angle, 1, 180)
			return {
				kind = kind, pos = cf.Position, dir = dir, corners = corners, part = part,
				cosHalf = math.cos(math.rad(spread) * 0.5), range = light.Range, bright = light.Brightness,
				moving = part ~= nil and part:IsA("BasePart") and not part.Anchored,
			}
		end)
		if not okAll then
			return nil
		end
		return res
	end

	-- Rebuild the map shadows a lamp reaches (it was switched, moved, or changed).
	local function touchArea(pos, radius)
		if not pos then
			return
		end
		for _, ch in pairs(chunks) do
			if (ch.center - pos).Magnitude < radius + ch.reach then
				ch.needsScan = true
				for _, st in ipairs(ch.list) do
					st.dirty = true
				end
			end
		end
		refreshSoon = true
	end

	-- Every few frames: which lamps shine, and has any of them changed?
	function Lamps.refresh(now)
		if not CONFIG.DynamicLights or now - lastRefresh < 0.1 then
			return
		end
		lastRefresh = now
		table.clear(active)
		for light, lamp in pairs(tracked) do
			local info = readLamp(lamp)
			if info == "gone" then
				touchArea(lamp.pos, lamp.range or 0)
				tracked[light] = nil
			else
				local sig = ""
				if info then
					local p = info.pos
					sig = string.format("%s%.1f,%.1f,%.1f|%.1f|%.2f|%.3f", info.kind, p.X, p.Y, p.Z, info.range,
						info.bright, info.cosHalf)
					if info.dir then
						sig ..= string.format("|%.2f,%.2f,%.2f", info.dir.X, info.dir.Y, info.dir.Z)
					end
				end
				if sig ~= lamp.sig and now - lamp.changedAt > (info and info.moving and 0.3 or 0) then
					touchArea(lamp.pos, lamp.range or 0)
					lamp.sig, lamp.changedAt = sig, now
					lamp.casters = nil
					if info then
						for k, v in pairs(info) do
							lamp[k] = v
						end
						touchArea(lamp.pos, lamp.range)
					else
						lamp.pos = nil
					end
					lamp.shines = info ~= nil
				end
				if lamp.shines then
					active[#active + 1] = lamp
				end
			end
		end
		Lamps.active = #active > 0
	end

	-- How far a lamp's strong light reaches (`fade`: the softer ring's outer edge instead).
	local function poolRange(lamp, fade)
		local k = math.clamp(lamp.bright, 0.3, 1)
		if fade then
			return lamp.range * POOL_OUTER * math.sqrt(k)
		end
		return lamp.range * CONFIG.LightPoolSize * math.sqrt(k)
	end

	-- A lamp's pool on a face plane, as a CCW polygon in the face's 2D coordinates (count, or 0).
	local PX, PY = {}, {}
	local function poolOn(lamp, o, nrm, u, v, R, outX, outY)
		local rel = lamp.pos - o
		local h = rel:Dot(nrm)
		if h <= 0.02 or h >= R then
			return 0
		end
		local rho = math.sqrt(R * R - h * h)
		local cx, cy = rel:Dot(u), rel:Dot(v)
		local n = 0
		for k = 0, SEGS - 1 do
			local t = 2 * math.pi * k / SEGS
			n += 1
			outX[n] = cx + math.cos(t) * rho
			outY[n] = cy + math.sin(t) * rho
		end
		if lamp.kind == "point" then
			return n
		end
		-- a cone: where its edge rays meet the plane (rays that miss reach out along the plane)
		local dir = lamp.dir
		local e1 = (math.abs(dir.Y) < 0.9 and YAXIS or XAXIS):Cross(dir).Unit
		local e2 = dir:Cross(e1)
		local sinHalf = math.sqrt(math.max(0, 1 - lamp.cosHalf * lamp.cosHalf))
		local origins = lamp.corners or {lamp.pos}
		local m = 0
		local CX, CY = {}, {}
		for _, start in ipairs(origins) do
			local srel = start - o
			local sh = srel:Dot(nrm)
			for k = 0, 11 do
				local t = 2 * math.pi * k / 12
				local ray = dir * lamp.cosHalf + (e1 * math.cos(t) + e2 * math.sin(t)) * sinHalf
				local down = -ray:Dot(nrm)
				local hit
				if down > 0.05 and sh > 0 then
					hit = start + ray * (sh / down)
				else
					local flat = ray - nrm * ray:Dot(nrm)
					if flat.Magnitude < 1e-3 then
						flat = e1 - nrm * e1:Dot(nrm)
					end
					hit = start - nrm * sh + flat.Unit * (R * 2)
				end
				m += 1
				local d = hit - o
				CX[m], CY[m] = d:Dot(u), d:Dot(v)
			end
		end
		if dir:Dot(nrm) > 0.05 and not lamp.corners then
			return 0 -- shining away from this plane
		end
		-- keep the part of the disc inside the cone's footprint (its convex hull)
		local hull = {}
		local hn = convexHull(CX, CY, m, hull)
		if hn < 3 then
			return 0
		end
		local inX, inY = outX, outY
		for i = 1, hn do
			local a, b = hull[i], hull[i % hn + 1]
			local ax, ay, bx, by = CX[a], CY[a], CX[b], CY[b]
			n = clipLine(inX, inY, n, -(by - ay), bx - ax, (by - ay) * ax - (bx - ax) * ay, PX, PY)
			if n < 3 then
				return 0
			end
			for j = 1, n do
				outX[j], outY[j] = PX[j], PY[j]
			end
		end
		return n
	end

	-- A still part changed (built, moved, removed) near a lamp: what that lamp lights is redone.
	function Lamps.partMoved(pos)
		for _, lamp in ipairs(active) do
			if (lamp.pos - pos).Magnitude < lamp.range + 8 then
				lamp.casters = nil
				local now = clock()
				if now - (lamp.touchedAt or -1) > 0.3 then
					lamp.touchedAt = now
					touchArea(lamp.pos, lamp.range)
				end
			end
		end
	end

	-- The still things a lamp can cast a shadow of (checked again when the lamp changes).
	local function castersOf(lamp)
		local list = lamp.casters
		if list then
			return list
		end
		list = {}
		local skip = {Render.layers.main.model, Render.layers.tint.model}
		if lamp.part then
			skip[#skip + 1] = lamp.part
		end
		queryParams.FilterDescendantsInstances = skip
		local ok, parts = pcall(function()
			return Workspace:GetPartBoundsInRadius(lamp.pos, lamp.range, queryParams)
		end)
		if ok then
			for _, p in ipairs(parts) do
				local st = states[p]
				if st and st.isCaster and not st.dead and not st.dynamic and not st.character then
					list[#list + 1] = st
				end
			end
		end
		lamp.casters = list
		return list
	end

	-- A caster's corners in world space (round parts: points around their surface).
	local BALL_DIRS = {}
	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				if x ~= 0 or y ~= 0 or z ~= 0 then
					BALL_DIRS[#BALL_DIRS + 1] = V3(x, y, z).Unit
				end
			end
		end
	end
	local function worldPoints(st)
		local shape = getShape(st, 1)
		if not shape then
			return nil
		end
		local cf = st.part.CFrame
		local key = shape
		if st.lampPts and st.lampKey == key and st.lampCf == st.cfVersion then
			return st.lampPts
		end
		local pts = {}
		if shape.verts then
			for i, p in ipairs(shape.verts) do
				pts[i] = cf * p
			end
		elseif shape.points then
			for i, p in ipairs(shape.points) do
				pts[i] = cf * p
			end
		elseif shape.ellipsoids then
			for _, e in ipairs(shape.ellipsoids) do
				for _, d in ipairs(BALL_DIRS) do
					pts[#pts + 1] = cf * (e.c + e.e1 * d.X + e.e2 * d.Y + e.e3 * d.Z)
				end
			end
		end
		st.lampPts, st.lampKey, st.lampCf = pts, key, st.cfVersion
		return pts
	end

	-- A caster's shadow from a lamp on a face plane: the outline of its points pushed away from the
	-- lamp onto the plane (only the part between the plane and the lamp's height counts).
	local SX, SY, HULL = {}, {}, {}
	local function lampShadow(lamp, st, o, nrm, u, v, h, outX, outY)
		local pts = worldPoints(st)
		if not pts or #pts == 0 then
			return 0
		end
		local top = h * 0.98
		local m = 0
		local above, inside = 0, 0
		local D = {}
		for i, p in ipairs(pts) do
			local d = (p - o):Dot(nrm)
			D[i] = d
			if d > 0.02 then
				above += 1
			end
		end
		if above == 0 then
			return 0 -- under or on this surface: the surface's own part
		end
		local lp = lamp.pos
		local function put(p, d)
			local q = lp + (p - lp) * (h / (h - d))
			local rel = q - o
			m += 1
			SX[m], SY[m] = rel:Dot(u), rel:Dot(v)
		end
		for i, p in ipairs(pts) do
			local d = D[i]
			if d >= -0.02 and d <= top then
				inside += 1
				put(p, math.max(d, 0))
			end
		end
		-- where the caster crosses the surface or the lamp's height: cut points there
		for i = 1, #pts do
			local di = D[i]
			for j = i + 1, #pts do
				local dj = D[j]
				for _, cut in ipairs({0, top}) do
					if (di - cut) * (dj - cut) < 0 then
						local t = (cut - di) / (dj - di)
						put(pts[i]:Lerp(pts[j], t), cut)
					end
				end
			end
		end
		if m < 3 then
			return 0
		end
		local hn = convexHull(SX, SY, m, HULL)
		for k = 1, hn do
			outX[k], outY[k] = SX[HULL[k]], SY[HULL[k]]
		end
		return hn
	end

	-- P minus a convex Q: appends P's pieces outside Q to `out` as {xs, ys, n}.
	local AX, AY, BX, BY = {}, {}, {}, {}
	local function copyPoly(xs, ys, n)
		local cx, cy = tcreate(n), tcreate(n)
		for i = 1, n do
			cx[i], cy[i] = xs[i], ys[i]
		end
		return {cx, cy, n}
	end

	local function subtract(xs, ys, n, qx, qy, qn, layer, out)
		local first = copyPoly(xs, ys, n)
		local curX, curY = first[1], first[2]
		local cn = n
		for i = 1, qn do
			local j = i % qn + 1
			local ax, ay, bx, by = qx[i], qy[i], qx[j], qy[j]
			local A, B = -(by - ay), bx - ax
			local C = -(A * ax + B * ay)
			local k = clipLine(curX, curY, cn, -A, -B, -C, AX, AY)
			if k >= 3 and math.abs(polyArea(AX, AY, k)) > MIN_AREA then
				local piece = copyPoly(AX, AY, k)
				piece[4] = layer
				out[#out + 1] = piece
			end
			cn = clipLine(curX, curY, cn, A, B, C, BX, BY)
			if cn < 3 then
				return
			end
			local rest = copyPoly(BX, BY, cn)
			curX, curY = rest[1], rest[2]
		end
	end

	-- P inside a convex Q (count, written into outX / outY).
	local function intersect(xs, ys, n, qx, qy, qn, outX, outY)
		local first = copyPoly(xs, ys, n)
		local curX, curY, cn = first[1], first[2], n
		for i = 1, qn do
			local j = i % qn + 1
			local ax, ay, bx, by = qx[i], qy[i], qx[j], qy[j]
			local A, B = -(by - ay), bx - ax
			local C = -(A * ax + B * ay)
			cn = clipLine(curX, curY, cn, A, B, C, AX, AY)
			if cn < 3 then
				return 0
			end
			local rest = copyPoly(AX, AY, cn)
			curX, curY = rest[1], rest[2]
		end
		for i = 1, cn do
			outX[i], outY[i] = curX[i], curY[i]
		end
		return cn
	end

	local function ccw(xs, ys, n)
		if polyArea(xs, ys, n) < 0 then
			reversePoly(xs, ys, n)
		end
	end

	-- Called for every shadow polygon (in a face's 2D coordinates). Returns true when lamps change
	-- it (the pieces are emitted here), false to draw it as it is.
	local OX, OY, IX, IY, QSX, QSY, TX, TY = {}, {}, {}, {}, {}, {}, {}, {}
	function Lamps.carve(wf, xs, ys, n, emit)
		local o, nrm, u, v = wf.o, wf.n, wf.u, wf.v
		local mine = nil
		for _, lamp in ipairs(active) do
			local h = (lamp.pos - o):Dot(nrm)
			if h > 0.02 and h < lamp.range then
				-- does its light reach this polygon at all? (bounding boxes)
				local rel = lamp.pos - o
				local cx, cy = rel:Dot(u), rel:Dot(v)
				local reach = math.sqrt(math.max(0, lamp.range * lamp.range - h * h))
				local x0, x1, y0, y1 = huge, -huge, huge, -huge
				for i = 1, n do
					local x, y = xs[i], ys[i]
					x0, x1 = math.min(x0, x), math.max(x1, x)
					y0, y1 = math.min(y0, y), math.max(y1, y)
				end
				local near = x1 >= cx - reach and x0 <= cx + reach and y1 >= cy - reach and y0 <= cy + reach
				if near then
					mine = mine or {}
					mine[#mine + 1] = lamp
				end
			end
		end
		if not mine then
			return false
		end
		local pieces = {copyPoly(xs, ys, n)}
		pieces[1][4] = false
		for _, lamp in ipairs(mine) do
			local on = poolOn(lamp, o, nrm, u, v, poolRange(lamp, true), OX, OY)
			if on >= 3 then
				ccw(OX, OY, on)
				local inner = poolOn(lamp, o, nrm, u, v, poolRange(lamp, false), IX, IY)
				if inner >= 3 then
					ccw(IX, IY, inner)
				end
				-- the lamp's own shadows here
				local h = (lamp.pos - o):Dot(nrm)
				local shadows = {}
				for _, st in ipairs(castersOf(lamp)) do
					local k = lampShadow(lamp, st, o, nrm, u, v, h, QSX, QSY)
					if k >= 3 then
						local sp = copyPoly(QSX, QSY, k)
						shadows[#shadows + 1] = sp
						local rec = Lamps.rec
						if rec then
							-- redrawn when that thing moves or goes
							local deps = st.dependents
							if not deps then
								deps = {}
								st.dependents = deps
							end
							if not deps[rec] then
								deps[rec] = true
								rec.receivers = rec.receivers or {}
								rec.receivers[#rec.receivers + 1] = st
							end
						end
					end
				end
				local nextPieces = {}
				for _, pc in ipairs(pieces) do
					local px, py, pn, layer = pc[1], pc[2], pc[3], pc[4]
					-- outside the light: unchanged
					subtract(px, py, pn, OX, OY, on, layer, nextPieces)
					local inn = intersect(px, py, pn, OX, OY, on, TX, TY)
					if inn >= 3 then
						-- in the light's way: things standing in it still cast a full shadow
						for _, sp in ipairs(shadows) do
							local k = intersect(TX, TY, inn, sp[1], sp[2], sp[3], QSX, QSY)
							if k >= 3 and math.abs(polyArea(QSX, QSY, k)) > MIN_AREA then
								local piece = copyPoly(QSX, QSY, k)
								piece[4] = layer
								nextPieces[#nextPieces + 1] = piece
							end
						end
						-- the fading ring: a lighter shadow
						if CONFIG.LightFade and inner >= 3 then
							subtract(TX, TY, inn, IX, IY, inner, "dim", nextPieces)
						end
					end
				end
				pieces = nextPieces
			end
		end
		for _, pc in ipairs(pieces) do
			emit(wf, pc[1], pc[2], pc[3], pc[4])
		end
		return true
	end

	-- Is this point lit by a lamp (in its strong light, nothing in the way)?
	function Lamps.lights(pos, skip)
		for _, lamp in ipairs(active) do
			local to = lamp.pos - pos
			local d = to.Magnitude
			if d < poolRange(lamp, false) and d > 1e-3 then
				local inCone = lamp.kind == "point" or (-to / d):Dot(lamp.dir) >= lamp.cosHalf
				if inCone then
					rayParams.FilterDescendantsInstances = {skip, Render.layers.main.model, lamp.part}
					local hit = Workspace:Raycast(pos, to * 0.98, rayParams)
					local st = hit and states[hit.Instance]
					if not (st and st.isCaster and not st.dead) then
						return true
					end
				end
			end
		end
		return false
	end
end

----------------------------------------------------------------------------------------------------
-- Shadows on avatar parts whose surface can't be drawn on exactly (package meshes, R6 packages):
-- when a part is inside a shadow, a slightly larger, invisible copy of it joins the shadow model,
-- so the same Highlight darkens exactly the part's real shape (merged with every other shadow).
----------------------------------------------------------------------------------------------------
do
	local shadeParams = RaycastParams.new()
	shadeParams.FilterType = Enum.RaycastFilterType.Exclude
	shadeParams.IgnoreWater = true
	local GROW = 0.02      -- studs the copy is bigger than the part on each side
	local PER_FRAME = 6    -- parts per character re-checked against the sun each frame

	-- Does anything that casts a shadow sit between this point and the light?
	local function blocked(origin, len)
		local dir = Light.dir
		for _ = 1, 4 do
			local hit = Workspace:Raycast(origin, dir * len, shadeParams)
			if not hit then
				return false
			end
			local st = states[hit.Instance]
			if st and st.isCaster and not st.dead and (st.ltmLevel or 0) < 2 then
				return true
			end
			-- glass, parts that don't cast, invisible parts: look past them
			local step = hit.Distance + 0.05
			len -= step
			if len <= 0 then
				return false
			end
			origin += dir * step
		end
		return false
	end

	-- In shadow when at least two of three points along the part are (and no lamp lights it).
	local function inShadow(st)
		local part = st.part
		if Lamps.active and Lamps.lights(part.Position, st.character) then
			return false
		end
		local cf, size = part.CFrame, part.Size
		local len = CONFIG.MaxShadowLength
		local up = cf.UpVector * (size.Y * 0.3)
		local p = cf.Position
		local n = (blocked(p, len) and 1 or 0) + (blocked(p + up, len) and 1 or 0)
		if n == 1 then
			n += blocked(p - up, len) and 1 or 0
		end
		return n >= 2
	end

	-- Where a bone sits under its part ("Head/Jaw/..."), to pair a copy's bones with the real ones.
	local function bonePath(bone, root)
		local path = bone.Name
		local node = bone.Parent
		while node and node ~= root do
			path = node.Name .. "/" .. path
			node = node.Parent
		end
		return path
	end

	local function makeCopy(st)
		local part = st.part
		if part:FindFirstChildOfClass("WrapLayer") then
			return nil -- layered clothing only takes its shape on the body
		end
		local copy = nil
		pcall(function()
			local archivable = part.Archivable
			part.Archivable = true
			copy = part:Clone()
			part.Archivable = archivable
		end)
		if not copy then
			return nil
		end
		-- only the shape is wanted: the mesh, and the bones a skinned mesh (a dynamic head) bends
		-- with; no joints, attachments, face controls, scripts, decals or clothing
		local bones = nil
		for _, child in ipairs(copy:GetDescendants()) do
			if child:IsA("Bone") then
				bones = bones or {}
				bones[bonePath(child, copy)] = child
			elseif not child:IsA("DataModelMesh") then
				pcall(child.Destroy, child)
			end
		end
		if bones then
			-- every frame the copy's bones take the real ones' pose (the face moves, so does its copy)
			local pairsList = {}
			for _, bone in ipairs(part:GetDescendants()) do
				if bone:IsA("Bone") then
					local twin = bones[bonePath(bone, part)]
					if twin and twin.Parent then
						pairsList[#pairsList + 1] = bone
						pairsList[#pairsList + 1] = twin
					end
				end
			end
			st.copyBones = pairsList
		end
		local okSkin, skinned = pcall(function()
			return part:IsA("MeshPart") and part.HasSkinnedMesh
		end)
		st.copySkinned = bones ~= nil or (okSkin and skinned == true)
		if st.shadeKind == "charmesh" then
			-- an R6 limb dressed in a package mesh: the copy shows that mesh too
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = "rbxassetid://" .. tostring(st.charMesh)
			mesh.Parent = copy
			st.copyMesh = mesh
		end
		copy.Name = "BodyShade"
		Render.styleShade(copy)
		return copy
	end

	-- A skinned copy finds its bones by name in its own model, so each character's skinned copies
	-- get a model of their own (with the same Highlight trick as the shadow model).
	local function skinModel(info)
		local m = info.skinModel
		if m == nil or m.Parent == nil then
			m = Instance.new("Model")
			m.Name = "SkinnedShade"
			local hum = Instance.new("Humanoid")
			hum.Name = "HighlightHost"
			pcall(function()
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				hum.RequiresNeck = false
				hum.BreakJointsOnDeath = false
				hum.EvaluateStateMachine = false
			end)
			hum.Parent = m
			m.Parent = Render.layers.main.model
			info.skinModel = m
		end
		return m
	end

	-- A whole character in shade (indoors, under a roof): one Highlight on the real avatar darkens
	-- every bit of it exactly - face, hair, hands, glasses - instead of copies.
	local function setFullShade(info, on)
		local hl = info.fullHighlight
		if on then
			if hl == nil or hl.Parent == nil then
				hl = Instance.new("Highlight")
				hl.Name = "CharacterShade"
				hl.FillColor = CONFIG.ShadowColor
				hl.FillTransparency = CONFIG.ShadowTransparency
				hl.OutlineTransparency = 1
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				info.fullHighlight = hl
			end
			hl.Adornee = info.model
			hl.Enabled = true
			if hl.Parent ~= Render.layers.main.model then
				hl.Parent = Render.layers.main.model
			end
		elseif hl then
			hl.Enabled = false
			hl.Parent = nil
		end
	end

	local function visibleMember(st)
		return not st.dead and st.isReceiver and (st.ltmLevel or 0) == 0
	end

	-- A part either sits in a shadow (its copy, a hair bigger, darkens all of it), or it's lit and
	-- only its side away from the light is dark: its copy is pushed a hair away from the light, so
	-- the copy only pokes out of the real part on that side, and the Highlight darkens exactly the
	-- real surface there - the same thing the old shadow volumes did.
	function BodyShade.update(info)
		local main = Render.layers.main.model
		local filter = {info.model, main, Render.layers.tint.model, Workspace.Terrain}
		if MeshProbe.model then
			filter[#filter + 1] = MeshProbe.model
		end
		if Silhouette.holder then
			filter[#filter + 1] = Silhouette.holder
		end
		shadeParams.FilterDescendantsInstances = filter
		local members = info.members
		local n = #members
		if n == 0 then
			return
		end
		-- re-check a few parts against the sun each frame (round robin)
		local cursor = info.shadeCursor or 0
		for _ = 1, min(n, PER_FRAME) do
			cursor = cursor % n + 1
			local st = members[cursor]
			if visibleMember(st) and Light.valid then
				st.inShade = inShadow(st)
			else
				st.inShade = nil
			end
			st.shaded = st.shadeKind ~= nil and not st.polyReceive and st.inShade == true
		end
		info.shadeCursor = cursor
		-- the whole character in shade? (once on, it waits for two lit parts or a lasting one)
		local lit, known = 0, 0
		for i = 1, n do
			local st = members[i]
			if st.inShade ~= nil and visibleMember(st) then
				known += 1
				if not st.inShade then
					lit += 1
				end
			end
		end
		local now = clock()
		local full = info.fullShade
		if full then
			if lit == 0 then
				info.litSince = nil
			else
				info.litSince = info.litSince or now
				if lit >= 2 or now - info.litSince > 0.25 then
					full = false
				end
			end
		else
			full = known > 0 and lit == 0 and Light.valid and not holdHidden
		end
		if full ~= (info.fullShade or false) then
			info.fullShade = full
			info.litSince = nil
			setFullShade(info, full)
			-- drawn polygons (dark sides, shadows on the head) give way to it, or come back
			if info.casterRec then
				info.casterRec.lightVersion = -1
			end
			if info.recvRec then
				info.recvRec.lightVersion = -1
			end
		end
		local push = 0.02 + (info.dist or 0) * 0.0005
		local away = Light.dir * -push
		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position
		-- every frame: the copies follow their parts
		for i = 1, n do
			local st = members[i]
			local copy = st.shadeCopy
			local mode = nil
			if not full and st.shadeKind and visibleMember(st) and Light.valid then
				if st.shaded then
					mode = "whole"
				elseif CONFIG.ShadeBackFaces then
					mode = "dark"
				end
			end
			if mode then
				if copy == nil then
					copy = makeCopy(st) or false
					st.shadeCopy = copy
				end
				if copy then
					local part = st.part
					local size, cf, scale = part.Size, part.CFrame, 1
					if mode == "whole" then
						if st.copySkinned then
							-- a skinned mesh can't simply be made bigger: it moves a hair toward
							-- the camera instead, so it covers the real one
							if camPos then
								local toCam = camPos - cf.Position
								local d = toCam.Magnitude
								if d > 1e-3 then
									cf += toCam * ((0.02 + d * 0.0005) / d)
								end
							end
						else
							size += V3(GROW * 2, GROW * 2, GROW * 2)
							scale = 1.03
						end
					else
						cf += away
					end
					if copy.Size ~= size then
						copy.Size = size
					end
					copy.CFrame = cf
					local mesh = st.copyMesh
					if mesh and mesh.Scale.X ~= scale then
						mesh.Scale = V3(scale, scale, scale)
					end
					local bones = st.copyBones
					if bones then
						for b = 1, #bones - 1, 2 do
							bones[b + 1].Transform = bones[b].Transform
						end
					end
					local home = st.copySkinned and skinModel(info) or main
					if copy.Parent ~= home then
						copy.Parent = home
					end
				end
			elseif copy and copy.Parent then
				copy.Parent = nil
			end
		end
	end

	function BodyShade.clear(info)
		for _, st in ipairs(info.members) do
			st.shaded = false
			st.inShade = nil
			local copy = st.shadeCopy
			if copy and copy.Parent then
				copy.Parent = nil
			end
		end
		if info.fullShade then
			info.fullShade = false
			setFullShade(info, false)
		end
	end

	-- A character gone for good: its shade model and Highlight go too.
	function BodyShade.forget(info)
		BodyShade.clear(info)
		if info.fullHighlight then
			pcall(info.fullHighlight.Destroy, info.fullHighlight)
			info.fullHighlight = nil
		end
		if info.skinModel then
			pcall(info.skinModel.Destroy, info.skinModel)
			info.skinModel = nil
		end
	end

	function BodyShade.drop(st)
		local copy = st.shadeCopy
		st.shadeCopy = nil
		st.copyBones = nil
		st.shaded = false
		if copy then
			pcall(copy.Destroy, copy)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Exact character silhouettes. A black copy of the character is drawn, as seen from the light, in
-- a ViewportFrame on a SurfaceGui lying on the floor under it, stretched along the light so every
-- point lands exactly where its shadow falls: hair spikes, hats, clothing, tools, everything.
-- It's used whenever the character's whole shadow lies on one flat, lit block face (which is most
-- of the time); anywhere else (edges, stairs, inside other shadows) the character casts polygons.
----------------------------------------------------------------------------------------------------
do
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude
	floorParams.IgnoreWater = true
	local litParams = RaycastParams.new()
	litParams.FilterType = Enum.RaycastFilterType.Exclude
	litParams.IgnoreWater = true
	local THICK = 0.02
	local ROOM = 0.4       -- studs of room around the shadow
	local CORNERS = {}
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				CORNERS[#CORNERS + 1] = V3(x, y, z) * 0.5
			end
		end
	end

	local function holderModel()
		local h = Silhouette.holder
		if h == nil or h.Parent == nil then
			h = Instance.new("Model")
			h.Name = SILHOUETTE_NAME
			h.Parent = Workspace
			Silhouette.holder = h
		end
		return h
	end

	local function filterList(info)
		local list = {info.model, Render.layers.main.model, Render.layers.tint.model, holderModel()}
		if MeshProbe.model then
			list[#list + 1] = MeshProbe.model
		end
		return list
	end

	local function newView()
		local canvas = Instance.new("Part")
		canvas.Name = "SilhouetteCanvas"
		canvas.Anchored = true
		canvas.CanCollide = false
		canvas.CanQuery = false
		canvas.CanTouch = false
		canvas.CastShadow = false
		canvas.Transparency = 1
		canvas.Size = V3(1, 1, THICK)
		local gui = Instance.new("SurfaceGui")
		gui.Name = SILHOUETTE_GUI
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(256, 256)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.ClipsDescendants = true
		gui.ResetOnSpawn = false
		gui.Adornee = canvas
		local vf = Instance.new("ViewportFrame")
		vf.Size = UDim2.fromScale(1, 1)
		vf.BackgroundTransparency = 1
		vf.ImageColor3 = CONFIG.ShadowColor
		vf.ImageTransparency = CONFIG.RenderStyle == "Direct" and CONFIG.DirectTransparency or CONFIG.ShadowTransparency
		vf.Ambient = Color3.new(0, 0, 0)    -- no light at all inside: the copy draws black
		vf.LightColor = Color3.new(0, 0, 0)
		vf.Parent = gui
		local world = Instance.new("WorldModel")
		world.Parent = vf
		local cam = Instance.new("Camera")
		cam.Parent = vf
		vf.CurrentCamera = cam
		-- in the PlayerGui the copy stays out of the workspace; otherwise it rides on the canvas
		local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
		gui.Parent = playerGui or canvas
		return {canvas = canvas, gui = gui, vf = vf, world = world, cam = cam, clones = {}, shown = false}
	end

	local function copyOf(st)
		local part = st.part
		if part:FindFirstChildOfClass("WrapLayer") then
			return nil -- layered clothing only takes its shape on the body
		end
		local copy = nil
		pcall(function()
			local archivable = part.Archivable
			part.Archivable = true
			copy = part:Clone()
			part.Archivable = archivable
		end)
		if not copy then
			return nil
		end
		for _, child in ipairs(copy:GetDescendants()) do
			-- keep what gives it its shape (meshes, and the bones a skinned mesh like a dynamic
			-- head needs) and its see-through cutouts (SurfaceAppearance)
			if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance") or child:IsA("Bone")) then
				pcall(child.Destroy, child)
			end
		end
		if st.charMesh then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = "rbxassetid://" .. tostring(st.charMesh)
			mesh.Parent = copy
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		if copy.Material == Enum.Material.Neon then
			copy.Material = Enum.Material.SmoothPlastic -- Neon would glow even in the dark
		end
		return copy
	end

	-- Does anything that casts a shadow sit between this floor point and the light?
	local function shaded(origin)
		local dir = Light.dir
		local len = CONFIG.MaxShadowLength
		for _ = 1, 4 do
			local hit = Workspace:Raycast(origin, dir * len, litParams)
			if not hit then
				return false
			end
			local st = states[hit.Instance]
			if st and st.isCaster and not st.dead and (st.ltmLevel or 0) < 2 then
				return true
			end
			local step = hit.Distance + 0.05
			len -= step
			if len <= 0 then
				return false
			end
			origin += dir * step
		end
		return false
	end

	function Silhouette.hide(info)
		local view = info.sil
		if view and view.shown then
			view.shown = false
			view.gui.Enabled = false
			view.canvas.Parent = nil
			for _, c in pairs(view.clones) do
				if c then
					c.Parent = nil
				end
			end
		end
	end

	function Silhouette.hideAll()
		for _, info in pairs(characters) do
			Silhouette.hide(info)
		end
	end

	function Silhouette.drop(info)
		local view = info.sil
		info.sil = nil
		if view then
			pcall(view.gui.Destroy, view.gui)
			pcall(view.canvas.Destroy, view.canvas)
		end
	end

	function Silhouette.destroyAll()
		for _, info in pairs(characters) do
			Silhouette.drop(info)
		end
		if Silhouette.holder then
			pcall(Silhouette.holder.Destroy, Silhouette.holder)
			Silhouette.holder = nil
		end
	end

	-- Shows the silhouette when it fits. Returns the floor part it's drawn on, or nil.
	function Silhouette.update(info, root)
		if not CONFIG.ExactSilhouettes or not Light.valid or root == nil then
			Silhouette.hide(info)
			return nil
		end
		local filter = filterList(info)
		floorParams.FilterDescendantsInstances = filter
		litParams.FilterDescendantsInstances = filter
		-- 1. the floor under the character: something still and flat
		local hit = Workspace:Raycast(root.Position, V3(0, -60, 0), floorParams)
		local floorPart = hit and hit.Instance
		local fst = floorPart and states[floorPart]
		if not fst or fst.dynamic or not fst.isReceiver then
			Silhouette.hide(info)
			return nil
		end
		local n = hit.Normal
		local L = Light.L
		local sinE = -L:Dot(n) -- how high the light stands above this floor
		if sinE < 0.15 then
			Silhouette.hide(info)
			return nil
		end
		local flat = L + n * sinE
		local cosE = flat.Magnitude
		local u = cosE > 1e-4 and flat / cosE or (abs(n.Y) < 0.9 and YAXIS or XAXIS):Cross(n).Unit
		local v = n:Cross(u)
		-- 2. where the shadow falls: every visible part's box, pushed along the light onto the floor
		local F = hit.Position
		local umin, umax, vmin, vmax = huge, -huge, huge, -huge
		local spots = info.silSpots or {}
		info.silSpots = spots
		local ns = 0
		for _, st in ipairs(info.members) do
			if st.isCaster and not st.dead and (st.ltmLevel or 0) < 2 then
				local cf, size = st.part.CFrame, st.part.Size
				for k = 1, 8 do
					local P = cf * (CORNERS[k] * size)
					local d = (P - F):Dot(n)
					local S = P + L * (max(d, 0) / sinE)
					local rel = S - F
					local a, b = rel:Dot(u), rel:Dot(v)
					umin, umax = min(umin, a), max(umax, a)
					vmin, vmax = min(vmin, b), max(vmax, b)
				end
				-- where the middle of this part's shadow lands (to see if it falls in the light)
				local P = cf.Position
				ns += 1
				spots[ns] = P + L * (max((P - F):Dot(n), 0) / sinE)
			end
		end
		for i = #spots, ns + 1, -1 do
			spots[i] = nil
		end
		if ns == 0 then
			Silhouette.hide(info)
			return nil
		end
		umin, umax, vmin, vmax = umin - ROOM, umax + ROOM, vmin - ROOM, vmax + ROOM
		local W = max(vmax - vmin, (umax - umin) * sinE)
		local Lu = W / sinE
		local center = F + u * ((umin + umax) * 0.5) + v * ((vmin + vmax) * 0.5)
		-- 3. the floor has to carry on, flat, under the whole canvas (it may be many parts: tiles,
		-- a baseplate in pieces), or the shadow would hang in the air past an edge
		for k = 0, 15 do
			local su, sv = (k % 4) / 3 - 0.5, floor(k / 4) / 3 - 0.5
			local c = center + u * (Lu * su) + v * (W * sv)
			local down = Workspace:Raycast(c + n * 0.3, n * -0.6, floorParams)
			local dst = down and states[down.Instance]
			if not down or abs(down.Distance - 0.3) > 0.03 or down.Normal:Dot(n) < 0.999 or not dst
				or dst.dynamic or not dst.isReceiver then
				Silhouette.hide(info)
				return nil
			end
		end
		-- 4. and mostly in the light: a silhouette inside another shadow would make it darker
		-- (a few spots are re-checked each frame; it switches over with a margin, not back and forth)
		local lit = info.silLit or {}
		info.silLit = lit
		local cursor = info.silCursor or 0
		for _ = 1, min(ns, 6) do
			cursor = cursor % ns + 1
			lit[cursor] = not shaded(spots[cursor] + n * 0.05)
		end
		info.silCursor = cursor
		local nl = 0
		for i = 1, ns do
			if lit[i] ~= false then
				nl += 1
			end
		end
		local share = nl / ns
		if share < (info.sil and info.sil.shown and 0.6 or 0.8) then
			Silhouette.hide(info)
			return nil
		end
		-- 4. show it
		local view = info.sil
		if not view then
			view = newView()
			info.sil = view
		end
		local clones = view.clones
		for _, st in ipairs(info.members) do
			local c = clones[st]
			if st.isCaster and not st.dead and (st.ltmLevel or 0) < 2 then
				if c == nil then
					c = copyOf(st) or false
					clones[st] = c
				end
				if c then
					local part = st.part
					if c.Size ~= part.Size then
						c.Size = part.Size
					end
					c.CFrame = part.CFrame
					if c.Parent ~= view.world then
						c.Parent = view.world
					end
				end
			elseif c then
				c.Parent = nil
			end
		end
		for st, c in pairs(clones) do
			if st.dead then
				if c then
					pcall(c.Destroy, c)
				end
				clones[st] = nil
			end
		end
		-- the camera looks along the light, framing exactly the canvas (tiny angle: nearly parallel)
		local dist = W * 45
		local up = u * sinE + n * cosE
		view.cam.CFrame = CFrame.fromMatrix(center - L * dist, v, -up)
		view.cam.FieldOfView = math.deg(2 * math.atan(W * 0.5 / dist))
		-- the canvas: its front face lies on the floor; across it runs v, along it runs u
		local px = math.clamp(math.floor(W * 40 + 0.5), 96, 512)
		if view.gui.CanvasSize.X ~= px then
			view.gui.CanvasSize = Vector2.new(px, px)
		end
		view.canvas.Size = V3(W, Lu, THICK)
		view.canvas.CFrame = CFrame.fromMatrix(center + n * (CONFIG.SurfaceOffset - THICK * 0.5), -v, -u)
		if holdHidden then
			Silhouette.hide(info) -- the start-up pause shows everything at once afterwards
		elseif not view.shown then
			view.shown = true
			view.canvas.Parent = holderModel()
			view.gui.Enabled = true
		end
		-- the polygons leave this floor plane to the silhouette
		local plane = info.silPlaneT or {}
		info.silPlaneT = plane
		plane.n, plane.d = n, F:Dot(n)
		return string.format("%.3f,%.3f,%.3f,%.3f", n.X, n.Y, n.Z, plane.d)
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
		-- glowing (Neon) parts give off their own light: shadows don't darken them
		local glow = CONFIG.GlowingPartsStayLit and part.Material == Enum.Material.Neon
		state.glow = glow
		state.isReceiver = visible and not glow
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
		if Lamps.active and not state.character then
			Lamps.partMoved(state.part.Position)
		end
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
		local main, tint, dim = Render.layers.main, Render.layers.tint, Render.layers.dim
		if parent == nil or part:IsDescendantOf(main.model) or parent == tint.model
			or (dim ~= nil and parent == dim.model) or (parent == MeshProbe.model and parent ~= nil)
			or (Silhouette.holder ~= nil and part:IsDescendantOf(Silhouette.holder)) then
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
				newCharacter = true -- read what it's wearing right away
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
		BodyShade.drop(state)
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
				Silhouette.drop(info)
				BodyShade.forget(info)
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
		if state.charInfo then
			state.charInfo.dirty = true
		end
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
	local LOOK_PROPS = {Transparency = true, CastShadow = true, Color = true, Material = true}

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
			if not states[part] and part:IsA("BasePart") and part.Parent ~= nil then
				register(part)
			elseif CONFIG.DynamicLights and part:IsA("Light") then
				Lamps.track(part)
			end
			count += 1
			if count % 200 == 0 and clock() > deadline then
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

	-- Avatar outlines that arrived: redraw the parts that were waiting for them.
	function processProbeReady()
		while true do
			local entry = qpop(MeshProbe.ready)
			if not entry then
				return
			end
			local users = entry.users
			entry.users = setmetatable({}, {__mode = "k"})
			for st in pairs(users) do
				if not st.dead then
					onShapeChanged(st)
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

	local BODY_FIELDS = {"Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"}

	-- What the avatar is wearing: R6 package meshes (CharacterMesh) and, from the
	-- HumanoidDescription, which R15 body parts are the default blocky ones (asset id 0).
	local function readBody(model)
		local meshes, blocky, sig = nil, nil, ""
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("CharacterMesh") then
				meshes = meshes or {}
				local name = child.BodyPart.Name
				meshes[name] = child.MeshId
				sig = sig .. name .. tostring(child.MeshId) .. ","
			end
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local desc = hum and hum:FindFirstChildOfClass("HumanoidDescription")
		if desc then
			blocky = {}
			sig = sig .. "|"
			for _, field in ipairs(BODY_FIELDS) do
				local ok, id = pcall(function()
					return desc[field]
				end)
				if ok and id == 0 then
					blocky[field] = true
					sig = sig .. field .. ","
				end
			end
		end
		return meshes, blocky, sig
	end

	function refreshCharacters()
		for model, info in pairs(characters) do
			info.isLocal = LocalPlayer ~= nil and LocalPlayer.Character == model
			local meshes, blocky, sig = readBody(model)
			local bodyChanged = sig ~= info.bodySig
			if bodyChanged then
				info.bodySig, info.charMeshes, info.blocky = sig, meshes, blocky
				info.dirty = true
			end
			for _, st in ipairs(info.members) do
				local part = st.part
				local size, t = part.Size, part.Transparency
				if bodyChanged or size ~= st.lastSize or t ~= st.lastT then
					st.lastSize, st.lastT = size, t
					st.shapeVersion += 1
					st.geom = nil
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
	local wholeMapChecked = nil

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

	-- LoadWholeMap: is the map small enough to build all of it and keep it?
	local function checkWholeMap()
		if not CONFIG.LoadWholeMap then
			wholeMap = false
			return
		end
		local n = 0
		for _, ch in pairs(chunks) do
			n += #ch.list
		end
		local limit = Render.meshOk and CONFIG.WholeMapParts or CONFIG.PartsWholeMapParts
		wholeMap = n <= limit
		stats.mapParts = n
		stats.wholeMap = wholeMap
	end

	local function refreshChunks(camPos)
		local R = CONFIG.ShadowDistance
		if not Render.meshOk then
			R = min(R, CONFIG.PartsShadowDistance)
		end
		local whole = wholeMap
		local queue = {}
		for _, ch in pairs(chunks) do
			local d = max(0, (ch.center - camPos).Magnitude - ch.reach)
			ch.dist = d
			if whole or d <= R then
				if not ch.active then
					ch.active = true
					ch.needsScan = true
				end
				local lod = lodFor(d, ch.lod)
				if whole and ch.lod ~= 0 and lod > ch.lod then
					lod = ch.lod -- a kept map only gets finer as you come close, never rebuilt coarser
				end
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

	-- Returns true when every queued chunk has been gone through.
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
				return true
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
					return false
				end
			end
		end
		return staticQueue[staticHead] == nil
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
			local part = st.part
			local cf = part.CFrame
			local prev = last[st]
			if not prev or not cf:FuzzyEq(prev, 1e-4) then
				last[st] = cf
				moved = true
			end
			-- zooming in fades your own character out (LocalTransparencyModifier) and hides it in
			-- first person: its shadows go with it
			local ltm = part.LocalTransparencyModifier
			local level = ltm > 0.5 and 2 or (ltm > 0.02 and 1 or 0)
			if level ~= (st.ltmLevel or 0) then
				st.ltmLevel = level
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
		local casting, receiving, silhouettes = 0, 0, 0
		for i = 1, nc do
			local info = CHAR_LIST[i]
			local lod = info.dist < CONFIG.NearDetail and 1 or 2
			local inBudget = i == 1 or clock() < deadline
			-- a character standing perfectly still keeps its shadows (animated ones always move)
			local moved = characterMoved(info)
			-- its exact silhouette on the floor, when that fits (the polygons then skip that floor)
			local silFloor = nil
			if CONFIG.ExactSilhouettes and CONFIG.CharacterShadows and silhouettes < CONFIG.MaxSilhouettes
				and info.dist <= CONFIG.ReceiverDistance then
				silhouettes += 1
				silFloor = safeCall(Silhouette.update, info, characterRoot(info))
			else
				Silhouette.hide(info)
			end
			if silFloor ~= info.silFloor then
				info.silFloor = silFloor
				info.silPlane = silFloor and info.silPlaneT or nil
				moved = true
			end
			if CONFIG.CharacterShadows and casting < CONFIG.MaxCharacters and info.dist <= CONFIG.DynamicDistance then
				casting += 1
				local rec = info.casterRec
				if inBudget and (moved or info.retry or not rec or rec.lightVersion ~= Light.version or rec.lod ~= lod) then
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
				-- package avatars: their real shape darkens where they stand in shadow
				if CONFIG.ShadowsOnAvatars then
					safeCall(BodyShade.update, info)
				end
			else
				if info.recvRec then
					dropRecord(info.recvRec)
					info.recvRec = nil
				end
				BodyShade.clear(info)
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
				local changed = grp.sig ~= grp.builtSig or grp.ids ~= grp.builtIds or grp.retry
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

	-- One frame of work. budgetMs / warm are used by the start-up pause, which runs this over and
	-- over with a big budget. Returns true when everything in range has been built.
	function step(dt, budgetMs, warm)
		frameId += 1
		local now = clock()
		RaySample.budget = warm and 40 or 3
		local loading = not initialScanDone or staticHead <= #staticQueue
		local budget = budgetMs or ((loading and dt < 1 / 40) and CONFIG.LoadingBudget or CONFIG.FrameBudget)
		local deadline = now + budget / 1000
		local settled = initialScanDone and not warm

		processRemovals()
		processCharacterChanges()
		processAdds(settled and now + 0.0015 or deadline, settled and 500 or CONFIG.RegisterPerFrame)
		processChanges(now)
		processMeshReady()
		processProbeReady()
		if not enabled then
			Silhouette.hideAll()
			return true
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
			Silhouette.hideAll()
			return true
		end

		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or ZERO
		Lamps.refresh(now)
		pollPhysics(now)
		if newCharacter or now - lastCharacterRefresh > 0.5 then
			newCharacter = false
			lastCharacterRefresh = now
			refreshCharacters()
		end
		if initialScanDone and (wholeMapChecked == nil or now - wholeMapChecked > 3) then
			-- (again every few seconds: a map that streams in or gets built on can outgrow it)
			local was = wholeMap
			wholeMapChecked = now
			checkWholeMap()
			if was ~= wholeMap then
				refreshSoon = true
			end
		end
		if warm or refreshSoon or now - lastRefresh > 0.25 then
			refreshSoon = false
			lastRefresh = now
			refreshChunks(camPos)
		end
		processDynamic(camPos, now, deadline)
		Render.updateCores(camPos)
		local staticDone = false
		if initialScanDone then
			processUpstream(deadline)
			staticDone = processStatic(deadline)
		end
		Render.flush(now)
		stats.frameMs = (clock() - now) * 1000
		return staticDone and urgentQ.head > urgentQ.tail and upstreamQ.head > upstreamQ.tail
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
	if not on then
		Silhouette.hideAll()
	end
	if started then -- before that, the start-up pause swaps the shadows over when it's done
		applyRobloxShadows(on)
	end
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
	pcall(Silhouette.destroyAll)
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
	local main, tint, dim = Render.layers.main, Render.layers.tint, Render.layers.dim
	if inst:IsDescendantOf(main.model) or parent == tint.model or (dim ~= nil and parent == dim.model)
		or (parent ~= nil and parent == MeshProbe.model)
		or (Silhouette.holder ~= nil and inst:IsDescendantOf(Silhouette.holder)) then
		return
	end
	if inst:IsA("BasePart") or (CONFIG.DynamicLights and inst:IsA("Light")) then
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

-- The start-up pause: nothing is shown until everything near the player has been built. The game
-- simply freezes for a moment while that happens (no loading screen). The freeze is cut into
-- slices of LoadPauseSlice seconds with one frame in between, so Roblox never stops the script for
-- running too long, and it never lasts longer than LoadPauseMax.
local function loadPause()
	pcall(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
	end)
	-- wait for our character to spawn, so the area around it is what gets built
	local waited = 0
	while alive and LocalPlayer and not LocalPlayer.Character and waited < 10 do
		waited += task.wait(0.1)
	end
	if LocalPlayer and LocalPlayer.Character then
		task.wait(0.2) -- the camera moves to the character
	end
	if not alive or not enabled then
		return
	end
	holdHidden = true
	local t0 = clock()
	local stop = t0 + CONFIG.LoadPauseMax
	while alive and enabled do
		-- a map small enough to build completely gets a longer pause (decided once it's scanned)
		stop = t0 + (wholeMap and max(CONFIG.WholeMapPauseMax, CONFIG.LoadPauseMax) or CONFIG.LoadPauseMax)
		local sliceEnd = min(clock() + CONFIG.LoadPauseSlice, stop)
		local done = false
		repeat
			local ok, res = pcall(step, 1 / 60, max(1, (sliceEnd - clock()) * 1000), true)
			if ok then
				done = res
			else
				errorCount += 1
				warn("[StencilShadows] " .. tostring(res))
				done = true
			end
		until done or clock() >= sliceEnd
		if done or clock() >= stop then
			break
		end
		RunService.Heartbeat:Wait() -- let one frame through, then carry on
	end
	-- avatar outlines load in the background: wait a moment for your own character's (shadows
	-- still hidden), so your shadow is already the right shape when everything appears
	local function ownOutlinesLoading()
		local char = LocalPlayer and LocalPlayer.Character
		local info = char and characters[char]
		if not info then
			return false
		end
		for _, st in ipairs(info.members) do
			local probe = st.probe
			if probe and (probe.status == "queued" or probe.status == "loading") then
				return true
			end
		end
		return false
	end
	local waited = 0
	while alive and enabled and waited < 3 and ownOutlinesLoading() do
		waited += task.wait(0.05)
	end
	if waited > 0 and alive and enabled then
		pcall(step, 1 / 60, 50, true)
	end
	stats.loadPauseMs = (clock() - t0) * 1000
	holdHidden = false
end

local function mainLoop()
	if enabled and CONFIG.LoadPause then
		local ok, err = pcall(loadPause)
		holdHidden = false
		if not ok then
			warn("[StencilShadows] " .. tostring(err))
		end
	end
	started = true
	if alive and enabled then
		-- Roblox's shadows go off at the same moment the stencil shadows appear
		applyRobloxShadows(true)
		Render.setVisible(Light.valid)
	end
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
	if alive and enabled and started and CONFIG.DisableRobloxShadows and Lighting.GlobalShadows then
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

-- Every descendant goes into the queue as-is; filtering happens in the time-budgeted loader, so
-- starting the script on a huge map doesn't freeze the game.
do
	local all = Workspace:GetDescendants()
	addQ.items, addQ.head, addQ.tail = all, 1, #all
end

Render.setVisible(false) -- shown after the start-up pause, once the light has been read

_G.StencilShadows = API
_G.__StencilShadowsCleanup = shutdown

task.spawn(mainLoop)
