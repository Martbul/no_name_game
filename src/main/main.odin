package main

import "../constants"
import "../menu"
import perf "../performance"
import "../pkg"
import pl "../player"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import rl "vendor:raylib"

Network_Message :: struct {
	msg_type:  enum {
		PLAYER_UPDATE,
		GAME_STATE,
		PLAYER_CONNECT,
		PLAYER_DISCONNECT,
	},
	position:  rl.Vector2,
	player_id: int,
}

Multiplayer_State :: struct {
	is_server:       bool,
	socket:          net.Any_Socket,
	clients:         map[int]net.TCP_Socket,
	next_player_id:  int,
	local_player_id: int,
}

game_state :: struct {
	players:      map[int]pl.Player,
	item_manager: ^pl.ItemManager,
	pause:        bool,
	menu:         menu.Menu,
	platforms:    []rl.Rectangle,
	network:      Multiplayer_State,
	should_quit:  bool, // Add this field
}

PORT :: 27015


init_network :: proc(
	is_server: bool,
	server_ip: string = "127.0.0.1",
) -> (
	Multiplayer_State,
	bool,
) {
	state := Multiplayer_State {
		is_server      = is_server,
		clients        = make(map[int]net.TCP_Socket),
		next_player_id = 1,
	}

	if is_server {
		socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = PORT})
		if err != nil {
			return state, false
		}
		state.socket = socket
	} else {
		local_addr, ok := net.parse_ip4_address(server_ip)
		if !ok {
			fmt.println("Failed to parse IP address")
			return state, false
		}

		socket, err := net.dial_tcp(net.Endpoint{address = local_addr, port = PORT})
		if err != nil {
			return state, false
		}
		state.socket = socket
	}

	return state, true
}


send_message :: proc(socket: net.TCP_Socket, msg: Network_Message) -> bool {
	data, marshal_err := json.marshal(msg)
	if marshal_err != nil {
		return false
	}

	length := len(data)
	length_bytes := transmute([8]byte)length

	bytes_written, send_err := net.send_tcp(socket, length_bytes[:])
	if send_err != nil || bytes_written < 0 {
		return false
	}

	bytes_written, send_err = net.send_tcp(socket, data)
	if send_err != nil || bytes_written < 0 {
		return false
	}

	return true
}


receive_message :: proc(socket: net.TCP_Socket) -> (Network_Message, bool) {
	msg: Network_Message
	length_bytes: [8]byte

	bytes_read, recv_err := net.recv_tcp(socket, length_bytes[:])
	if recv_err != nil || bytes_read < 0 {
		return msg, false
	}

	length := transmute(int)length_bytes
	data := make([]byte, length)
	defer delete(data)

	bytes_read, recv_err = net.recv_tcp(socket, data)
	if recv_err != nil || bytes_read < 0 {
		return msg, false
	}

	unmarshal_err := json.unmarshal(data, &msg)
	if unmarshal_err != nil {
		return msg, false
	}

	return msg, true
}


update_network :: proc(game: ^game_state) {
	if game.network.is_server {
		// Accept new connections
		if check_socket_data(game.network.socket.(net.TCP_Socket)) {
			client, source, accept_err := net.accept_tcp(game.network.socket.(net.TCP_Socket))
			if accept_err != nil do return

			player_id := game.network.next_player_id
			game.network.next_player_id += 1
			game.network.clients[player_id] = client
			game.players[player_id] = pl.init_player() // Initialize a new player

			// Notify other clients
			msg := Network_Message {
				msg_type  = .PLAYER_CONNECT,
				player_id = player_id,
			}

			for _, client_socket in game.network.clients {
				send_message(client_socket, msg)
			}
		}

		// Handle client updates
		for player_id, client_socket in game.network.clients {
			if check_socket_data(client_socket) {
				msg, ok := receive_message(client_socket)
				if !ok {
					delete_key(&game.network.clients, player_id)
					delete_key(&game.players, player_id)
					continue
				}

				//synchronizeing player positions on update
				if msg.msg_type == .PLAYER_UPDATE {
					if player, ok := &game.players[player_id]; ok {
						player.position = msg.position
					}
				}
			}
		}
	} else {
		// Client updates
		if local_player, ok := &game.players[game.network.local_player_id]; ok {
			msg := Network_Message {
				msg_type  = .PLAYER_UPDATE,
				position  = local_player.position,
				player_id = game.network.local_player_id,
			}
			send_message(game.network.socket.(net.TCP_Socket), msg)
		}

		// Receive server updates
		if check_socket_data(game.network.socket.(net.TCP_Socket)) {
			msg, ok := receive_message(game.network.socket.(net.TCP_Socket))
			if !ok do return

			switch msg.msg_type {
			case .PLAYER_UPDATE:
				if msg.player_id != game.network.local_player_id {
					if player, ok := &game.players[msg.player_id]; ok {
						player.position = msg.position
					}
				}
			case .PLAYER_CONNECT:
				if msg.player_id != game.network.local_player_id {
					game.players[msg.player_id] = pl.init_player()
				}
			case .PLAYER_DISCONNECT:
				delete_key(&game.players, msg.player_id)
			case .GAME_STATE:
			// Handle full game state updates if needed    // Update local game state based on the received data
			}
		}
	}
}


check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
	// Create a small buffer to peek for data
	peek_buf: [1]byte
	//bytes_read, endpoint, err := net.recv_tcp(socket, peek_buf[:], {.Peek, .Non_Blocking})
	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
	return bytes_read > 0 && err == nil
}


