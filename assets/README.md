# Assets

`kit/` holds the prop kit as GLB files (boulder, rock_outcrop, pine_tree, dead_tree,
summit_cairn, spring, driftwood, shrub). Generated 31 Oct 2026 via Higgsfield (Tripo
text-to-3D), ~2-3k triangles each, real-world metres. Download
`river-royale-asset-kit-v1.zip` from the Higgsfield media library and unzip its
`models/` folder here as `kit/`.

`world/PropScatter.gd` scatters them by terrain rules and skips any that are missing,
so the game runs without them.

Blender exports (glTF) for hand-made assets go here too.
