# Classic Stencil Shadows for Roblox

A single LocalScript that recreates the hard, dark stencil shadows Roblox had from 2008 to 2013. It is
built the way the [real-time stencil shadow system on the DevForum](https://devforum.roblox.com/t/how-accurate-does-this-real-time-stencil-shadow-system-look-and-act-compared-to-the-old-stencil-shadows-roblox-used-to-have/4920633)
describes it. Shadows are exact polygons pushed along the sunlight onto every surface behind a part,
and overlapping shadows never get darker than a single shadow.

There are two scripts. They are the same script with one setting changed:

| Script | What it's like |
| --- | --- |
| [`src/StencilShadows.client.luau`](src/StencilShadows.client.luau) | **Classic** (2008 to early 2013). Only the sun and moon matter. Lamps are dimmed by shadows like everything else, as in the old engine. |
| [`src/StencilShadows2013.client.luau`](src/StencilShadows2013.client.luau) | **2013 edition.** PointLights arrived in March 2013 and stencil shadows stayed until early 2014. Lamps (PointLight, SpotLight, SurfaceLight) light up the shadows where they shine, with a softer ring around the light. Things standing in the light of a lamp whose `Shadows` is on still cast a shadow from the lamp there. (`DynamicLights = true`.) |

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
  - The middle of a ball's dark side is one ball-shaped part. When drawing with parts, a nearby
    size-8 tree top costs about 300 parts. (In the Direct style that part and the facets sit under
    a small Highlight of their own, so they can overlap.)
  - A ball's shadow on the ground has the classic facets' outline.
  - `RoundShading = "Smooth"` gives the smooth version instead.
- **Characters cast their shadow**, R6 and R15, with packages, hats, hair and tools.
  - Each part casts its real outline, rebuilt every frame the character moves, so the shadow
    stays at its feet. That outline comes from a hidden copy of each mesh with an exact
    convex-hull collision shape, traced once with raycasts. If a mesh can only be traced as a plain
    box (its real shape couldn't be read), it gets a rounded stand-in of its size instead, so a
    package never casts a blocky shadow.
  - On a computer, a player standing still on a flat floor in the light casts their exact
    silhouette instead: a black copy of the character drawn as seen from the sun, in a
    ViewportFrame on a SurfaceGui lying on the floor. Hair spikes, hats, clothing, tools and the
    exact pose all show, and the floor can be several parts side by side (tiles, plates). Roblox
    updates that GUI a little late, so a walking player's silhouette trailed behind them and
    jumped about: it's only used while standing still (`SilhouetteOnlyWhenStill`). Phones draw it
    blocky and late, so they always use the outlines (`SilhouettesOnPhones`).
  - When the silhouette is shown, the character draws nothing else on that floor, so there is
    never a double shadow. Where it can't work (the shadow crosses an edge or stairs, or mostly
    falls inside another shadow), the outlines are used.
  - Layered clothing (3D jackets, pants, shoes) casts no shadow of its own: its mesh only takes its
    shape on the body, so its outline was a shapeless blob. The body under it casts the shadow.
  - Default blocky bodies are real boxes and are drawn exactly, with corners. R6 limbs are blocks;
    an R15 limb is taken for a box when it has no mesh, when its mesh traces as a plain box, or
    (before it's traced, or if it can't be) when the player's avatar has no package for that limb.
    The script asks Roblox which limbs of each player's avatar come from a package (once per
    player, in the background). A package limb that only traces as a plain box (its real shape
    couldn't be read) gets a rounded stand-in instead, so a package never looks blocky. (The
    HumanoidDescription isn't used: its body part ids aren't sent to players' computers, so there
    they always read 0.)
