# Classic Stencil Shadows for Roblox

A single LocalScript that recreates the hard, dark stencil shadows Roblox had from 2008 to 2013. It is
built the way the [real-time stencil shadow system on the DevForum](https://devforum.roblox.com/t/how-accurate-does-this-real-time-stencil-shadow-system-look-and-act-compared-to-the-old-stencil-shadows-roblox-used-to-have/4920633)
describes it. Shadows are exact polygons pushed along the sunlight onto every surface behind a part,
and overlapping shadows never get darker than a single shadow.

There are two scripts. They are the same script with one setting changed:

| Script | What it's like |
| --- | --- |
| [`src/StencilShadows.client.luau`](src/StencilShadows.client.luau) | **Classic** (2008 to early 2013). Only the sun and moon matter. Lamps are dimmed by shadows like everything else, as in the old engine. |
| [`src/StencilShadows2013.client.luau`](src/StencilShadows2013.client.luau) | **2013 edition.** PointLights arrived in March 2013 and stencil shadows stayed until early 2014. Lamps (PointLight, SpotLight, SurfaceLight) light up the shadows where they shine, with a softer ring around the light. Things standing in a lamp's light still cast a shadow from the lamp there. (`DynamicLights = true`.) |

## Setup

1. In Studio, add a **LocalScript** to `StarterPlayer > StarterPlayerScripts` and paste one of the
   scripts in.
2. Recommended: open **Game Settings > Security** and turn on **Allow Mesh / Image APIs**. Roblox
   blocks EditableMesh in published games unless this is on. Without it, the script draws the same
   shadows with thin parts instead, which works but costs more, so its default range is shorter.
3. Play. Press **9** to switch between Roblox's shadows and the stencil shadows.

## What it does

- **Every opaque part casts**: blocks, wedges, corner wedges, balls, cylinders, capsules, special
  meshes (sphere, cylinder, head, wedge), unions, and MeshParts.
  - Mesh shadows use the real triangles when the mesh can be read, so concave shapes such as arches
    and L-shapes keep their holes. (In the default `"Direct"` style a mesh casts its outline.)
  - If a mesh can't be read, its outline is sampled with raycasts instead.
- **Balls and cylinders are blocky, like the old engine.** Old Roblox drew a ball with 16 x 8 flat
  facets, so a tree top's dark side ended in steps, facet by facet. Here every one of those classic
  facets is dark or lit as a whole.
  - The steps are drawn on finer facets that hug the real ball, so nothing floats off its edge.
  - In the Highlight style, the middle of a ball's dark side is one ball-shaped part. When drawing
    with parts, a nearby size-8 tree top costs about 300 parts in the Highlight style and about
    750 in the Direct style (where that ball-shaped part would overlap the facets).
  - A ball's shadow on the ground has the classic facets' outline.
  - `RoundShading = "Smooth"` gives the smooth version instead.
- **Characters cast their exact silhouette**, R6 and R15, with packages, hats, hair and tools.
  - On a still, flat floor in the light, a black copy of the character is drawn as seen from the
    sun, in a ViewportFrame on a SurfaceGui lying on the floor. Hair spikes, hats, clothing, tools
    and the exact pose all show. The floor can be several parts side by side (tiles, plates).
    When the silhouette is shown, the character draws nothing else on that floor, so there is
    never a double shadow.
  - Where that can't work (the shadow crosses an edge or stairs, or mostly falls inside another
    shadow), each part casts its real outline instead. That outline comes from a hidden copy of
    each mesh with an exact convex-hull collision shape, traced once with raycasts.
  - Default blocky bodies (R6, and R15 with the default body) are real boxes and are drawn exactly.
- **Shadows land on players too.**
  - Blocky bodies take exact shadows, and their sides away from the sun are dark.
  - On package avatars, heads, hair and hats, each part has a copy of its real mesh that darkens
    it. In the light, only the side facing away from the sun darkens, as inside the old shadow
    volumes. Inside a shadow, the whole part darkens.
  - Dynamic heads keep their face bones in that copy, so it follows the face.
  - A character that is entirely in shade (indoors, under a roof) is darkened by one Highlight on
    the real avatar instead, so face, hair, hands and glasses all darken exactly.
  - Hair and hats don't shadow their own head. Their outline is a blob around the head, so that
    shadow used to black out the whole head.
  - Zoomed into first person, your own character's shadows disappear along with it.
