package player

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
Inventory :: struct {
	items:          [12]Item,
	selected_index: int,
	is_extended:    bool,
}

Item :: struct {
	id:           ItemID,
	name:         string,
	texture:      rl.Texture,
	position:     rl.Vector2,
	rotation:     f32,
	state:        ItemState,
	quantity:     int,
	float_height: f32,
	float_speed:  f32,
	base_y:       f32,
	time_offset:  f32,
	on_pickup:    proc(_: ^ItemManager, _: ^Item),
}

ItemID :: distinct string

ItemManager :: struct {
	items:    [dynamic]^Item,
	textures: map[ItemID]rl.Texture2D,
}

ItemState :: enum {
	Ground,
	Floating,
	PickedUp,
}

init_inventory :: proc() -> Inventory {
	inventory := Inventory {
		selected_index = 0,
		is_extended    = false,
	}
	return inventory
}

handle_inventory_input :: proc(player: ^Player, item_manager: ^ItemManager) {
	mouse_pos := rl.GetMousePosition()

	slot_size: int = 64
	padding: int = 10
	start_x: int = 20
	max_items_row: int = 6

	if rl.IsKeyPressed(.TAB) {
		player.inventory.is_extended = !player.inventory.is_extended
	}

	if player.inventory.is_extended {
		show_extended_inventory(
			player,
			slot_size,
			padding,
			max_items_row,
			start_x,
			mouse_pos,
			item_manager,
		)
	} else {
		hide_extended_inventory(player, slot_size, padding, start_x, mouse_pos, item_manager)
	}

	// Number key shortcuts for quick selection
	if rl.IsKeyPressed(.ONE) do player.inventory.selected_index = 0
	if rl.IsKeyPressed(.TWO) do player.inventory.selected_index = 1
	if rl.IsKeyPressed(.THREE) do player.inventory.selected_index = 2
	if rl.IsKeyPressed(.FOUR) do player.inventory.selected_index = 3
	if rl.IsKeyPressed(.FIVE) do player.inventory.selected_index = 4
}

draw_inventory :: proc(inventory: Inventory) {
	slot_size: int = 64
	padding: int = 10
	start_x: int = 20
	start_y: int = int(rl.GetScreenHeight()) - slot_size - 20
	max_slots: int = 5

	for i in 0 ..< max_slots {
		slot_x := start_x + i * (slot_size + padding)
		slot_rect := rl.Rectangle {
			x      = f32(slot_x),
			y      = f32(start_y),
			width  = f32(slot_size),
			height = f32(slot_size),
		}

		// Draw slot background
		rl.DrawRectangleRec(slot_rect, rl.GRAY)

		// Draw item if exists
		if i < len(inventory.items) {
			item := inventory.items[i]
			if item.texture.id != 0 && item.quantity > 0 {
				scale := f32(slot_size) / f32(item.texture.width)
				rl.DrawTextureEx(item.texture, {slot_rect.x, slot_rect.y}, 0.0, scale, rl.WHITE)

				// Draw quantity
				if item.quantity > 1 {
					quantity_text := fmt.tprintf("%d", item.quantity)
					text_size := rl.MeasureTextEx(
						rl.GetFontDefault(),
						strings.clone_to_cstring(quantity_text),
						20,
						1,
					)
					rl.DrawText(
						strings.clone_to_cstring(quantity_text),
						i32(slot_x + slot_size - int(text_size.x) - 5),
						i32(start_y + slot_size - int(text_size.y) - 5),
						20,
						rl.WHITE,
					)
				}
			}
		}

		// Draw selection highlight
		if i == inventory.selected_index {
			rl.DrawRectangleLinesEx(slot_rect, 2, rl.YELLOW)
		}
	}
}

init_item_manager :: proc() -> ^ItemManager {
	manager := new(ItemManager)
	manager.items = make([dynamic]^Item)
	manager.textures = make(map[ItemID]rl.Texture2D)
	return manager
}

spawn_item :: proc(
	manager: ^ItemManager,
	id: ItemID,
	position: rl.Vector2,
	on_pickup: proc(_: ^ItemManager, _: ^Item) = nil,
) -> ^Item {
	if _, ok := manager.textures[id]; !ok {
		return nil
	}

	item := new(Item)
	item^ = Item {
		id           = id,
		position     = position,
		state        = .Floating,
		float_height = 10, // Pixels to float up and down
		float_speed  = 2.0,
		base_y       = position.y,
		time_offset  = f32(rl.GetTime()),
		quantity     = 1,
		texture      = manager.textures[id],
		on_pickup    = on_pickup,
	}

	append(&manager.items, item)
	return item
}

update :: proc(manager: ^ItemManager) {
	current_time := f32(rl.GetTime())

	for item in manager.items {
		if item.state == .Floating {
			// Create floating animation
			time_factor := (current_time - item.time_offset) * item.float_speed
			item.position.y = item.base_y + item.float_height * math.sin(time_factor)

			// Rotate the item slowly
			item.rotation += 90.0 * rl.GetFrameTime() // Degrees per second
		}
	}
}

load_item_resources :: proc(manager: ^ItemManager, id: ItemID, texture_path: cstring) {
	texture := rl.LoadTexture(texture_path)
	manager.textures[id] = texture
}

