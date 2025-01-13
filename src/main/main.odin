package main

import "../constants"
import "../menu"
import perf "../performance"
import "../pkg"
import pl "../player"
import rl "vendor:raylib"

game_state :: struct {
	player:       pl.Player,
	item_manager: ^pl.ItemManager,
	pause:        bool,
	menu:         menu.Menu,
	platforms:    []rl.Rectangle,
}

main :: proc() {
	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "SkyWays")
	defer rl.CloseWindow()

	game_state := init_game()
	defer cleanup_game(&game_state)

	rl.SetTargetFPS(60)
	pkg.init_logger()
	defer pkg.destroy_logger()

	for !rl.WindowShouldClose() {
		if game_state.menu.is_active {
			if !menu.update_menu(&game_state.menu) {
				game_state.menu.is_active = false
				continue
			}
			menu.draw_menu(&game_state.menu)
		} else {
			update_game(&game_state)
			render_game(&game_state)
		}
	}
}

init_game :: proc() -> game_state {
	perf.init_performance_tracking()

	item_manager := pl.init_item_manager()
	platforms := make([]rl.Rectangle, 4)

	platforms[0] = rl.Rectangle {
		x      = 0,
		y      = f32(constants.SCREEN_HEIGHT - 100),
		width  = f32(constants.SCREEN_WIDTH),
		height = 100,
	}

	platforms[1] = rl.Rectangle {
		x      = 300,
		y      = f32(constants.SCREEN_HEIGHT - 250),
		width  = 200,
		height = 20,
	}

	platforms[2] = rl.Rectangle {
		x      = 100,
		y      = f32(constants.SCREEN_HEIGHT - 400),
		width  = 200,
		height = 20,
	}

	platforms[3] = rl.Rectangle {
		x      = 500,
		y      = f32(constants.SCREEN_HEIGHT - 550),
		width  = 200,
		height = 20,
	}


	game_state := game_state {
		player       = pl.init_player(),
		item_manager = item_manager,
		pause        = false,
		menu         = menu.create_menu(),
		platforms    = platforms,
	}

	return game_state
}

update_game :: proc(game_state: ^game_state) {
	if game_state == nil || game_state.item_manager == nil {
		return
	}

	if game_state.pause do return

	pl.player_update(&game_state.player, game_state.platforms)
	if game_state.item_manager != nil {
		pl.update(game_state.item_manager)

		if rl.IsKeyPressed(.E) {
			pickup_range := f32(50.0)
			picked_item := pl.pick_up_item(
				game_state.item_manager,
				&game_state.player,
				pickup_range,
			)
		}
	}
}

render_game :: proc(game_state: ^game_state) {
	if game_state == nil {
		return
	}

	camera := pkg.init_camera(&game_state.player)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKBLUE)

	rl.BeginMode2D(camera)
	{
		pl.player_render(&game_state.player)
		draw_game(&game_state.player)

		// Only draw items if item manager exists
		if game_state.item_manager != nil {
			pl.draw(game_state.item_manager)
		}
	}
	rl.EndMode2D()

	screen_text := pkg.format_screen_text(&game_state.player)

	if game_state.item_manager != nil {
		pl.handle_inventory_input(&game_state.player, game_state.item_manager)
		pl.draw_inventory(game_state.player.inventory)
	}

	rl.DrawText(screen_text["coords"], 10, 10, 10, rl.BLACK)

	perf.update_performance_stats()
	perf.draw_performance_overlay()
}

draw_game :: proc(player: ^pl.Player) {
	// Add any additional game world drawing here
}

cleanup_game :: proc(game_state: ^game_state) {
	if game_state == nil {
		return
	}

	pl.unload_player(&game_state.player)

	if game_state.item_manager != nil {
		pl.unload_resources(game_state.item_manager)
	}

	menu.cleanup_menu(&game_state.menu)
}
