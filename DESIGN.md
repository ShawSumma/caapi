# Design

Working notes. Records intent, not implementation. Lines marked **?** are
unresolved or are my inference and may be wrong.

## Premise

A psychedelic art game about making drugs out of whole voxels, and about
perception. The player is the machine — rather than placing machines that work
on your behalf, you do the work yourself and your performance is what repeats.

The reference points are pharmacological rather than chemical. Serotonin and
the tryptamines as a family of near-variants. The kappa opioid receptor as the
sharper case: there is the ligand you'd expect, and then there are the
salvinorins, which are structurally unlike it and work anyway. The game wants
that shape — a right answer, a spread of things that are almost right, and
occasionally a novel solution that doesn't resemble the expected one.

It is not a chemistry simulation. Voxels, not molecules.

## The world

Hyperbolic space, order-4 dodecahedral honeycomb ({5,3,4}). Already built.
It does two jobs: it supplies the disorienting visuals, and it is a space where
shape and fit behave against intuition.

There are no entities. Nothing in the world is not a voxel with a color — the
player included.

## Two simulations

These are separate systems, at least for now:

- **World simulation** — voxels in space, pushing, gluing, the CA.
- **Chem simulation** — what elements are and what they do together.

Unifying them is desirable but needs a mechanism that actually works. The
black-substrate idea below is a step toward that.

## Elements

Each real value is an element. Reaction rules are **not** derived from color —
an element's color is how it is perceived, not what it is. Rules are
deliberately undecided; they are not to be worked out yet.

Some elements rotate. Some affect perception — swirl and similar — and several
can be active at once.

**?** Whether "rotate" is a world-space behavior (voxels physically turning) or
a perceptual effect is unclear to me.

### Black

Black is a real voxel and is inert.

Chemistry is only simulated where things touch black across at least a 2×2
region. Black is the medium the reaction happens in.

This is also what makes a block CA tractable here. A Margolus-style partition
normally needs a globally consistent two-phase 2×2 grid, which this honeycomb
fights — chunks meet mirrored with permuted axes, flipping block parity across
a seam. Restricting simulation to black-adjacent 2×2 regions means space is
never globally tiled, only locally, where a valid block exists.

**?** Whether there is still such a thing as empty space, distinct from black.

## Color: five channels, three levels

A voxel is five channels, each at one of three levels. 3^5 = 243, which is the
entire state of a voxel and fits in a byte. That is the point of the "under
256" constraint: a voxel is one byte and nothing else.

This is pentachromacy. No channel is "red." A channel's identity is its index.

Two of the 243 are reserved: black (all channels zero) is inert, and white
(all channels maximum) is the player. 241 elements remain.

Further reserved values — other "holes" punched in the space — are an open
option, not a commitment.

### Perception

Five channels have to be seen through three primaries. Collisions are therefore
forced — no colour space separates all 241 elements. Which things look alike is
a property of what you are perceiving with, not of the elements.

Drugs change the mapping. That is what "the colors being managed by the
drugs/manufacture itself" means: you make a thing, you take it, you see
differently. Rotation and swirl sit in the same category — perceptual state
driven by what is active, several at a time.

Mappings are not a palette you pick from. A *field* selects between them across
the view, so perception is not uniform — the same element reads differently
depending on where it falls in the field, and the field moves. A spiral is one
such field; reaction-diffusion is another. The field is screen-space rather
than world-space, which is the right frame for something happening in the
observer rather than in the place.

Per-voxel noise (position hash, ±15% brightness) breaks up flat surfaces.
It currently hashes chunk-local position, so the pattern repeats per chunk.

### The rotation space

A colour space is not an entry in a list. It is made live, and the space of
them is continuous.

Channels 0, 1 and 2 drive red, green and blue. Channels 3 and 4 start out of
sight. Turning three channels about the diagonal they share relabels which
channel drives which primary:

- a third of a turn about (a,b,c): a→green, b→blue, c→red
- a third of a turn about (a,b,d): a→green, b out of sight, c→blue, d→red
- a sixth of a turn stops between primaries — that is where the secondaries are
- every angle in between is a valid space, and none of them is a listed option

