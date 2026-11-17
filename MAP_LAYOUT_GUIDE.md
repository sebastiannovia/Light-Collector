# Godot map layout template

Open `MapLayoutTemplate.tscn` in Godot. The connected areas are visible side by side in the editor. During play, only the current area is visible; using an enabled path fades to the next area. Move the player with **WASD** or the arrow keys.

Each area is one continuous **3840 × 2160** block. The camera view is **1940 × 1080** and follows the player.

## Add, resize, and connect areas

- To add an area, select a node under `MapAreas` and duplicate it. The copy includes its ground and world art layers.
- Move the copy near a side of an existing area. With `snap_to_neighbors` enabled (default), it snaps to the nearest edge and aligns the centers when it is within `snap_distance` (default **96** units).
- To resize an area, select it and edit `area_size` in the Inspector. Neighboring areas remain where they are; drag them near the new edge to snap them into place.
- The `path_north`, `path_east`, `path_south`, and `path_west` switches enable one opening on that side. Its `*_path_offset_tiles` control moves it in whole `grid_step` increments from the midpoint; **0** keeps it exactly centered as the area is resized. The editor guide is centered on the area boundary, with half of its depth on each side.
- To add more openings, add tile indices to `north_path_tiles`, `east_path_tiles`, `south_path_tiles`, or `west_path_tiles` in the Inspector. These extra openings remain tile-aligned. Indices start at **0** from the left edge for north/south paths and from the top edge for east/west paths.
- Resizing an area redraws its path guides at the new edges without moving the area. Neighbor snapping happens when moving the area.
- Connect adjacent areas by aligning the world positions of openings on their facing sides. Matching tile indices work for extra openings when the areas share the same grid alignment. The player can cross only where both sides have an aligned opening.
- `path_width` defaults to 256 units and rounds to a whole number of grid cells.
- Delete an area by selecting its node under `MapAreas` and pressing **Delete**.

## Paint the placeholder tiles

Each area has two `TileMapLayer` children: `GroundArt` and `WorldArt`. The shared `MapTiles.tres` already contains 16 plain-color 256 × 256 placeholder tiles.

1. Select `GroundArt` under the area you want to edit.
2. Open the **TileMap** panel at the bottom of Godot, choose a color tile, and paint in the 2D view.
3. Use `WorldArt` for objects that need to draw in front of or behind the player based on their vertical position. It has Y-sorting enabled.

To replace the placeholders later, add the finished 256 × 256 tile sheet to the project. In `MapTiles.tres`, replace the atlas texture and use a **256 × 256** texture region size. Regenerate the atlas tiles from the texture in the TileSet editor so the palette matches the new art.

Godot's `TileMapLayer` paints tiles from a shared `TileSet`, and separate layers help order ground and objects independently. See the [Godot TileMap guide](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html).

The area height of 2160 is not divisible by 256. The last tile row is partial; leave it empty or change the area height to a multiple of 256, such as 2304, if you want a full row.

## Forest tiles

`Tiles/Forest Tiles/ForestMapTiles.tres` combines the existing placeholder atlas with the 12 forest images in a 4 × 3 atlas. Each cell is 256 × 256. The original atlas remains source ID `0`; the forest atlas is source ID `1`, so existing painted cells keep their coordinates. To use it, select a `GroundArt` or `WorldArt` layer and assign `ForestMapTiles.tres` to its **Tile Set** property. Forest variants also carry their original filename in the `forest_variant` custom data field.

## Hand-drawn minimap

The minimap reveals the starting area and adds each new area after its transition. It draws rough ink outlines, discovered exits, room labels, and a player marker on a paper-colored panel. Press **M** to hide or show it.

Select `Player` in the Scene dock to adjust the minimap in the Inspector under **Minimap**:

- `minimap_corner` and `minimap_offset` set its screen position.
- `minimap_panel_size`, `minimap_padding`, and `minimap_map_scale` control its size and how much of the area layout fits inside it.
- `minimap_room_gap`, `minimap_line_width`, and `minimap_line_wobble` control the sketch appearance.
- Assign `minimap_handwritten_font` if you have a handwritten font; otherwise it uses Godot's default font.
- `minimap_reveal_duration`, `minimap_show_area_names`, and `minimap_show_unknown_paths` control discovery and labels.

Edit the paper, ink, and player-marker colors at the top of `minimap_control.gd`; the game now uses those values directly. To color rooms by biome or type, select each area node and set `minimap_color` under its **Minimap** group in the Inspector. Give areas of the same type the same color.

Discovery is kept for the current run. The minimap uses each area's editor position and exit settings, so it follows the map layout as you move or add areas.

## Ground saturation

Each area applies `floor_saturation.gdshader` to its `GroundArt` layer during gameplay. Adjust **Ground Appearance → Floor Saturation** on an area; `1.0` keeps the original colors and `1.15` is the default subtle boost. `WorldArt` is not affected.

## Placing path lights

Stand on a `Path` tile and press **E** to place lights inside that same tile. A straight path gets two lights perpendicular to the route, a four-way crossing gets one in each corner, and a tile with three Path neighbors gets one on the side without a Path neighbor. The game spends 1 Light per lamp, and a path tile can only be lit once.

The placeholder atlas marks `Path` at source ID `0`, atlas coordinate `(0, 3)`. Each area can override this under **Path Lights** in the Inspector. For a replacement atlas, update those values to the new Path tile. If the TileSet has a custom data layer named `tile_type`, setting the tile's value to `Path` takes precedence over the atlas coordinates.
