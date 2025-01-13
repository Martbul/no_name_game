package player

import "../constants"
import rl "vendor:raylib"

Player :: struct {
	position:          rl.Vector2,
	previous_position: rl.Vector2,
	velocity:          rl.Vector2,
	is_on_ground:      bool,
	health:            int,
	inventory:         Inventory,
	texture:           rl.Texture,
	facing_left:       bool,
	texture_loaded:    bool,
	current_frame:     int,
	frames_counter:    int,
	frames_speed:      int,
	animation_state:   AnimationState,
	bounds:            rl.Rectangle,
}

AnimationState :: enum {
	Idle,
	Walking,
	Jumping,
	Falling,
}


check_collision :: proc(player: ^Player, platforms: []rl.Rectangle) {
	player.bounds = rl.Rectangle {
		x      = player.position.x - f32(player.texture.width) / 12,
		y      = player.position.y - f32(player.texture.height) / 4,
		width  = f32(player.texture.width) / 6,
		height = f32(player.texture.height) / 2,
	}

	player.is_on_ground = false

	for platform in platforms {
		if rl.CheckCollisionRecs(player.bounds, platform) {
			overlap_x := min(
				player.bounds.x + player.bounds.width - platform.x,
				platform.x + platform.width - player.bounds.x,
			)
			overlap_y := min(
				player.bounds.y + player.bounds.height - platform.y,
				platform.y + platform.height - player.bounds.y,
			)

			// Resolve collision based on smallest overlap
			if overlap_x < overlap_y {
				// Horizontal collision
				if player.bounds.x < platform.x {
					player.position.x -= overlap_x
				} else {
					player.position.x += overlap_x
				}
				player.velocity.x = 0
			} else {
				// Vertical collision
				if player.bounds.y < platform.y {
					player.position.y -= overlap_y
					player.velocity.y = 0
					player.is_on_ground = true
				} else {
					player.position.y += overlap_y
					player.velocity.y = 0
				}
			}
		}
	}
}


init_player :: proc() -> Player {
	player := Player {
		position          = rl.Vector2{100, 100},
		previous_position = rl.Vector2{100, 100},
		velocity          = rl.Vector2{0, 0},
		health            = 100,
		texture_loaded    = false,
		frames_speed      = 1,
		animation_state   = .Idle,
		facing_left       = false,
		inventory         = init_inventory(),
	}

	player.texture = rl.LoadTexture(constants.PLAYER_TEXTURE)
	if player.texture.id != 0 {
		player.texture_loaded = true
	}

	return player
}

player_update :: proc(player: ^Player, platforms: []rl.Rectangle) {
	delta_time := rl.GetFrameTime()
	player.previous_position = player.position

	// Apply gravity if not on ground
	if !player.is_on_ground {
		player.velocity.y += constants.GRAVITY * delta_time
	}

	// Handle input
	input := get_input_vec()
	player.velocity.x = input.x * constants.PLAYER_SPEED

	// Apply air resistance
	player.velocity.x *= 1.0 - (constants.AIR_RESISTANCE * delta_time)

	// Handle jumping
	if rl.IsKeyPressed(.SPACE) && player.is_on_ground {
		player.velocity.y = -constants.JUMP_FORCE
		player.is_on_ground = false
		player.animation_state = .Jumping
	}

	// Update position
	player.position.x += player.velocity.x * delta_time
	player.position.y += player.velocity.y * delta_time

	// Check collisions
	check_collision(player, platforms)

	// Update facing direction
	if player.velocity.x != 0 {
		player.facing_left = player.velocity.x < 0
	}

	// Update animation state
	if !player.is_on_ground {
		player.animation_state = player.velocity.y < 0 ? .Jumping : .Falling
	} else if abs(player.velocity.x) > 0.1 {
		player.animation_state = .Walking
	} else {
		player.animation_state = .Idle
	}

	// Update animation frame counter
	player.frames_counter += 1
	if player.frames_counter >= (60 / player.frames_speed) {
		player.frames_counter = 0
		player.current_frame += 1
	}
}

player_render :: proc(player: ^Player) {
	if !player.texture_loaded {
		return
	}

	frame_width := f32(player.texture.width) / 6
	frame_height := f32(player.texture.height) / 4
	animation_row := int(player.animation_state)

	if player.current_frame >= 6 {
		player.current_frame = 0
	}

	source_rec := rl.Rectangle {
		x      = frame_width * f32(player.current_frame),
		y      = frame_height * f32(animation_row),
		width  = frame_width,
		height = frame_height,
	}

	dest_rec := rl.Rectangle {
		x      = player.position.x - frame_width,
		y      = player.position.y - frame_height,
		width  = frame_width * 2,
		height = frame_height * 2,
	}

	rl.DrawTexturePro(player.texture, source_rec, dest_rec, rl.Vector2{0, 0}, 0.0, rl.WHITE)

}


get_input_vec :: proc() -> rl.Vector2 {
	input := rl.Vector2{}

	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
		input.x = -1
	}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
		input.x = 1
	}

	return input
}

unload_player :: proc(player: ^Player) {
	if player.texture_loaded {
		rl.UnloadTexture(player.texture)
	}
}