Bringing a hidden channel into view necessarily pushes another out, because
there are only three primaries. That is where metamerism comes from, and it is
forced by the arithmetic rather than arranged by hand.

The diagonal is the rotation axis, so it is fixed. All-max stays white and
all-zero stays black at every angle, which keeps the two reserved values
reserved without a special case anywhere.

Several rotations compose, and composition does not commute — so combination
and order matter, which is where discoverability lives.

### What drives it

The three rotations are driven independently, so a field with three natural
components — triplanar weights, a surface normal — turns each separately
instead of pushing one scalar through all three.

Anything screen-space is wrong on its own: it slides over the terrain like a
film rather than belonging to it. The vertex stage carries chunk-local position
and the chunk-local face normal, which is what an anchored field needs.

**Chunk-local is the only stable frame.** Any frame built from a chunk's
`transform` is expressed relative to whichever node the camera currently
occupies, so the instant the player crosses into the next node every transform
is rebuilt and the whole field jumps at once. A frame that is merely shared
across chunks is not enough; it has to be shared across *time* as well, and
only chunk-local coordinates are. The same applies to the winding flip in the
vertex shader — it keys off a camera-relative determinant, so the face axis has
to be read before the flip or the normals move with the player.

Two orthogonal choices: what fills the field texture, and how it is sampled.

**Producer**, `--trip none|diffusion|rps`:

- **diffusion** — Gray-Scott. Thin filaments, needs a wide blur to be usable.
- **rps** — cyclic cellular automaton, rock/paper/scissors generalised to N
  states: a cell in state s is eaten by neighbours in state s+1, so nothing is
  ever stable and it organises into travelling waves and spirals. Threshold is
  the sensitive parameter — at 1 it sweeps and organises, at 3 it sticks in a
  metastable speckle that never resolves. The state is stored as a unit vector
  rather than an index so filtering and blurring take a circular mean and the
  wrap costs nothing. Being cyclic suits driving a rotation: a driver running
  0→1 and wrapping is one full turn of the colour space, with no seam.

Both producers step at a rate per second rather than per frame, so speed does
not track framerate. They also both start from noise and need hundreds of steps
to organise while wanting to crawl afterwards, so that cost is paid once as a
warm-up at seed time instead of making the player watch static resolve.

**Sampling**, `--field N`:

- **0 screen** — reaction-diffusion in screen space. Slides. Kept for contrast.
- **1 triplanar** — the same reaction-diffusion projected onto surfaces, blended
  by the normal, with each axis driving a different rotation. The pattern wraps
  the terrain and stays put as the camera moves.
- **2 volume** — 3D noise filling space that the terrain is carved out of, so
  the pattern belongs to the place rather than to any surface.
- **3 normal** — orientation alone. Every face direction is its own colour
  space, so what you read is the form.
- **4 raw** — debug. Puts the field straight on screen with no rotation and no
  blur, so a producer can be judged on its own rather than through the terrain.

**?** Chunk-local sampling and a shared field texture do not currently
compose. Every chunk samples the same patch, so either the whole field is
crushed into each chunk and aliases into speckle, or it is magnified and every
chunk is identical. Screen-space sampling has neither problem and shows the
producers at their best, but slides over the terrain. Resolving this needs a
stable per-chunk offset into the field — the same node-ID plumbing noted above.

Calibration is per-mode and not interchangeable: the reaction-diffusion field
has a range near 0–0.15 and needs a large gain, while noise and normals are
already 0–1 and saturate instantly if that same gain is applied.

**Normals are not transported at all.** A chunk's transform is a Lorentz
isometry and its linear part is not a rotation — it shears — so pushing a face
direction through it gives a different vector in every chunk. There is no
global parallel frame in hyperbolic space to fix that in. The face axis is
therefore used raw, in chunk-local coordinates, where it is exact and never
moves.

**The field is sampled in node-local space.** Chunks tile physical space, so
there is a real 3D coordinate to use — the mistake was choosing a frame that
was either too small (chunk-local, which tiles because every chunk reads the
same patch) or not fixed to anything (camera-relative, which jumps on node
crossings). A node's frame is both: it spans all 20 of its chunks continuously,
and it belongs to the node rather than the viewer, so it never moves.

