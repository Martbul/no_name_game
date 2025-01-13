package main

import "../constants"
import "../menu"
import "../pkg"
import pl "../player"
import rl "vendor:raylib"

game_state :: struct {
	player: pl.Player,
	//item_manager: ^pl.ItemManager,
	pause:  bool,
	//npcs:         [dynamic]^npc.NPC,
	menu:   menu.Menu,
}


main :: proc() {
	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "SkyWays")
	game_state := init_game()

	pkg.init()
	defer pkg.destroy()

	defer cleanup_game(&game_state)
	defer rl.CloseWindow()

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
init_game :: proc() -> Game_State {
	perf.init_performance_tracking()
	//	textures.init_custom_material()
	//	textures.init_terrain_elements()
	//	textures.init_concrete_elements()
	terrain_models.init_terrain_elements()
	game_state := Game_State {
		player       = pl.init_player(),
		item_manager = pl.init_item_manager(),
		pause        = false,
		npcs         = make([dynamic]^npc.NPC),
		menu         = menu.create_menu(),
	}

	pl.load_item_resources(
		game_state.item_manager,
		"wooden_axe",
		"assets/wooden_axe/wooden_axe_1k.gltf",
		"assets/wooden_axe/wooden_axe.png",
	)

	patrol_points := []rl.Vector3{{5, 0, 5}, {15, 0, 5}, {15, 0, 15}, {5, 0, 15}}
	texture_paths_1 := []cstring {
		"assets/models/bots/spartan/material_0_diffuse.jpeg",
		"assets/models/bots/spartan/material_0_occlusion.png",
		"assets/models/bots/spartan/material_0_specularGlossiness.png",
	}
	npc1 := npc.create_npc(
		"assets/models/bots/spartan/scene.gltf",
		texture_paths_1,
		rl.Vector3{5, 0, 5},
		patrol_points,
	)
	//texture_paths_2 := []cstring {
	//	"assets/npc_diffuse.png", // Main color/diffuse texture
	//	"assets/npc_normal.png", // Normal map (if using)
	//	"assets/npc_specular.png", // Specular map (if using)
	//}
	//npc2 := npc.create_npc(
	//	"assets/models/bots/ghost_cod/scene.gltf",
	//	texture_paths_2,
	//	rl.Vector3{5, 0, 5},
	//	patrol_points,
	//)


	append(&game_state.npcs, npc1)
	//	append(&game_state.npcs, npc2)

	pl.spawn_item(game_state.item_manager, "wooden_axe", {7, 2, 4})
	pl.spawn_item(game_state.item_manager, "wooden_knife", {9, 2, 8})

	return game_state
}

update_game :: proc(game_state: ^Game_State) {
	if game_state.pause do return

	pl.player_update(&game_state.player)
	pl.update(game_state.item_manager)

	for npcInGameState in game_state.npcs {
		npc.update_npc(npcInGameState, game_state.player.position, rl.GetFrameTime())
	}

	if rl.IsKeyPressed(.E) {
		pickup_range := f32(2.0)
		picked_item := pl.pick_up_item(game_state.item_manager, &game_state.player, pickup_range)
		//if picked_item != nil {
		// Add to player inventory or handle pickup
		//	}
	}
}

render_game :: proc(game_state: ^Game_State) {
	camera := pkg.init_camera(&game_state.player)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKBLUE)

	rl.BeginMode3D(camera)
	{
		tgen.init_terrain_instances()


		pl.player_render(&game_state.player)
		draw_game(&game_state.player)
		pl.draw(game_state.item_manager)

		for npcInGameState in game_state.npcs {
			npc.draw_npc(npcInGameState)
		}
	}
	rl.EndMode3D()

	screen_text := pkg.format_screen_text(&game_state.player)
	pl.handle_inventory_input(&game_state.player, game_state.item_manager)
	pl.draw_inventory(game_state.player.inventory)

	rl.DrawText(screen_text["coords"], 10, 10, 10, rl.BLACK)
	rl.DrawText(screen_text["gold"], 10, 30, 30, rl.GOLD)

	perf.update_performance_stats()
	perf.draw_performance_overlay()
}

draw_game :: proc(player: ^pl.Player) {
	textures.draw_custom_material()
	for instance in shared.Terrain_instances {
		for instance in shared.Terrain_instances {
			// Draw the current collision boxes to debug
			for collision_box in instance.collision_boxes {
				pkg.debug(collision_box.position)
				rl.DrawBoundingBox(collision_box.box, rl.RED)
			}
		}
		switch instance.model_type {
		case .RockyCube:
			textures.draw_rocky_cube(instance.position, instance.scale)
		case .IslandPlatform:
			textures.draw_island_platform(instance.position, instance.scale)
		case .RockFormation:
			textures.draw_rock_formation(instance.position, instance.scale)
		case .CliffWall:
			textures.draw_cliff_wall(instance.position, instance.scale)
		case .TerrainPillar:
			textures.draw_terrain_pillar(instance.position, instance.scale)
		case .ConcreteCube:
			textures.draw_concrete_cube(instance.position, instance.scale)
		case .ConcreteIslandPlatform:
			textures.draw_concrete_island_platform(instance.position, instance.scale)
		case .ConcreteFormation:
			textures.draw_concrete_formation(instance.position, instance.scale)
		case .ConcreteWall:
			textures.draw_concrete_wall(instance.position, instance.scale)
		case .ConcretePillar:
			textures.draw_concrete_pillar(instance.position, instance.scale)
		case .StartingIsland:
			terrain_models.draw_starting_island(instance.position, instance.scale)
		case .LibertyIsland:
			terrain_models.draw_liberty_island(instance.position, instance.scale)
		case .OldGarage:
			terrain_models.draw_old_garage(instance.position, instance.scale)
		case .Room99:
			terrain_models.draw_room_99(instance.position, instance.scale)
		case .portal:
			terrain_models.draw_portal(instance.position, instance.scale)
		}

	}
}

cleanup_game :: proc(game_state: ^Game_State) {
	pl.unload_player(&game_state.player)
	pl.unload_resources(game_state.item_manager)

	for npcInGameState in game_state.npcs {
		npc.destroy_npc(npcInGameState)
	}
	delete(game_state.npcs)

	textures.cleanup_custom_material()
	textures.cleanup_terrain_elements()
	menu.cleanup_menu(&game_state.menu)
}
