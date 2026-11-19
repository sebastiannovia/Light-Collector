# Gameplay systems

The gameplay components are under `gameplay/`. The main scene adds an `ItemDatabase` and a `PlayerInventory` component to the player. Inventory data is held by the component; its UI is generated separately and reads the inventory's public API and change signal.

## Define an item

1. Duplicate `gameplay/items/item_definition_template.tres` into `gameplay/items/`.
2. Set its unique `item_id`, display name, description, maximum stack size, and maximum carry quantity.
3. Assign `icon` for the inventory. Assign `world_texture` for the PNG shown in the world; if it is empty, the world drop uses `icon` instead. Tune `inventory_icon_scale`, `world_texture_scale`, `world_texture_offset`, and `world_color` as needed.
4. Add the new path to `ItemDatabase.definition_paths` on the main scene's `ItemDatabase` node. The starter items are loaded automatically.

The inventory limits are read from each definition. Adding a new item does not require changing inventory or drop logic. The starter definitions include Wood, Stone, Iron, Wild Berry, Forest Mushroom, and Glow Herb. The last three are editable examples; assign their PNGs and inventory icons in the resource Inspector.

## Inventory API

Call methods on the player's `PlayerInventory` node:

- `add_item(item_id, quantity)` returns the amount accepted. The unaccepted remainder stays with the caller.
- `remove_item(item_id, quantity)` removes that exact quantity only when available.
- `get_item_quantity(item_id)`, `has_item(item_id, quantity)`, and `can_add_item(item_id, quantity)` query inventory state.
- `get_slots()` returns a copy of the slot data.
- `inventory_changed`, `item_added`, `item_removed`, and `item_add_failed` are emitted for observers.

The grid dimensions are the `rows` and `columns` exports on `PlayerInventory`. Press **I** to toggle its window. Drag the window by its header; its position persists while the game runs.

## Player HUD

The top-left HUD shows Health, Sleep, then Lights. Its visual settings are in `gameplay/player_hud_default.tres`; change its position, panel and bar sizes, labels, fonts, colors, icon sizes, notification position, duration, and notification appearance from the `Player HUD Style` resource on the Player. Duplicate that resource first if you want a separate style for another player.

Health and Sleep currently start at the exported `health_current` and `sleep_current` values. Gameplay systems can update the bars through `set_health(value)` and `set_sleep(value)`. Each successful inventory addition creates a temporary notification at the left-center of the screen, including its icon when one is configured.

## Collectibles and harvested resources

Use `gameplay/item_drop.tscn` as a configurable collectible object placed in an area. Set its `Item Definition`, quantity, and pickup radius in the Inspector. The assigned resource controls its name, description, inventory image, world PNG, scale, offset, stack limits, and fallback color. It is added directly to the inventory when the player comes close. Any amount the inventory cannot accept stays on that placed collectible.

Harvesting does not create ground drops. When a rock or tree is fully mined/chopped, its Stone or Wood is added directly to the inventory. If the inventory is full, the last hit remains available; if only part of the yield fits, the object keeps the remaining amount until there is space.

For resources granted by gameplay code, call `inventory.add_item(&"wild_berry", 4)`. Set the definition's optional `drop_scene` only when a placed collectible needs a custom scene; otherwise it uses the shared `item_drop.tscn`.

The main scene includes a sample `HarvestableRock` in Main Base. Press **E** nearby four times to mine it; three Stone are added directly to the inventory. Its scene exports let you change the required hits, interaction range, and stone yield.

`gameplay/Gatherables/harvestable_tree.tscn` is a separate tree gatherable. Add PNG textures to its **Tree Appearance → Tree Textures** array; each instance randomly chooses one when it enters the scene. With no textures assigned, it draws a simple placeholder tree. Adjust `tree_scale`, `texture_offset`, required hits and `wood_quantity` on the instance. Press **E** nearby to chop it and receive Wood.

To make a forest, select an area node and use **Forest Scatter**. `Forest Atlas Source ID` defaults to `1`, the `forest_atlas.png` source in `ForestMapTiles.tres`. `Forest Tile Names` chooses which `forest_variant` values can receive trees, such as `straight_grass`, `mini_grass`, or `long_grass_02`; clear the list to allow all variants. Set the number of trees, minimum spacing, tile-edge margin, scale range, rotation range, and seed, then press **Scatter Trees on Matching Tiles**. Set the seed to `0` for a new random layout each time, or another number to repeat a layout. **Clear Scattered Trees** removes only trees made by this scatter tool. Each tree still selects a PNG from its `Tree Textures` list.

When the player is behind a tree, its `tree_occlusion.gdshader` fades a soft circular area around the player. Tune **Occlusion Radius** and **Occlusion Edge Softness** on the tree instance.

## Construction

Instance `gameplay/construction_site.tscn` and set its `construction_config_path` to a `ConstructionConfig` resource. The sample is `gameplay/construction/tower_config.tres`, with three configurable stages. Each `ConstructionStage` has an ordered array of `ItemRequirement` resources, plus an optional visual scene and fallback color.

The site draws a compact requirements bubble above its separate deposit marker. The prompt appears only while the player is in range. Press **E** to deposit matching resources for the current stage; unrelated items and amounts beyond the remaining requirement are left in the inventory. Signals report deposits, stage completion and final completion. Outside an interactive site's range, **E** retains the existing path-light behavior.
