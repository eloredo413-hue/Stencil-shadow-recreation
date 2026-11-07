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
  - Characters cast too, including tools and accessories.
- **Shadows land on everything behind the caster.**
  - That includes floors, walls, roofs, slopes, round parts, meshes, terrain, and other players.
  - A shadow continues from the floor up a wall and over a box, and is cut exactly at each
    surface's edge.
  - The sides of parts that face away from the sun are darkened too, as they were inside the old
    shadow volumes.
- **Moving things update every frame.**
  - Characters, unanchored parts, vehicles (one shadow job per assembly), and tweened parts all
    update.
  - A part that stops moving goes back into the cheaper map shadows after `RestTime` seconds.
- **Shadows on moving things.** A player walking under a roof gets the roof's shadow on them. Loose
  parts get shadows drawn on them too.
- **Sun and moon.** Shadows follow the sun, or the moon at night. When neither is up they hide.
- **Loads without freezing the game.**
  - The map is read in time-limited slices and grouped into chunks.
  - Shadows are built nearest-first within a per-frame budget (`FrameBudget`, 4.2 ms by default).
  - Faraway shadows use simpler curves.
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
| `TransparentShadows` | `false` | See-through parts cast lighter shadows tinted with their color. |
| `MinShadowElevation` | `8` | A sun lower than this many degrees is raised, so shadows don't stretch forever. |
| `MaxShadowLength` | `200` | How far past its caster a shadow can reach. |
| `RenderStyle` | `"Highlight"` | `"Direct"` draws plain see-through black instead. Overlaps then stack, but it doesn't need a Highlight slot. |
| `Backend` | `"Auto"` | `"EditableMesh"`, `"Parts"`, or automatic. |
| `FrameBudget` | `4.2` | Milliseconds of shadow work per frame. |
| `IgnoreAttribute` | `"NoStencilShadow"` | Set this attribute to `true` on a part or model to leave it out. |

On phones, lower `ShadowDistance` and `FrameBudget` if the game feels heavy.

Other scripts can control it through `_G.StencilShadows`: `SetEnabled(bool)`, `Toggle()`,
`IsEnabled()`, `Rebuild()`, `GetStats()` and `Destroy()`.

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
  - R15 body parts receive shadows only when their mesh can be read; blocky R6 bodies always do.
- **Light sources.** Only the sun and the moon cast shadows, not PointLights or SpotLights.
- **Not yet run in Roblox.** The script was checked with a Luau parser and linter, and with the
  26-scenario simulation suite described below. Two things can only be confirmed in a real game:
  how the Highlight draws on 99.9% transparent parts, and EditableMesh memory budgets on your
  devices.

## Testing

The script was run unmodified in a simulated Roblox runtime: a Luau interpreter plus mocked engine
APIs whose property and method checks follow Roblox's API dump.

The 26 scenarios compare the shadow triangles it draws against independently computed projections.
They cover every shape, clipping, sunk casters, moving and resting parts, vehicles, removal,
characters (R6 and R15), the toggle key, the wedge-part fallback, exact concave meshes, ray-sampled
meshes, terrain, sun, moon and night, oversized shadows split across pages, tight time budgets,
streaming, EditableMesh memory running out, and failed mesh loads.
