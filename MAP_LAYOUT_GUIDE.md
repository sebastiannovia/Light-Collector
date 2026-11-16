# Godot map layout template

Open `MapLayoutTemplate.tscn` in Godot. The connected areas are visible side by side in the editor. During play, only the current area is visible; using an enabled path fades to the next area. Move the player with **WASD** or the arrow keys.

Each area is one continuous **3840 × 2160** block. The camera view is **1940 × 1080** and follows the player.

## Add, resize, and connect areas

- To add an area, select a node under `MapAreas` and duplicate it. The copy includes its ground and world art layers.
- Move the copy near a side of an existing area. With `snap_to_neighbors` enabled (default), it snaps to the nearest edge and aligns the centers when it is within `snap_distance` (default **96** units).
- To resize an area, select it and edit `area_size` in the Inspector. Neighboring areas remain where they are; drag them near the new edge to snap them into place.
- To make a connection, enable the matching paths on both areas. For an east connection, set `path_east` on one area and `path_west` on its neighbor. The player can use the exit only when both paths align and are enabled.
- Change the centered opening with `path_width`. Delete an area by selecting its node under `MapAreas` and pressing **Delete**.

## Paint the placeholder tiles

Each area has two `TileMapLayer` children: `GroundArt` and `WorldArt`. The shared `MapTiles.tres` already contains 16 plain-color 256 × 256 placeholder tiles.

1. Select `GroundArt` under the area you want to edit.
2. Open the **TileMap** panel at the bottom of Godot, choose a color tile, and paint in the 2D view.
3. Use `WorldArt` for objects that need to draw in front of or behind the player based on their vertical position. It has Y-sorting enabled.

To replace the placeholders later, add the finished 256 × 256 tile sheet to the project. In `MapTiles.tres`, replace the atlas texture and use a **256 × 256** texture region size. Regenerate the atlas tiles from the texture in the TileSet editor so the palette matches the new art.

Godot's `TileMapLayer` paints tiles from a shared `TileSet`, and separate layers help order ground and objects independently. See the [Godot TileMap guide](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html).

The area height of 2160 is not divisible by 256. The last tile row is partial; leave it empty or change the area height to a multiple of 256, such as 2304, if you want a full row.