- **Shadows land on everything behind the caster**: floors, walls, roofs, slopes, round parts,
  meshes, terrain, and other players.
  - A shadow continues from the floor up a wall and over a box, and is cut exactly at each
    surface's edge. Shadows on two faces that meet at an edge meet exactly, with no lit line.
  - Glowing (Neon) parts give off light, so shadows don't darken them.
- **Smooth shadow edges.** Shadows are drawn as plain see-through geometry, which Roblox
  anti-aliases. Wherever two shadows would overlap on a surface, one is cut away, so nothing is ever
  darker than one shadow. That includes a player's shadow over a building's shadow, and one shadow
  across two floor tiles. The old way, one Highlight, is still there (`RenderStyle = "Highlight"`),
  but Roblox draws Highlights without anti-aliasing, so their edges look jagged on phones.
- **The whole map at once.** There is no loading screen. The game waits for your character, then
  freezes while the shadows are built, then all of them appear in the same frame that Roblox's own
  shadows switch off.
  - Maps up to 12,000 parts (4,000 when drawing with parts) are built completely and kept, so
    nothing loads while you walk around. The pause may last up to `WholeMapPauseMax` seconds.
  - Bigger maps build what's near you, then load the rest as you go.
  - The freeze comes in slices with one frame between them, so Roblox never stops the script.
- **Building tools work.** Parts spawned, cloned, dragged, resized or deleted (BTools, F3X, scripts)
  get their shadows updated by the next frame.
- **Moving things update every frame**: characters, unanchored parts, vehicles (one shadow job per
  assembly) and tweened parts. A part that stops moving goes back into the map's shadows.
- **Sun and moon.** Shadows follow the sun, or the moon at night. When neither is up they hide.
- **Lamps (2013 edition).** Where a lamp shines strongly (`LightPoolSize` of its Range), the sun's
  shadow is taken away, with a ring at half darkness around it (`LightFade`). Parts between the
  lamp and a surface keep a full shadow there, pointing away from the lamp. Switching, moving or
  changing a lamp redraws what it reaches.
- **Toggle** with 9. Turning it off hides the shadows and restores `Lighting.GlobalShadows`.

## Settings

All settings are in the `CONFIG` table at the top of the script.

| Setting | Default | What it does |
| --- | --- | --- |
| `RenderStyle` | `"Direct"` | `"Direct"`: see-through geometry with smooth edges, overlaps cut apart. `"Highlight"`: merged by one Highlight (jagged edges on phones; balls cost fewer parts). |
| `ShadowTransparency` | `0.6` | Shadow darkness with the Highlight style. Lower is darker. |
| `DirectTransparency` | `0.62` | Shadow darkness with the Direct style. |
| `ShadowColor` | black | Shadow color. |
| `RoundShading` | `"Blocky"` | Dark sides of balls and cylinders. `"Blocky"`: in steps, like the old engine. `"Smooth"`: along the real curve. `false`: Roblox's own shading. |
| `DynamicLights` | `false` (`true` in the 2013 edition) | Lamps light up shadows and cast their own there. |
| `LightPoolSize` | `0.6` | How much of a lamp's Range takes the shadow away fully. |
| `LightFade` | `true` | A ring at half darkness around each pool of light. |
| `LoadPause` | `true` | Freeze at the start so all shadows appear at once (no loading screen). |
| `LoadWholeMap` | `true` | Build the whole map in that pause and keep it, unless the map is bigger than the limits below. |
| `WholeMapParts` | `12000` | Most parts for a whole-map load with EditableMesh. |
| `PartsWholeMapParts` | `4000` | The same when drawing with parts. |
| `WholeMapPauseMax` | `20` | The longest the pause may last for a whole map, in seconds (`LoadPauseMax`, 5, otherwise). |
| `ShadowDistance` | `520` | On bigger maps, map shadows are kept within this many studs of the camera. |
| `PartsShadowDistance` | `300` | The same, when drawing with parts because EditableMesh is off. |
| `ShadeBackFaces` | `true` | Darken the sides of parts that face away from the sun. |
| `GlowingPartsStayLit` | `true` | Neon parts are never darkened. |
| `ExactSilhouettes` | `true` | On flat lit floors, characters cast their exact silhouette (ViewportFrame). |
| `MaxSilhouettes` | `4` | How many characters (nearest first) can have one at a time. |
| `AvatarOutlines` | `true` | Elsewhere, cast avatars' real outlines, using hidden hull copies of their meshes. |
| `ShadowsOnAvatars` | `true` | Darken avatars' body parts, heads, hair and hats. |
| `CharacterSurfaceOffset` | `0.012` | How far shadows float off characters (the map uses `SurfaceOffset`, 0.04). |
| `TransparentShadows` | `false` | See-through parts cast lighter shadows tinted with their color. |
| `MinShadowElevation` | `8` | A sun lower than this many degrees is raised, so shadows don't stretch forever. |
| `MaxShadowLength` | `600` | How far past its caster a shadow can reach. |
| `Backend` | `"Auto"` | `"EditableMesh"`, `"Parts"`, or automatic. |
| `FrameBudget` | `4.2` | Milliseconds of shadow work per frame. |
| `IgnoreAttribute` | `"NoStencilShadow"` | Set this attribute to `true` on a part or model to leave it out. |