- **Players have dark sides, and shadows land on them too.** Every visible part of an avatar gets
  its dark side from a copy of itself, about one part each, that just follows it. (In-game, the
  flat dark pieces drawn on avatars before didn't show at all, so the head and body looked
  unshaded. The copies are drawn far enough off the surface to show on phones and while the
  avatar animates.)
  - A block (R6 limbs and torso, the default blocky R15 body) gets a block that reaches out of
    every side facing away from the sun and stays just inside the sides facing it. Each dark side
    is darkened evenly, by the same rule as the old shadow volumes.
  - The classic head gets a copy of the head pushed away from the sun and turned to the nearest
    edge between the old head mesh's 16 sides (one facing straight ahead, like the chest). Its
    dark side steps round facet by facet as the sun or the player turns, and the face goes dark
    exactly when the chest does.
  - Package bodies, other heads, hair, hats and glasses get a copy of their real mesh, pushed away
    from the sun, so only the side facing away from it darkens.
  - Parts under layered clothing (a jacket over the torso and upper arms, pants over the legs,
    shoes) reach out further (`LayeredClothingThickness`), past the clothing.
  - Inside a shadow, the whole part darkens. Shadows that fall on blocks and the classic head are
    drawn exactly, for the three nearest players.
  - Dynamic heads keep their face bones in that copy, so it follows the face.
  - A character that is entirely in shade (indoors, under a roof) is darkened by one Highlight on
    the real avatar instead, so face, hair, hands and glasses all darken exactly. Only the nearest
    three get one (`MaxShadeHighlights`): Roblox draws 31 Highlights at most, the game's own
    included. Everyone else is darkened part by part.
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
  darker than one shadow. That includes a player's shadow over a building's shadow, one shadow
  across two floor tiles, and shadows from two things landing on a player. The pieces are as thin
  as Roblox allows (0.001 studs), so their sides don't show as lines along the seams. The old way,
  one Highlight, is still there (`RenderStyle = "Highlight"`), but Roblox draws Highlights without
  anti-aliasing, so their edges look jagged on phones.
- **Roblox's own shadows stay off.** `Lighting.GlobalShadows` goes off while the stencil shadows
  are on, and so does `Shadows` on lamps (PointLight, SpotLight, SurfaceLight), so Roblox's soft
  shadows never lie on top of these. This happens the moment the script starts. If the game
  switches either back on, it goes off again (checked every second as well). Key 9 (or removing the
  script) gives everything back.
- **Only where Roblox would have a shadow.**
  - A game that has its own shadows switched off (`Lighting.GlobalShadows` off when the script
    starts) gets no sun shadows from the script either, and a notice titled "Stencil Shadows" asks:
    "This game doesn't have shadows enabled. This script cannot work without shadows. Enable
    shadows anyway?" with Yes and No buttons. Yes draws the stencil shadows anyway; No (or letting
    the notice go) leaves the game without them. (`FollowGameShadows = false` always draws them.)
    If the game switches its shadows on later, the stencil shadows appear.
  - Parts with `CastShadow` off, see-through parts, ForceField parts, and parts a game hides on
    your screen only (`LocalTransparencyModifier`, like a roof that fades when you walk in) cast
    nothing.
  - Lamps (2013 edition) cast shadows only if their own `Shadows` is on, like in Roblox (it's off
    by default on new lights). A lamp with `Shadows` off still lights things up.
- **The whole map loads, in the background.** There is no start-up pause and no loading screen:
  the shadows near you appear within the first moments, and the rest of the map follows, nearest
  first, a little each frame, so the game doesn't freeze. Once a map is built it's kept, so
  nothing loads while you walk around. A map bigger than the limits (`WholeMapParts`, 12,000
  parts with EditableMesh; `PartsWholeMapParts`, 4,000 parts without) loads around you as you
  walk instead.
  - While it loads, a counter like Roblox's own notification boxes sits on the right of the screen
    (above the jump button on phones): "Stencil Shadows", "Loading shadows... 63%", how many
    parts are done ("1,234 of 1,950 parts") and a bar. Its Hide button puts it away; it slides
    away by itself once everything is built (`LoadingCounter = false` never shows it).
  - When everything is built, a notice titled "Stencil Shadows" says so: "Loading complete: the
    whole map's shadows are ready (12 s)." (On a map too big for that: "Loading complete: the
    shadows around you are ready (5 s). This map is too big to load all at once, so farther
    shadows load as you walk.") `LoadingMessage = false` turns it off.
  - The start-up pause from earlier versions is still there as `LoadPause`, off: freezing the game
    while loading made it laggy.
  - Floors made of parts with `CanQuery` off (often roads, decorations, or a visible floor over an
    invisible one) take shadows too. Roblox's spatial queries skip such parts, so the script keeps
    a grid of its own for them.
  - If a part's shadow fails to build (something unusual about it), it's tried again a few seconds
    later instead of being skipped for good.
  - On phones and tablets the script uses less time each frame (`MobileFrameBudget`), and the
    bigger loading budget is only used in the first seconds.