//main :: proc() {
//
//	args := runtime.args__
//
//	fmt.println("Arguments:", runtime.args__)
//	if len(args) < 2 {
//		fmt.println("Usage:")
//		fmt.println("  Server: program server")
//		fmt.println("  Client: program client [server_ip]")
//		return
//	}
//
//	is_server := args[1] == "server"
//	server_ip := len(args) >= 3 ? args[2] : "127.0.0.1"
//
//	network_state, ok := init_network(is_server, string(server_ip))
//	if !ok {
//		fmt.println("Failed to initialize network")
//		return
//	}
///
//	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "SkyWays")
//	defer rl.CloseWindow()
//
//	game := init_game()
//	game.network = network_state
//
//	if !is_server {
//		// Initialize local player
//		local_player_id := 1 // First client gets ID 1
//		game.network.local_player_id = local_player_id
//		game.players[local_player_id] = pl.init_player()
//	}

//	defer cleanup_game(&game)
//
//	rl.SetTargetFPS(60)
//	pkg.init_logger()
//	defer pkg.destroy_logger()
//
//	for !rl.WindowShouldClose() {
//		if game.menu.is_active {
//			if !menu.update_menu(&game.menu) {
//				game.menu.is_active = false
//				continue
//			}
//			menu.draw_menu(&game.menu)
//		} else {
//			update_network(&game)
///			update_game(&game)
//			render_game(&game)
//		}
//	}
//}

main :: proc() {
	args := runtime.args__

	fmt.println("Arguments:", runtime.args__)
	if len(args) < 2 {
		fmt.println("Usage:")
		fmt.println("  Server: program server")
		fmt.println("  Client: program client [server_ip]")
		return
	}

	is_server := args[1] == "server"
	server_ip := len(args) >= 3 ? args[2] : "127.0.0.1"

	network_state, ok := init_network(is_server, string(server_ip))
	if !ok {
		fmt.println("Failed to initialize network")
		return
	}

	if is_server {
		run_server(&network_state)
	} else {
		run_client(&network_state, string(server_ip))
	}
}

run_server :: proc(network_state: ^Multiplayer_State) {
	game := init_server_game()
	game.network = network_state^

	for !game.should_quit {
		update_network(&game)
		update_game(&game)

		// Optional: Add condition to quit
		if len(game.network.clients) == 0 {
			// Maybe quit if all clients disconnect
			// game.should_quit = true
		}
	}

	cleanup_game(&game)
}

run_client :: proc(network_state: ^Multiplayer_State, server_ip: string) {
	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "SkyWays")
	defer rl.CloseWindow()

	game := init_client_game()
	game.network = network_state^

	// Initialize local player
	local_player_id := 1
	game.network.local_player_id = local_player_id
	game.players[local_player_id] = pl.init_player()

	defer cleanup_game(&game)

	rl.SetTargetFPS(60)
	pkg.init_logger()
	defer pkg.destroy_logger()

	for !rl.WindowShouldClose() {
		if game.menu.is_active {
			if !menu.update_menu(&game.menu) {
				game.menu.is_active = false
				continue
			}
			menu.draw_menu(&game.menu)
		} else {
			update_network(&game)
			update_game(&game)
			render_game(&game)
		}
	}
}

init_server_game :: proc() -> game_state {
	item_manager := pl.init_item_manager()
	platforms := make([]rl.Rectangle, 4)
	// Initialize platforms...

	return game_state {
		players      = make(map[int]pl.Player),
		item_manager = item_manager,
		pause        = false,
		platforms    = platforms,
		network      = Multiplayer_State{},
		should_quit  = false, // Initialize the new field
	}
}


init_client_game :: proc() -> game_state {
	// Full initialization including graphics
	return init_game()
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

	return game_state {
		players      = make(map[int]pl.Player), // Start with no players
		item_manager = item_manager,
		pause        = false,
		menu         = menu.create_menu(),
		platforms    = platforms,
		network      = Multiplayer_State{}, // Placeholder, initialized later
	}
}


update_game :: proc(game_state: ^game_state) {
	if game_state == nil || game_state.item_manager == nil {
		return
	}

	if game_state.pause do return

	// Iterate over all players by reference
	for player_id, &player in game_state.players {
		pl.player_update(&player, game_state.platforms)

		// Handle input only for the local player
		if player_id == game_state.network.local_player_id {
			if rl.IsKeyPressed(.E) {
				pickup_range := f32(50.0)
				picked_item := pl.pick_up_item(game_state.item_manager, &player, pickup_range)
			}
		}
	}

	// Update item manager
	if game_state.item_manager != nil {
		pl.update(game_state.item_manager)
	}
}


render_game :: proc(game: ^game_state) {
	if game == nil {
		return
	}

	// Get local player for camera
	local_player := &game.players[game.network.local_player_id]
	camera := pkg.init_camera(local_player)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKBLUE)
	rl.BeginMode2D(camera)
	{
		// Draw platforms
		for platform in game.platforms {
			rl.DrawRectangleRec(platform, rl.WHITE)
		}

		// Draw all players
		for _, &player in &game.players {
			pl.player_render(&player)
		}

		// Draw items
		if game.item_manager != nil {
			pl.draw(game.item_manager)
		}
	}
	rl.EndMode2D()

	// Draw UI elements
	screen_text := pkg.format_screen_text(local_player)
	if game.item_manager != nil {
		pl.handle_inventory_input(local_player, game.item_manager)
		pl.draw_inventory(local_player.inventory)
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

	for playerId, &player in game_state.players {

		pl.unload_player(&player)
	}

	if game_state.item_manager != nil {
		pl.unload_resources(game_state.item_manager)
	}

	menu.cleanup_menu(&game_state.menu)
}
