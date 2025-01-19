package main

import "../constants"
import "../menu"
import perf "../performance"
import "../pkg"
import pl "../player"
import server "../server_shared"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import rl "vendor:raylib"


game_state :: struct {
	players:      map[int]pl.Player,
	item_manager: ^pl.ItemManager,
	pause:        bool,
	menu:         menu.Menu,
	platforms:    []rl.Rectangle,
	network:      server.Multiplayer_State,
	should_quit:  bool,
}


main :: proc() {
	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "no_name_game")
	defer rl.CloseWindow()

	game := init_game()

	fmt.println("Connecting to server...")
	network_state, ok := init_client("127.0.0.1")
	if !ok {
		fmt.println("Failed to connect to server")
		return
	}

	game.network = network_state

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
			//WARN: IPDATE_CLIENT_NETWORK FUCKS THE GAME
			update_client_network(&game)
			update_game(&game)
			render_game(&game)
		}
	}

	// Cleanup
	net.close(game.network.socket)
}


//init_network :: proc(
//	is_server: bool,
//	server_ip: string = "127.0.0.1",
//) -> (
//	server.Multiplayer_State,
//	bool,
//) {
//	state := server.Multiplayer_State {
//		is_server      = is_server,
//		clients        = make(map[int]net.TCP_Socket),
//		next_player_id = 1,
//	}
//
//	if is_server {
//		socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = server.PORT})
//		if err != nil {
//			return state, false
//		}
//		state.socket = socket
//	} else {
//		local_addr, ok := net.parse_ip4_address(server_ip)
//		if !ok {
//			fmt.println("Failed to parse IP address")
//			return state, false
//		}
///		socket, err := net.dial_tcp(net.Endpoint{address = local_addr, port = server.PORT})
//		if err != nil {
//			return state, false
///		}
//		state.socket = socket
//	}
//
//	return state, true
//}//


init_client :: proc(server_ip: string = "127.0.0.1") -> (server.Multiplayer_State, bool) {
	state := server.Multiplayer_State {
		is_server      = false,
		clients        = make(map[int]net.TCP_Socket),
		next_player_id = 1,
	}

	local_addr, ok := net.parse_ip4_address(server_ip)
	if !ok {
		fmt.println("Failed to parse IP address")
		return state, false
	}
	// Establishes TCP connection to server
	socket, err := net.dial_tcp(net.Endpoint{address = local_addr, port = server.PORT})
	if err != nil {
		fmt.println("Failed to establish connection to the server")
		return state, false
	}
	fmt.println("Successfully connected to server")
	//INFO: The socet is i32 and it is 11, meaning it is a file descriptor(The OS returns a unique integer identifier (file descriptor) that represents this connection.)
	state.socket = socket
	return state, true
}

update_client_network :: proc(game: ^game_state) {
	fmt.print("----------DEBUGING-----------")
	socket := game.network.socket.(net.TCP_Socket)
	fmt.print(socket)

	// Send local player position update
	if local_player, ok := &game.players[game.network.local_player_id]; ok {
		msg := server.Network_Message {
			msg_type  = .PLAYER_UPDATE,
			position  = local_player.position,
			player_id = game.network.local_player_id,
		}
		// Don't block on send, just try once
		send_message(socket, msg)
	}

	// Try to receive any pending messages
	if !check_socket_data(socket) do return

	msg, ok := receive_message(socket)
	if !ok do return

	#partial switch msg.msg_type {
	case .PLAYER_CONNECT:
		if msg.player_id != game.network.local_player_id {
			fmt.println("New player connected:", msg.player_id)
			game.players[msg.player_id] = pl.init_player()
		}

	case .PLAYER_DISCONNECT:
		if msg.player_id != game.network.local_player_id {
			fmt.println("Player disconnected:", msg.player_id)
			delete_key(&game.players, msg.player_id)
		}

	case .PLAYER_UPDATE:
		if msg.player_id != game.network.local_player_id {
			if player, exists := game.players[msg.player_id]; exists {
				// Create new player with updated position
				updated_player := player
				updated_player.position = msg.position
				game.players[msg.player_id] = updated_player
			}
		}
	}
}

// Client send_message
send_message :: proc(socket: net.TCP_Socket, msg: server.Network_Message) -> bool {
	fmt.println("Attempting to send message:")
	fmt.printf("Message type: %v\n", msg.msg_type)
	fmt.printf("Player ID: %v\n", msg.player_id)
	fmt.printf("Position: %v\n", msg.position)

	data, marshal_err := json.marshal(msg)
	if marshal_err != nil {
		fmt.println("Marshal error:", marshal_err)
		return false
	}

	length := len(data)
	fmt.printf("Message length: %v bytes\n", length)

	length_bytes := transmute([8]byte)length
	bytes_written, send_err := net.send_tcp(socket, length_bytes[:])
	if send_err != nil || bytes_written < 0 {
		fmt.println("Error sending length:", send_err)
		return false
	}
	fmt.printf("Length bytes written: %v\n", bytes_written)

	bytes_written, send_err = net.send_tcp(socket, data)
	if send_err != nil || bytes_written < 0 {
		fmt.println("Error sending data:", send_err)
		return false
	}
	fmt.printf("Data bytes written: %v\n", bytes_written)

	return true
}

receive_message :: proc(socket: net.TCP_Socket) -> (server.Network_Message, bool) {
	msg: server.Network_Message
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


check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
	peek_buf: [1]byte
	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
	return bytes_read > 0 && err == nil
}
//check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
//	// Create a small buffer to peek for data
//	peek_buf: [1]byte
//	//bytes_read, endpoint, err := net.recv_tcp(socket, peek_buf[:], {.Peek, .Non_Blocking})
//	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
//	return bytes_read > 0 && err == nil
//}


run_client :: proc(server_ip: string) {
	network_state, ok := init_client(server_ip)
	if !ok {
		fmt.println("Failed to connect to server")
		return
	}

	rl.InitWindow(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT, "no_name_game")
	defer rl.CloseWindow()

	game := init_game()
	game.network = network_state

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
			update_client_network(&game)
			update_game(&game)
			render_game(&game)
		}
	}

	// Cleanup
	net.close(game.network.socket)
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
		network      = server.Multiplayer_State{}, // Placeholder, initialized later
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
