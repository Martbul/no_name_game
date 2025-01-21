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
import "core:time"
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
			update_client_network(&game)
			update_game(&game)
			render_game(&game)
		}
	}

	// Cleanup
	net.close(game.network.socket)
}


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
	//fmt.println("Successfully connected to server")
	//INFO: The socet is i32 and it is 11, meaning it is a file descriptor(The OS returns a unique integer identifier (file descriptor) that represents this connection.)
	state.socket = socket
	return state, true
}


verify_connection :: proc(socket: net.TCP_Socket) -> bool {
	// Send a simple ping message
	ping_msg := server.Network_Message {
		msg_type  = .PLAYER_CONNECT,
		player_id = -1, // Special ping ID
	}
	return send_message(socket, ping_msg)
}

//update_client_network :: proc(game: ^game_state) {
//	socket := game.network.socket.(net.TCP_Socket)
//
//	// First, try to send update without blocking
//	if local_player, ok := &game.players[game.network.local_player_id]; ok {
//		msg := server.Network_Message {
//			msg_type  = .PLAYER_UPDATE,
//			position  = local_player.position,
//			player_id = game.network.local_player_id,
//		}
//		send_message(socket, msg)
//	}
//
//	// Quick check for data without blocking
//	peek_buf: [1]byte
//	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
//	if err != nil || bytes_read <= 0 {
//		return // No data available, continue with game loop
//	}
//
//	// Data is available, now receive the full message
//	msg, ok := receive_message(socket)
//	if !ok do return
//
//	// Process the message as before
//	#partial switch msg.msg_type {
//	case .PLAYER_CONNECT:
//		if msg.player_id != game.network.local_player_id {
//			fmt.println("New player connected:", msg.player_id)
//			game.players[msg.player_id] = pl.init_player()
//		}
//
//	case .PLAYER_DISCONNECT:
//		if msg.player_id != game.network.local_player_id {
//			fmt.println("Player disconnected:", msg.player_id)
//			delete_key(&game.players, msg.player_id)
//		}

//	case .PLAYER_UPDATE:
//		if msg.player_id != game.network.local_player_id {
//			if player, exists := game.players[msg.player_id]; exists {
//				updated_player := player
//				updated_player.position = msg.position
//				game.players[msg.player_id] = updated_player
//			}
//		}
//	}
//}

encode_length :: proc(length: u64) -> [8]byte {
	return [8]byte {
		byte(length >> 56),
		byte(length >> 48),
		byte(length >> 40),
		byte(length >> 32),
		byte(length >> 24),
		byte(length >> 16),
		byte(length >> 8),
		byte(length),
	}
}

decode_length :: proc(bytes: [8]byte) -> u64 {
	return(
		u64(bytes[0]) << 56 |
		u64(bytes[1]) << 48 |
		u64(bytes[2]) << 40 |
		u64(bytes[3]) << 32 |
		u64(bytes[4]) << 24 |
		u64(bytes[5]) << 16 |
		u64(bytes[6]) << 8 |
		u64(bytes[7]) \
	)
}
update_client_network :: proc(game: ^game_state) {
	socket := game.network.socket.(net.TCP_Socket)

	// Only send updates every 10 frames (6 times per second)
	if int(rl.GetFrameTime()) % 10 == 0 {
		if local_player, ok := &game.players[game.network.local_player_id]; ok {
			msg := server.Network_Message {
				msg_type  = .PLAYER_UPDATE,
				position  = local_player.position,
				player_id = game.network.local_player_id,
			}
			fmt.printf("Sending position update: [%f, %f]\n", msg.position.x, msg.position.y)
			if !send_message(socket, msg) {
				fmt.println("Failed to send player update")
				return
			}
		}
	}

	// Try to receive messages (non-blocking)
	msg, ok := receive_message(socket)
	if ok {
		fmt.printf("Received message type: %v from player: %v\n", msg.msg_type, msg.player_id)
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
					updated_player := player
					updated_player.position = msg.position
					game.players[msg.player_id] = updated_player
					fmt.printf(
						"Updated player %v position to [%f, %f]\n",
						msg.player_id,
						msg.position.x,
						msg.position.y,
					)
				}
			}
		}
	}
}

//update_client_network :: proc(game: ^game_state) {
///	socket := game.network.socket.(net.TCP_Socket)
//
//	// First, try to send update without blocking
//	if local_player, ok := &game.players[game.network.local_player_id]; ok {
//		msg := server.Network_Message {
//			msg_type  = .PLAYER_UPDATE,
//			position  = local_player.position,
//			player_id = game.network.local_player_id,
//		}
//		if !send_message(socket, msg) {
//			fmt.println("Failed to send player update")
//			return
//		}
//	}
//
///	// Add a small delay to prevent flooding the network
//	time.sleep(time.Millisecond * 16) // ~60 FPS

// Try to receive messages
//	msg, ok := receive_message(socket)
//	if !ok {
//		return
//	}

//	#partial switch msg.msg_type {
//	case .PLAYER_CONNECT:
//		if msg.player_id != game.network.local_player_id {
//			fmt.println("New player connected:", msg.player_id)
//			game.players[msg.player_id] = pl.init_player()
///		}
//
//	case .PLAYER_DISCONNECT:
//		if msg.player_id != game.network.local_player_id {
//			fmt.println("Player disconnected:", msg.player_id)
//			delete_key(&game.players, msg.player_id)
//		}
//
//	case .PLAYER_UPDATE:
//		if msg.player_id != game.network.local_player_id {
//			if player, exists := game.players[msg.player_id]; exists {
//				updated_player := player
///				updated_player.position = msg.position
//				game.players[msg.player_id] = updated_player
//			}
//		}
//	}
//}