draw :: proc(manager: ^ItemManager) {
	for item in manager.items {
		if item.state != .PickedUp {
			// Get the texture from the manager
			texture := manager.textures[item.id]
			if texture.id != 0 {
				origin := rl.Vector2{f32(texture.width) / 2, f32(texture.height) / 2}

				source_rect := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}

				dest_rect := rl.Rectangle {
					item.position.x,
					item.position.y,
					f32(texture.width),
					f32(texture.height),
				}

				rl.DrawTexturePro(texture, source_rect, dest_rect, origin, item.rotation, rl.WHITE)
			}
		}
	}
}

pick_up_item :: proc(manager: ^ItemManager, player: ^Player, pickup_range: f32) -> ^Item {
	for item in manager.items {
		if item.state != .PickedUp {
			distance := rl.Vector2Distance(player.position, item.position)
			if distance <= pickup_range {
				item.state = .PickedUp

				// Find an empty slot or stack with existing items
				for i := 0; i < len(player.inventory.items); i += 1 {
					inv_item := &player.inventory.items[i]

					// Stack with existing item
					if inv_item.id == item.id && inv_item.quantity > 0 {
						inv_item.quantity += 1
						if item.on_pickup != nil {
							item.on_pickup(manager, item)
						}
						return item
					}

					// Find empty slot
					if inv_item.quantity == 0 {
						inv_item^ = Item {
							id       = item.id,
							name     = item.name,
							quantity = 1,
							texture  = item.texture,
							state    = .PickedUp,
						}

						if item.on_pickup != nil {
							item.on_pickup(manager, item)
						}
						return item
					}
				}
			}
		}
	}
	return nil
}

drop_item :: proc(player: ^Player, item_manager: ^ItemManager, item_index: int) {
	if item_index >= len(player.inventory.items) {
		return
	}

	item := &player.inventory.items[item_index]
	if item.quantity <= 0 {
		return
	}

	// Calculate drop position slightly to the right of the player
	drop_position := rl.Vector2 {
		player.position.x + 50, // 50 pixels to the right
		player.position.y, // Same Y level as player
	}

	spawned_item := spawn_item(item_manager, item.id, drop_position)
	if spawned_item != nil {
		spawned_item.state = .Floating
		spawned_item.texture = item.texture
		spawned_item.name = item.name
		spawned_item.quantity = 1
	}

	item.quantity -= 1
	if item.quantity == 0 {
		clear_item(item)
	}
}

clear_item :: proc(item: ^Item) {
	item.name = ""
	item.quantity = 0
	item.id = ""
}

unload_resources :: proc(manager: ^ItemManager) {
	for _, texture in manager.textures {
		rl.UnloadTexture(texture)
	}

	delete(manager.items)
	delete(manager.textures)
	free(manager)
}


show_extended_inventory :: proc(
	player: ^Player,
	slot_size: int,
	padding: int,
	max_items_row: int,
	start_x: int,
	mouse_pos: [2]f32,
	item_manager: ^ItemManager,
) {


	start_y := int(rl.GetScreenHeight()) - (slot_size * 6 + padding * 5) - 20
	max_slots := 36

	for slot_index := 0; slot_index < max_slots; slot_index += 1 {
		row := slot_index / max_items_row
		col := slot_index % max_items_row

		slot_x := start_x + col * (slot_size + padding)
		slot_y := start_y + row * (slot_size + padding)

		slot_rect := rl.Rectangle {
			x      = cast(f32)slot_x,
			y      = cast(f32)slot_y,
			width  = cast(f32)slot_size,
			height = cast(f32)slot_size,
		}

		rl.DrawRectangleRec(slot_rect, rl.GRAY)
		if rl.CheckCollisionPointRec(mouse_pos, slot_rect) {
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				player.inventory.selected_index = slot_index
				if slot_index < len(player.inventory.items) {
					item := player.inventory.items[slot_index]
					use_item(player, slot_index)
				}
			} else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
				if slot_index < len(player.inventory.items) {
					item := &player.inventory.items[slot_index]
					drop_item(player, item_manager, slot_index)
				}
			}
		}
	}


}

use_item :: proc(player: ^Player, item_index: int) {
	if item_index >= len(player.inventory.items) {
		return
	}

	item := &player.inventory.items[item_index]
	if item.quantity <= 0 {
		return
	}

	// Handle different item types
	switch item.name {
	case "Health Potion":
		// Apply healing effect
		item.quantity -= 1
		// If quantity reaches 0, you might want to clear the item
		if item.quantity == 0 {
			clear_item(item)
		}
	case "Wooden Axe":
		item.quantity -= 1
		// If quantity reaches 0, you might want to clear the item
		if item.quantity == 0 {
			clear_item(item)
		}
	}
}


hide_extended_inventory :: proc(
	player: ^Player,
	slot_size: int,
	padding: int,
	start_x: int,
	mouse_pos: [2]f32,
	item_manager: ^ItemManager,
) {
	start_y := int(rl.GetScreenHeight()) - slot_size - 20
	max_slots := 5

	for i in 0 ..< max_slots {
		slot_x := start_x + i * (slot_size + padding)
		slot_rect := rl.Rectangle {
			x      = cast(f32)slot_x,
			y      = cast(f32)start_y,
			width  = cast(f32)slot_size,
			height = cast(f32)slot_size,
		}

		if rl.CheckCollisionPointRec(mouse_pos, slot_rect) {
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				player.inventory.selected_index = i
				if i < len(player.inventory.items) {
					item := player.inventory.items[i]
					if item.quantity > 0 {
						use_item(player, i)
					}
				}
			} else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
				if i < len(player.inventory.items) {
					item := &player.inventory.items[i]
					if item.quantity > 0 {
						drop_item(player, item_manager, i)
					}
				}
			}
		}
	}

}