On phones, lower `FrameBudget` (or `PartsWholeMapParts`) if the game feels heavy.

Other scripts can control it through `_G.StencilShadows`: `SetEnabled(bool)`, `Toggle()`,
`IsEnabled()`, `Rebuild()`, `GetStats()` and `Destroy()`. `GetStats().backend` says whether shadows
are drawn with `"EditableMesh"` or `"Parts"`, and `GetStats().wholeMap` whether the whole map is kept.

## How it works

1. **Light.** The script reads `Lighting:GetSunDirection()`, or the moon at night. It only rebuilds the
   map when the light moves more than `LightUpdateAngle` degrees.
2. **Casting.** Each caster's corners or curves give its outline as seen from the sun.
   - For every surface behind the caster (found with one `GetPartBoundsInBox` along the light),
     that outline is projected onto the surface's plane and clipped to the face.
   - If the caster sticks into the surface, only the part in front of it casts.
   - Shadows on terrain are draped over a small grid of raycasts.
3. **No stacking.** In the Direct style, each still part has a fixed place in line. A shadow on a
   surface has the shadows of the parts before it on that surface cut out of it (a polygon
   difference), and a moving part's shadow gives way to all still ones. When a part moves, the
   shadows that gave way to it are redrawn.
4. **Drawing.** The shadow polygons are split into triangles and written into EditableMesh pages,
   one per 256-stud cell. Without EditableMesh, each triangle becomes two wedge parts, each
   rectangle one thin block, and each trapezoid (a ball's facet) one block and two wedges.
   - Direct style: 62% transparent black Neon.
   - Highlight style: 99.9% transparent, painted by a Highlight (black fill, 0.6 transparency,
     Occluded). A Humanoid in the model makes the Highlight draw on such transparent parts.
5. **Lamps (2013 edition).** For each shadow polygon near a lamp, the lamp's pool of light on that
   plane is worked out (a disc, cut to the cone for spot and surface lights). The pool is cut out
   of the shadow, except where a part between the lamp and the surface casts a shadow from the
   lamp (projected from the lamp's position).
6. **Scheduling.** Still parts are bucketed into 64-stud chunks. On maps that aren't huge, every
   chunk is built in the start-up pause and kept. Otherwise chunks load nearest-first and unload
   when far away. Moving parts and characters have their own per-frame jobs.

## Indoors: how the old stencil shadows behaved

Sources:

- Roblox's 2012 engineering blog post
  ["Shadows on ROBLOX: Past, Present, and Future"](https://blogarchive.pages.dev/2012/10/shadows-on-roblox-past-present-and-future)
  describes the old shadow as "a darkened shadow with pixel-perfect edges", "essentially an extruded
  version of an object that darkens everything within it".
- The [Ogre 3D manual](https://www.ogre3d.org/docs/manual.old/manual_73.html) covers the engine
  family these shadows came from. It says this kind of shadow works "by darkening an already
  rendered scene with a fixed colour", and that it darkens "the areas of shadow uniformly,
  irrespective of the amount of light which would have fallen on the shadow area anyway".
- On the DevForum thread, PointLights are dated to March 2013 and the stencil shadows to early
  2014, so both were in the game for most of 2013.

What that means inside a building:

- **The roof's shadow covers the whole room.** Everything under it sits inside one shadow volume,
  so floors, walls, furniture and players all get the same, even darkening.
- **Shadows inside don't stack.** A player's shadow on a floor that is already in the roof's shadow
  doesn't show, because a spot is either in shadow or not.
- **Sunlight through windows and doors makes sharp bright patches.** These are the only lit areas
  indoors in the classic script.
- **Lamps.** In the classic script lamps are dimmed along with everything else, as the fixed-colour
  darkening did. The 2013 edition lets lamps light up the shadows around them.
- **Roblox's own lighting goes off.** Many games make interiors dark with Roblox's own shadows,
  which this script turns off (`DisableRobloxShadows`) so they don't double up outdoors.

## Known limits

- **Parts with `CanQuery` off don't receive shadows.** The surface search uses spatial queries, which
  skip them. They still cast.
- **Direct style.**
  - Shadows on terrain, and shadows from several parts landing on a character, can still overlap
    and look darker there.
  - Balls cost more parts than with the Highlight style (about 750 instead of 300 for a nearby
    tree top drawn with parts), because the ball-shaped middle would overlap the facets.
  - Building takes about twice the CPU time, because overlaps are cut on the CPU.
- **Highlight style.** Roblox draws at most 31 Highlights at once, and draws them without
  anti-aliasing ([DevForum feature request](https://devforum.roblox.com/t/anti-aliasing-for-highlight-instances/1862811)).
  The fully shaded character uses a Highlight in both styles.
- **Mesh data.** Reading a MeshPart's mesh needs permission for that asset, usually yours or your
  group's. Other meshes fall back to a raycast-sampled outline, which is convex, so holes in such
  meshes are filled in.
- **Receiving shadows on meshes.** MeshParts only receive shadows on their own surface when their
  mesh can be read and is small enough (`MeshReceiverTriangles`). Otherwise, flat meshes and unions
  use their bounding box.
- **Avatars.**
  - Away from a flat floor each body part casts its convex outline, so a gap inside one part
    (between hair spikes, say) is filled in there.
  - The silhouette is a texture, so its edges are a little softer. Layered clothing isn't part of
    it and isn't darkened.
  - In the light, a body part either darkens as a whole or only on its dark side. A shadow edge
    can't cut across it.
  - Hair and hats don't cast shadows on their own character.
  - Dynamic heads: Roblox's skinning wasn't available to test here. If a dynamic head's copy
    still doesn't draw, the whole-character Highlight still covers it in shade.
- **Lamps (2013 edition).** Only still parts cast shadows from lamps (not players). A lamp's pool
  is a disc or cone with one softer ring, not Roblox's exact falloff.
- **Not tested in Roblox itself.** The requester tests each version in a real game on a phone. The
  fixes in this version were checked with the Luau parser, linter and simulation suite below.

## Testing

The script was run unmodified in a simulated Roblox runtime: a Luau interpreter plus mocked engine
APIs whose property and method checks follow Roblox's API dump.

The 61 scenarios compare the shadow triangles it draws against independently computed projections.
They cover:

- Every shape, clipping, parts sunk into the floor, shadows falling 450 studs.
- Moving and resting parts, vehicles, removal, building tools.
- Characters: R6, R15, packages, blocky bodies, the classic head, first person, avatar outlines
  from hull copies, package avatars darkening in shadow, dark sides on heads.
- The exact silhouette (every body point's shadow lands at the same spot on the canvas and in the
  camera image), its fallbacks, and a floor made of two parts.
- Hair not blacking out its own head, hair getting its own shading, dynamic heads keeping their
  bones, and the one Highlight for a character entirely in shade.
- Blocky balls (each classic facet dark or lit as a whole, tight on the ball, the classic outline,
  dark all over under a roof), with EditableMesh and with parts.
- The Direct style: no overlaps anywhere on the floor, across floor tiles and after a part moves,
  and the same coverage as the Highlight style.
- Lamps in the 2013 edition (lit pool, softer ring, a crate's shadow from the lamp, switching off),
  and the classic script ignoring them.
- The start-up pause, whole-map loading (far islands built before the pause ends, nothing loading
  while flying around), and huge maps still streaming.
- The wedge-part fallback, exact concave meshes, ray-sampled meshes, terrain, sun, moon and night,
  oversized shadows split across pages, tight time budgets, streaming, EditableMesh memory running
  out, failed mesh loads, edges meeting without gaps, and Neon parts.