- **Building tools work.** Parts spawned, cloned, dragged, resized or deleted (BTools, F3X, scripts)
  get their shadows updated by the next frame.
- **Moving things update every frame**: characters, unanchored parts, vehicles (one shadow job per
  assembly) and tweened parts. You, the nearest other player and the two nearest moving things are
  redrawn every frame they move, however little time there is to spare, so their shadows never
  trail behind them; the rest when there's time. A part that stops moving goes back into the
  map's shadows. Faces of an avatar's blocks tucked inside another block (the legs' tops under
  the torso) get no shadows worked out, which keeps walking smooth.
- **Sun and moon.** Shadows follow the sun, or the moon at night. When neither is up they hide.
- **Lamps (2013 edition).** PointLights shine all around; SpotLights and SurfaceLights only inside
  their cone (`Angle`, `Face`). Where a lamp shines strongly (`LightPoolSize` of its Range), the
  sun's shadow is taken away, with a ring at half darkness around it (`LightFade`). If the light
  has `Shadows` on, parts between the lamp and a surface keep a full shadow there, pointing away
  from the lamp, and the ring doesn't stack on it. The same goes for shadows on terrain, round parts' dark sides, and
  characters: a player standing in a lamp's light gets no dark sides and no sun silhouette there.
  Switching, moving or changing a lamp redraws what it reaches.
- **Smooth while walking around.** Shadows that look the same at every level of detail (blocks on
  blocks) aren't rebuilt when you walk closer or further away, still parts' shadows under a moving
  player are worked out once instead of every frame, and the silhouette's floor check runs only
  when the shadow has moved.
