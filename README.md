# Classic Stencil Shadows for Roblox

A single LocalScript that recreates the hard, dark stencil shadows Roblox had from 2008 to 2013. It is
built the way the [real-time stencil shadow system on the DevForum](https://devforum.roblox.com/t/how-accurate-does-this-real-time-stencil-shadow-system-look-and-act-compared-to-the-old-stencil-shadows-roblox-used-to-have/4920633)
describes it. Shadows are exact polygons pushed along the sunlight onto every surface behind a part.
They are written into EditableMeshes and painted by one Highlight, so overlapping shadows never get
darker than a single shadow.

Script: [`src/StencilShadows.client.luau`](src/StencilShadows.client.luau)

## Setup

1. In Studio, add a **LocalScript** to `StarterPlayer > StarterPlayerScripts` and paste the script in.
2. Recommended: open **Game Settings > Security** and turn on **Allow Mesh / Image APIs**. Roblox
   blocks EditableMesh in published games unless this is on. Without it, the script draws the same
   shadows with thin parts instead, which works but costs more, so its default range is shorter.
3. Play. Press **9** to switch between Roblox's shadows and the stencil shadows.

## What it does

- **Every opaque part casts**: blocks, wedges, corner wedges, balls, cylinders, capsules, special
  meshes (sphere, cylinder, head, wedge), unions, and MeshParts.
  - Mesh shadows use the real triangles when the mesh can be read, so concave shapes such as arches
    and L-shapes keep their holes.
  - If a mesh can't be read, its outline is sampled with raycasts instead.
- **Characters cast their real silhouette**, R6 and R15, with packages, hats, hair and tools.
  - Most games don't let scripts read avatar meshes, and give avatars plain box collisions. But any
    script may create a copy of a mesh with an exact convex-hull collision shape. The script makes
    one hidden copy per mesh, outlines it with raycasts, and casts each body part's real outline.
  - Until an outline has loaded (a second or two after an avatar appears), or if it can't be
    loaded, a part casts a rounded block of its real size.
  - Default blocky bodies (R6, and R15 with the default body) are real boxes and are drawn exactly.
- **Shadows land on players too.**
  - Blocky bodies take exact shadows, cut where a shadow's edge crosses them, and their sides away
    from the sun are dark. These sit 0.012 studs off the body, so they don't look oversized.
  - On package avatars, a body part inside a shadow gets a slightly larger invisible copy in the
    shadow model, so the same Highlight darkens exactly that part's real shape.
  - Nothing that doesn't match the avatar's real shape is drawn on it, so no dark cubes stick out.
  - Zoomed into first person, your own character's shadows disappear along with it, as they do
    with Roblox's shadows.
- **Shadows land on everything behind the caster.**
  - That includes floors, walls, roofs, slopes, round parts, meshes, terrain, and other players.
  - A shadow continues from the floor up a wall and over a box, and is cut exactly at each
    surface's edge.
  - The sides of parts that face away from the sun are darkened too, as they were inside the old
    shadow volumes.
  - Shadows on two faces that meet at an edge meet exactly, with no thin lit line between them.
  - On balls, cylinders and capsules the dark side sits just off the real curve and ends in a smooth
    line exactly where the surface turns away from the sun. It doesn't float off the part or follow
    blocky facets.
  - Glowing (Neon) parts give off light, so shadows don't darken them.
- **Moving things update every frame.**
  - Characters, unanchored parts, vehicles (one shadow job per assembly), and tweened parts all
    update.
  - A part that stops moving goes back into the cheaper map shadows after `RestTime` seconds.
- **Shadows on moving things.** A player walking under a roof gets the roof's shadow on them. Loose
  parts get shadows drawn on them too.
- **Sun and moon.** Shadows follow the sun, or the moon at night. When neither is up they hide.
- **A short pause at the start, then everything at once.** There is no loading screen. The game
  waits for your character, then freezes for a moment while every shadow near you is built. Then
  all of them appear in the same frame that Roblox's own shadows switch off.
  - The freeze comes in slices of `LoadPauseSlice` seconds with one frame between them, so Roblox
    never stops the script for running too long. It never lasts more than `LoadPauseMax` seconds.
  - After that, new parts are built nearest-first within a per-frame budget (`FrameBudget`, 4.2 ms
    by default), and faraway shadows use simpler curves.
- **Toggle** with 9. Turning it off hides the shadows and restores `Lighting.GlobalShadows`.

## Settings

Everything is in the `CONFIG` table at the top of the script. The most useful settings:

| Setting | Default | What it does |
| --- | --- | --- |
| `ShadowTransparency` | `0.6` | Shadow darkness (Highlight fill transparency). Lower is darker. |
| `ShadowColor` | black | Shadow color. |
| `ShadowDistance` | `520` | Map shadows are kept within this many studs of the camera. |
| `PartsShadowDistance` | `300` | The same, when drawing with parts because EditableMesh is off. |
| `ShadeBackFaces` | `true` | Darken the sides of parts that face away from the sun. |
| `CurvedShading` | `"Auto"` | Smooth dark sides on round parts. `"Auto"` does all round parts with EditableMesh, and only cylinders when drawing with parts, because balls would need too many parts. |
| `GlowingPartsStayLit` | `true` | Neon parts are never darkened. |
| `AvatarOutlines` | `true` | Cast avatars' real outlines, using hidden hull copies of their meshes. |
| `ShadowsOnAvatars` | `true` | Darken package avatars' body parts when they stand in a shadow. |
| `CharacterSurfaceOffset` | `0.012` | How far shadows float off characters (the map uses `SurfaceOffset`, 0.04). |
| `LoadPause` | `true` | Freeze briefly at the start so all nearby shadows appear at once (no loading screen). |
| `LoadPauseMax` | `5` | The longest the start-up pause may last, in seconds. |
| `TransparentShadows` | `false` | See-through parts cast lighter shadows tinted with their color. |
| `MinShadowElevation` | `8` | A sun lower than this many degrees is raised, so shadows don't stretch forever. |
| `MaxShadowLength` | `600` | How far past its caster a shadow can reach. |
| `RenderStyle` | `"Highlight"` | `"Direct"` draws plain see-through black instead. Overlaps then stack, but it doesn't need a Highlight slot. |
| `Backend` | `"Auto"` | `"EditableMesh"`, `"Parts"`, or automatic. |
| `FrameBudget` | `4.2` | Milliseconds of shadow work per frame. |
| `IgnoreAttribute` | `"NoStencilShadow"` | Set this attribute to `true` on a part or model to leave it out. |

On phones, lower `ShadowDistance` and `FrameBudget` if the game feels heavy.

Other scripts can control it through `_G.StencilShadows`: `SetEnabled(bool)`, `Toggle()`,
`IsEnabled()`, `Rebuild()`, `GetStats()` and `Destroy()`. `GetStats().backend` says whether shadows
are drawn with `"EditableMesh"` or `"Parts"`.

## How it works

1. **Light.** The script reads `Lighting:GetSunDirection()`, or the moon at night. It only rebuilds the
   map when the light moves more than `LightUpdateAngle` degrees.
2. **Casting.** Each caster's corners or curves give its outline as seen from the sun.
   - For every surface behind the caster (found with one `GetPartBoundsInBox` along the light),
     that outline is projected onto the surface's plane and clipped to the face.
   - If the caster sticks into the surface, only the part in front of it casts.
   - Shadows on terrain are draped over a small grid of raycasts.
3. **Drawing.** The shadow polygons are split into triangles and written into EditableMesh pages,
   one per 256-stud cell.
   - The meshes are 99.9% transparent black Neon. A Highlight (black fill, 0.6 transparency, no
     outline, Occluded) paints the whole model in one pass, so overlaps merge instead of stacking.
   - A Humanoid in the model makes the Highlight draw on such transparent parts.
   - Without EditableMesh, each triangle becomes two wedge parts and each rectangle one thin block,
     under the same Highlight.
4. **Scheduling.** Still parts are bucketed into 64-stud chunks that load nearest-first and unload
   when far away. Moving parts and characters have their own per-frame jobs. When a surface moves or
   is removed, the shadows drawn on it are rebuilt right away.

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

What that means inside a building:

- **The roof's shadow covers the whole room.** Everything under it sits inside one shadow volume,
  so floors, walls, furniture and players all get the same, even darkening. A flat, evenly grey
  interior is what real stencil shadows look like.
- **Shadows inside don't stack.** A player's shadow on a floor that is already in the roof's shadow
  doesn't show, because a spot is either in shadow or not.
- **Sunlight through windows and doors makes sharp bright patches.** These are the only lit areas
  indoors, and the script draws them because every wall and roof part casts its exact shape.
- **Lamps can't light up shadows.** The darkening is one fixed colour over everything. Old Roblox
  had no lamps, but in today's games (horror games especially) lamps indoors get dimmed along with
  the rest. Glowing Neon parts are left bright.
- **Roblox's own lighting goes off.** Many games make interiors dark with Roblox's own shadows,
  which this script turns off (`DisableRobloxShadows`) so they don't double up outdoors. If you'd
  rather keep a game's own dark interiors, set it to `false`, but then outdoor shadows get darker
  where both overlap.

## Known limits

- **Parts with `CanQuery` off don't receive shadows.** The surface search uses spatial queries, which
  skip them. They still cast.
- **Highlights.** Roblox draws at most 31 Highlights at once. A game that already uses that many can
  hide the shadows; switch `RenderStyle` to `"Direct"` in that case.
- **Mesh data.** Reading a MeshPart's mesh needs permission for that asset, usually yours or your
  group's. Other meshes fall back to a raycast-sampled outline, which is convex, so holes in such
  meshes are filled in.
- **Receiving shadows on meshes.**
  - MeshParts only receive shadows on their own surface when their mesh can be read and is small
    enough (`MeshReceiverTriangles`).
  - Otherwise, flat meshes and unions use their bounding box.
- **Avatars.**
  - Each body part's outline is convex, so a gap inside one part (between fingers, say) is filled
    in. Gaps between parts, like between the legs, show.
  - On package avatars a body part darkens as a whole when it's mostly in shadow. A shadow edge
    can't cut across the part, and its side away from the sun isn't darkened separately.
  - Layered clothing isn't darkened.
- **Jagged edges on phones.** Roblox draws Highlights without anti-aliasing, so shadow edges look a
  little pixelated, mostly on mobile
  ([DevForum feature request](https://devforum.roblox.com/t/anti-aliasing-for-highlight-instances/1862811)).
  `RenderStyle = "Direct"` gives smooth edges, but overlapping shadows then get darker.
- **Balls drawn with parts.** Without EditableMesh, the dark side of a ball keeps Roblox's own
  shading, because drawing it would take hundreds of parts per ball. Cylinders still get theirs.
- **Light sources.** Only the sun and the moon cast shadows, not PointLights or SpotLights.
- **Tested in a real game on a phone** by the requester. This version fixes what that showed: the
  avatar shadow, cubes on the player, thin lines along edges, round parts, first person, and the
  start-up. The fixes themselves were checked with the Luau parser, linter and simulation suite
  below, not in Roblox.

## Testing

The script was run unmodified in a simulated Roblox runtime: a Luau interpreter plus mocked engine
APIs whose property and method checks follow Roblox's API dump.

The 43 scenarios compare the shadow triangles it draws against independently computed projections.
They cover every shape, clipping, sunk casters, moving and resting parts, vehicles, removal,
characters (R6, R15, packages, blocky bodies, the classic head, first person), the toggle key, the
wedge-part fallback, exact concave meshes, ray-sampled meshes, terrain, sun, moon and night,
oversized shadows split across pages, tight time budgets, streaming, EditableMesh memory running
out, failed mesh loads, edges meeting without gaps, round parts without gaps or floating, Neon
parts, the start-up pause, avatar outlines from hull copies, package avatars darkening in shadow,
tight shading on blocky players, shadows falling 450 studs, and parts sunk into the floor.