//receive_message :: proc(socket: net.TCP_Socket) -> (server.Network_Message, bool) {
//	msg: server.Network_Message
//	length_bytes: [8]byte
//
//	// Read 8-byte length prefix
//	total_read := 0
//	for total_read < 8 {
//		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
//		if recv_err != nil {
//			fmt.println("Error reading length:", recv_err)
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			return msg, false
//		}
//		total_read += bytes_read
///	}
//
//	// Convert length prefix to u64 (big-endian)
//	length :=
//		u64(length_bytes[0]) << 56 |
//		u64(length_bytes[1]) << 48 |
//		u64(length_bytes[2]) << 40 |
///		u64(length_bytes[3]) << 32 |
//		u64(length_bytes[4]) << 24 |
//		u64(length_bytes[5]) << 16 |
//		u64(length_bytes[6]) << 8 |
//		u64(length_bytes[7])

//	if length == 0 || length > 1024 * 1024 { 	// Reasonable size limit
//		fmt.println("Invalid message length:", length)
//		return msg, false
//	}

//	data := make([]byte, length)
//	defer delete(data)

// Read full message data
//	total_read = 0
//	for total_read < int(length) {
//		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
//		if recv_err != nil {
//			fmt.println("Error reading data:", recv_err)
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			return msg, false
//		}
//		total_read += bytes_read
//	}

// Deserialize JSON message
//	unmarshal_err := json.unmarshal(data, &msg)
//	if unmarshal_err != nil {
//		fmt.println("Unmarshal error:", unmarshal_err)
//		return msg, false
//	}
//
//	return msg, true
//}

send_message :: proc(socket: net.TCP_Socket, msg: server.Network_Message) -> bool {
	data, marshal_err := json.marshal(msg)
	if marshal_err != nil {
		fmt.println("Marshal error:", marshal_err)
		return false
	}

	length := u64(len(data))
	if length == 0 || length > 1024 * 1024 {
		fmt.println("Invalid message length:", length)
		return false
	}

	fmt.printf("Sending message: %s\n", string(data))
	length_bytes := encode_length(length)
	fmt.printf("Length encoded: %v (decimal: %v)\n", length_bytes, length)

	// Send length prefix and data
	send_all := proc(data: []byte, socket: net.TCP_Socket) -> bool {
		total_sent := 0
		for total_sent < len(data) {
			bytes_sent, send_err := net.send_tcp(socket, data[total_sent:])
			if send_err != nil {
				fmt.printf("Send error: %v\n", send_err)
				return false
			}
			if bytes_sent <= 0 {
				fmt.println("Socket closed during send")
				return false
			}
			total_sent += bytes_sent
		}
		return true
	}

	if !send_all(length_bytes[:], socket) {
		fmt.println("Failed to send length prefix")
		return false
	}
	if !send_all(data, socket) {
		fmt.println("Failed to send message data")
		return false
	}
	return true
}

receive_message :: proc(socket: net.TCP_Socket) -> (server.Network_Message, bool) {
	msg: server.Network_Message
	length_bytes: [8]byte

	// Read length prefix
	total_read := 0
	for total_read < 8 {
		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
		if recv_err != nil {
			fmt.printf("Error reading length prefix: %v\n", recv_err)
			return msg, false
		}
		if bytes_read <= 0 {
			return msg, false
		}
		total_read += bytes_read
	}

	length := decode_length(length_bytes)
	fmt.printf("Length decoded: %v from bytes: %v\n", length, length_bytes)

	if length == 0 || length > 1024 * 1024 {
		fmt.printf("Invalid message length: %v\n", length)
		return msg, false
	}

	data := make([]byte, length)
	defer delete(data)

	// Read message data
	total_read = 0
	for total_read < int(length) {
		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
		if recv_err != nil {
			fmt.printf("Error reading message data: %v\n", recv_err)
			return msg, false
		}
		if bytes_read <= 0 {
			return msg, false
		}
		total_read += bytes_read
	}

	fmt.printf("Received complete message: %s\n", string(data))

	unmarshal_err := json.unmarshal(data, &msg)
	if unmarshal_err != nil {
		fmt.printf("Unmarshal error: %v\n", unmarshal_err)
		return msg, false
	}

	return msg, true
}
//receive_message :: proc(socket: net.TCP_Socket) -> (server.Network_Message, bool) {
//	msg: server.Network_Message
//	length_bytes: [8]byte

// Read length prefix with timeout
//	total_read := 0
//	for total_read < 8 {
//		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
//		if recv_err != nil {
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			return msg, false
//		}
//		total_read += bytes_read
//	}
//
//	length :=
//		u64(length_bytes[0]) << 56 |
//		u64(length_bytes[1]) << 48 |
//		u64(length_bytes[2]) << 40 |
///		u64(length_bytes[3]) << 32 |
//		u64(length_bytes[4]) << 24 |
///		u64(length_bytes[5]) << 16 |
//		u64(length_bytes[6]) << 8 |
//		u64(length_bytes[7])
//
//	if length == 0 || length > 1024 * 1024 {
//		fmt.println("Invalid message length:", length)
//		return msg, false
//	}

//	data := make([]byte, length)
//	defer delete(data)

//	total_read = 0
//	for total_read < int(length) {
//		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
//		if recv_err != nil {
//			return msg, false
//		}
///		if bytes_read <= 0 {
//			return msg, false
//		}
//		total_read += bytes_read
//	}

//	unmarshal_err := json.unmarshal(data, &msg)
//	if unmarshal_err != nil {
//		fmt.println("Unmarshal error:", unmarshal_err)
//		return msg, false
//	}
//
//	return msg, true
//}

check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
	peek_buf: [1]byte
	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
	if err != nil {
		fmt.printf("Socket check error: %v\n", err)
		return false
	}
	return bytes_read > 0
}

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
