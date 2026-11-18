# Gameplay systems

The gameplay components are under `gameplay/`. The main scene adds an `ItemDatabase` and a `PlayerInventory` component to the player. Inventory data is held by the component; its UI is generated separately and reads the inventory's public API and change signal.

## Define an item

1. Create a `ItemDefinition` resource, for example `gameplay/items/wood.tres`.
2. Set its unique `item_id`, display name, maximum stack size, maximum carry quantity, optional icon and world color.
3. Add the resource path to `ItemDatabase.definition_paths`.

The inventory limits are read from each definition. Adding a new item does not require changing inventory or drop logic. The current sample definitions are Wood, Stone and Iron.

## Inventory API

Call methods on the player's `PlayerInventory` node:

- `add_item(item_id, quantity)` returns the amount accepted. The unaccepted remainder stays with the caller.
- `remove_item(item_id, quantity)` removes that exact quantity only when available.
- `get_item_quantity(item_id)`, `has_item(item_id, quantity)`, and `can_add_item(item_id, quantity)` query inventory state.
- `get_slots()` returns a copy of the slot data.
- `inventory_changed`, `item_added`, `item_removed`, and `item_add_failed` are emitted for observers.

The grid dimensions are the `rows` and `columns` exports on `PlayerInventory`. Press **I** to toggle its window. Drag the window by its header; its position persists while the game runs.

## World drops

Call `ItemDropSpawner.spawn_item_drop(&"wood", 4, world_position)` from another gameplay object. The catalog definition must exist. The drop automatically collects near the player. If the inventory accepts only part (or none), the same drop stays in the world with the remaining quantity.

The main scene includes a sample `HarvestableRock` in Main Base. Press **E** nearby four times to mine it; it drops three Stone items. Its scene exports let you change the required hits, interaction range and stone yield. Harvestable objects can use this same drop method when their own action succeeds.

`gameplay/Gatherables/harvestable_tree.tscn` is a separate tree gatherable. Add PNG textures to its **Tree Appearance → Tree Textures** array; each instance randomly chooses one when it enters the scene. With no textures assigned, it draws a simple placeholder tree. Adjust `tree_scale`, `texture_offset`, required hits and `wood_quantity` on the instance. Press **E** nearby to chop it and receive Wood.

To make a forest, select an area node and use **Forest Scatter**. `Forest Atlas Source ID` defaults to `1`, the `forest_atlas.png` source in `ForestMapTiles.tres`. `Forest Tile Names` chooses which `forest_variant` values can receive trees, such as `straight_grass`, `mini_grass`, or `long_grass_02`; clear the list to allow all variants. Set the number of trees, minimum spacing, tile-edge margin, scale range, rotation range, and seed, then press **Scatter Trees on Matching Tiles**. Set the seed to `0` for a new random layout each time, or another number to repeat a layout. **Clear Scattered Trees** removes only trees made by this scatter tool. Each tree still selects a PNG from its `Tree Textures` list.

When the player is behind a tree, its `tree_occlusion.gdshader` fades a soft circular area around the player. Tune **Occlusion Radius** and **Occlusion Edge Softness** on the tree instance.

## Construction

Instance `gameplay/construction_site.tscn` and set its `construction_config_path` to a `ConstructionConfig` resource. The sample is `gameplay/construction/tower_config.tres`, with three configurable stages. Each `ConstructionStage` has an ordered array of `ItemRequirement` resources, plus an optional visual scene and fallback color.

The site draws a compact requirements bubble above its separate deposit marker. The prompt appears only while the player is in range. Press **E** to deposit matching resources for the current stage; unrelated items and amounts beyond the remaining requirement are left in the inventory. Signals report deposits, stage completion and final completion. Outside an interactive site's range, **E** retains the existing path-light behavior.