- **Toggle** with 9. Turning it off hides the shadows and restores `Lighting.GlobalShadows`.
- **Something looks wrong?** Set `ShowDiagnostics = true` at the top of the script. A small box in
  the corner then says what the script sees: whether the sun (or the game's shadow setting) allows
  shadows, your avatar's parts and head, how many dark-side copies are showing, whether your floor
  shadow is the exact silhouette (and if not, why not), the number of Highlights in the game, and
  the last error. A screenshot of it shows what's going on.

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
| `LoadPause` | `false` | Freeze at the start until nearby shadows are built (off: it made joining laggy). |
| `LoadWholeMap` | `true` | Build the whole map in the background and keep it, unless it's bigger than the limits below. |
| `LoadingMessage` | `true` | A notice once the shadows have finished loading. |
| `LoadingCounter` | `true` | A counter (with a Hide button) on the right of the screen while they load. |
| `WholeMapParts` | `12000` | Most parts for a whole-map load with EditableMesh. |
| `PartsWholeMapParts` | `4000` | The same when drawing with parts. |
| `WholeMapPauseMax` | `20` | The longest the pause may last for a whole map, in seconds (`LoadPauseMax`, 5, otherwise). |
| `ShadowDistance` | `520` | On bigger maps, map shadows are kept within this many studs of the camera. |
| `PartsShadowDistance` | `300` | The same, when drawing with parts because EditableMesh is off. |
| `FollowGameShadows` | `true` | A game with its own shadows switched off (`Lighting.GlobalShadows`) gets no sun shadows either. |
| `ShadeBackFaces` | `true` | Darken the sides of parts that face away from the sun. |
| `GlowingPartsStayLit` | `true` | Neon parts are never darkened. |
| `ExactSilhouettes` | `true` | On flat lit floors, characters cast their exact silhouette (ViewportFrame). |
| `SilhouetteOnlyWhenStill` | `true` | Only while the player stands still (a walking player's would trail behind). |
| `SilhouettesOnPhones` | `false` | Phones draw it blocky and late, so they use the outlines. |
| `MaxSilhouettes` | `4` | How many characters (nearest first) can have one at a time. |
| `AvatarOutlines` | `true` | Elsewhere, cast avatars' real outlines, using hidden hull copies of their meshes. |
| `ShadowsOnAvatars` | `true` | Avatars' dark sides, and darkening where they stand in shadow. |
| `MaxShadeHighlights` | `3` | Characters (nearest first) fully in shade that get one Highlight; the rest are darkened part by part. |
| `CharacterSurfaceOffset` | `0.035` | How far shadows landing on characters float off them, plus 0.001 per stud of camera distance (the map uses `SurfaceOffset`, 0.04). |
| `CharacterShadeOffset` | `0.04` | How far a body part's dark side reaches out of it, plus 0.001 per stud of camera distance. |
| `LayeredClothingThickness` | `0.1` | How far it reaches out of parts under layered clothing. |
| `TransparentShadows` | `false` | See-through parts cast lighter shadows tinted with their color. |
| `MinShadowElevation` | `8` | A sun lower than this many degrees is raised, so shadows don't stretch forever. |
| `MaxShadowLength` | `600` | How far past its caster a shadow can reach. |
| `Backend` | `"Auto"` | `"EditableMesh"`, `"Parts"`, or automatic. |
| `FrameBudget` | `4.2` | Milliseconds of shadow work per frame. |
| `MobileFrameBudget` | `2.5` | The same on phones and tablets. |
| `LoadingTime` | `8` | Seconds after the start during which `LoadingBudget` (9 ms) may be used. |
| `IgnoreAttribute` | `"NoStencilShadow"` | Set this attribute to `true` on a part or model to leave it out. |
| `ShowDiagnostics` | `false` | A small box in the corner says what the script sees (to screenshot when something looks wrong). |

On phones, lower `MobileFrameBudget` or `PartsShadowDistance` if the game still feels heavy.

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
6. **Scheduling.** Still parts are bucketed into 64-stud chunks that load nearest-first, a few
   milliseconds each frame. Maps within the whole-map limits are built completely and kept; on
   bigger ones, chunks unload when far away.
   Moving parts and characters have their own per-frame jobs.

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

- **Parts with `CanQuery` off** take and cast shadows, but the raycast checks (whether a player
  stands in shade, whether a spot is lit) don't see them.
- **Direct style.**
  - Shadows on terrain, and shadows from several parts landing on a character, can still overlap
    and look darker there.
  - Balls' dark sides use a small Highlight of their own (with parts), so their stepped edge isn't
    anti-aliased.
  - Building takes about twice the CPU time, because overlaps are cut on the CPU.
- **Highlight style.** Roblox draws at most 31 Highlights at once, and draws them without
  anti-aliasing ([DevForum feature request](https://devforum.roblox.com/t/anti-aliasing-for-highlight-instances/1862811)).
  A fully shaded character uses a Highlight in both styles (the nearest three at most). If the
  game itself uses many Highlights, the balls' dark-side layer (one Highlight) may not be drawn.
- **Mesh data.** Reading a MeshPart's mesh needs permission for that asset, usually yours or your
  group's. Other meshes fall back to a raycast-sampled outline, which is convex, so holes in such
  meshes are filled in.
- **Receiving shadows on meshes.** MeshParts only receive shadows on their own surface when their
  mesh can be read and is small enough (`MeshReceiverTriangles`). Otherwise, flat meshes and unions
  use their bounding box.
- **Avatars.**
  - Each body part casts its convex outline, so a gap inside one part (between hair spikes, say)
    is filled in. That's the shadow on phones, and on a computer while the player walks or stands
    off a flat floor.
  - The exact silhouette (computers, standing still) is a texture, so its edges are a little
    softer. Layered clothing isn't part of it.
  - Layered clothing has no copy of its own (it only takes its shape on the body). The parts under
    it reach out by `LayeredClothingThickness` instead: a puffier coat can still hide that, and a
    tight shirt shows it floating a hair off the cloth up close.
  - A pushed copy pokes out past the outline of a head or mesh a little on its dark side
    (about 0.05 studs up close).
  - Package bodies, hair and hats: in the light, they either darken as a whole or only on their
    dark side; a shadow edge can't cut across them. (Blocks and the classic head take exact
    shadows, for the three nearest players.)
  - Hair and hats don't cast shadows on their own character.
  - Dynamic heads: Roblox's skinning wasn't available to test here. If a dynamic head's copy
    still doesn't draw, the whole-character Highlight still covers it in shade.
- **Lamps (2013 edition).** Only still parts cast shadows from lamps (not players), and only lamps
  whose `Shadows` was on. A lamp's pool is a disc or cone with one softer ring, not Roblox's exact
  falloff. Lamps' own Roblox shadows are switched off, since these replace them.
- **Following the game's shadows.** Only the game's setting when the script starts, or switching
  shadows on later, is seen: a game that switches its shadows off later (say at night) keeps the
  stencil shadows, because the script keeps Roblox's own off already.
- **Not tested in Roblox itself.** The requester tests each version in a real game on a phone. The
  fixes in this version were checked with the Luau parser, linter and simulation suite below, on a
  rebuilt copy of the requester's avatar (R15 blocky body, classic head, spiky hair, sunglasses,
  layered jacket).

## Testing

The script was run unmodified in a simulated Roblox runtime: a Luau interpreter plus mocked engine
APIs whose property and method checks follow Roblox's API dump.

The 88 scenarios compare the shadow triangles it draws against independently computed projections.
They cover:

- Every shape, clipping, parts sunk into the floor, shadows falling 450 studs.
- Moving and resting parts, vehicles, removal, building tools.
- Characters: R6, R15, packages, blocky bodies (found by their missing meshes, not the
  HumanoidDescription), the classic head, first person, avatar outlines from hull copies, package
  avatars darkening in shadow. Dark sides: block copies reaching out of exactly the sides facing
  away from the sun, the head's copy turned to a facet edge with the face going dark together with
  the chest, no flat pieces on dark sides, and a full avatar with spiky hair, sunglasses and a
  layered jacket (parts under the jacket reach past it, the jacket casts no blob).
- The exact silhouette (every body point's shadow lands at the same spot on the canvas and in the
  camera image), its fallbacks, and a floor made of two parts.
- Hair not blacking out its own head, hair getting its own shading, dynamic heads keeping their
  bones, the one Highlight for a character entirely in shade (the nearest three at most).
- Blocky balls (each classic facet dark or lit as a whole, tight on the ball, the classic outline,
  dark all over under a roof), with EditableMesh and with parts.
- The Direct style: no overlaps anywhere on the floor, across floor tiles, after a part moves, on
  players, and between a lamp's ring and its shadows; the same coverage as the Highlight style;
  0.001-stud pieces; balls with their ball-shaped middle.
- Lamps in the 2013 edition (lit pool, softer ring, a crate's shadow from the lamp, switching off,
  spot and surface lights lighting only their cone, a player in a lamp's light, a light with
  `Shadows` off lighting things up without casting shadows), the classic script ignoring them, and
  lamps' own Roblox shadows switched off and back on with key 9.
- A game with its own shadows off getting none, with the notice's exact words (and getting them
  once it switches them on), and the diagnostics box.
- A walking player's shadow at their feet every frame (the silhouette only once they stand
  still), phones using the outlines, the nearest moving thing's shadow keeping up with it with no
  time to spare, a package whose meshes can only be traced as boxes not casting a blocky shadow,
  and hidden faces of an avatar's blocks skipped.
- The whole map loading in the background with no pause (far islands too), the "Loading complete"
  notice said exactly once, and a map too big for that saying so; the loading counter counting up,
  hiding with its button, and going once loading is complete.
- The no-shadows notice's Yes and No buttons.
- A blocky player whose limbs have box meshes casting boxes, whether the meshes can be traced or
  not, and a package limb that only traces as a box casting a rounded stand-in.
- Walking around a kept map: only shadows that depend on the level of detail are rebuilt.
- No pause by default (shadows and Roblox's shadows switched off from the first frames), Roblox's
  shadows switched back off within a second when a script sneaks them on, floors with `CanQuery`
  off taking shadows, ForceField and locally hidden parts casting nothing, the silhouette coming
  back after a game clears the PlayerGui; and, switched on, the start-up pause, whole-map loading
  and huge maps still streaming.
- The wedge-part fallback, exact concave meshes, ray-sampled meshes, terrain, sun, moon and night,
  oversized shadows split across pages, tight time budgets, streaming, EditableMesh memory running
  out, failed mesh loads, edges meeting without gaps, and Neon parts.