The 20 chunk-to-node isometries are constant and uploaded once; the vertex
stage puts a chunk-local position through the one indexed by the chunk's vertex
number. Chunk identity reaches the shader as a single per-instance uint —
vertex number in the low 5 bits, a hash of the node id above — on the same
instance rate as the transform, so it is indexed identically whatever the draw
does with firstInstance. The node hash offsets where each node reads the field,
so nodes differ from each other while staying continuous within themselves.

Seams remain at node boundaries, but nodes are twenty chunks apiece.

The shape of the world and a distance field should also feed **the diffusion**
itself, not just the rotation: geometry steering where the pattern forms. Not
built. Gray-Scott's feed and kill rates are the obvious entry point, since
varying them spatially changes which regime forms where.

**Built.** A voxel value decodes as five base-3 digits. Three diagonal
rotations are applied to those five levels — over (0,1,2), (0,1,3) and
(2,3,4) — and channels 0, 1, 2 are then read off as red, green, blue. There is
no palette table anywhere; `C` walks the resting angle in sixths of a turn.

The field is a texture, and that is the seam. `PerceptionField`
(`client/graphics/field.d`) owns a pair of 512² images and a compute pipeline;
the voxel shader samples the result and knows nothing about what produced it.
Swapping producers means writing a different compute shader and changing
nothing downstream.

The first producer is Gray-Scott reaction-diffusion (`shaders/reaction.comp`),
ping-ponged an even number of steps per frame so the result always lands in the
same image and the sampling descriptor never has to change. The lattice wraps,
so the field is toroidal and tiles seamlessly over any viewport. Enabled with
`--trip`; without it a single static mapping is used, cycled with `C`.

The activator is confined to thin curves, so it is blurred at sample time to
spread those into broad domains. Knobs: `feed`/`kill`/`stepsPerFrame` on the
field, `tripGain` and `tripScale` on the renderer, blur radius in the shader.
Feed/kill is a narrow window — most pairs die out to a flat field.

The sky is a clear colour rather than a voxel, so the field does not touch it.

## The player as machine

The loop is counted in actions, not seconds. The player chooses the length —
any power of two — to suit what they are doing. A move is an action and takes
one slot; the loop is that many slots long. You act, the loop closes, your
actions replay as a clone, and you record the next layer over the top.

Reference point is The Last Clockwinder, on a fixed grid.

Because length is action-count rather than wall-clock, replay is exact — no
timestep floats to drift. (The current `--record`/`--replay` format is
frame-and-dt based, which is the wrong shape for this.)

Clones are white voxels, same as the player.

## Making

A body pushes one voxel. Gluing is done by pushing voxels into each other
across a 5-join, so it takes as many bodies as there are voxels being joined:
two at minimum, and up to about five at a corner.

This is the hinge. The loop is not a convenience for automating drudgery — it
is the only way to apply force in more than one place at once. Loop length is
chosen to fit the join being attempted, which is why it is the player's call
rather than a global constant.

## Discoverability

The target feel: one right answer, many near-misses that do *something* rather
than nothing, and rarer novel solutions that look wrong and work. Near-misses
should read as near-misses — the player should be able to tell they are close.

## UI

Unresolved.

One observation to argue with: the loop needs little UI because clones are
already visible, and perception is a state you are in rather than a setting —
both push toward diegetic presentation instead of panels. The counter-pressure
is that hyperbolic space is disorienting on its own, so a fully diegetic UI may
be too harsh.

## Open questions

- Is a 5-join the pentagonal face of the dodecahedral cell? Where does "up to
  five" come from geometrically — five voxels meeting at a corner?
- Are the three levels ordered (0 < 1 < 2, so shading means something), or
  three unordered states a mapping assigns colors to?
- Is element rotation a world behavior or a perceptual one?
- Is there empty space distinct from black?
- What determines an element's placement at worldgen? `Material` is vestigial —
  materials were rejected, but worldgen still writes that enum.
