package server_shared

import "core:net"
import rl "vendor:raylib"
// Common types that both server and client need
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

//Server_Game_State :: struct {
//	players:     map[int]Player_State,
//	network:     Multiplayer_State,
//	should_quit: bool,
//}

//Player_State :: struct {
//	position: rl.Vector2,
//	// Add other necessary player state info here
//}

PORT :: 27015
