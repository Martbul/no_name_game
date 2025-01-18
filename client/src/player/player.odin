package player

import "../constants"
import rl "vendor:raylib"

Player :: struct {
	position:            rl.Vector2,
	previous_position:   rl.Vector2,
	velocity:            rl.Vector2,
	is_on_ground:        bool,
	health:              int,
	inventory:           Inventory,
	texture:             rl.Texture,
	facing_left:         bool,
	texture_loaded:      bool,
	current_frame:       int,
	frames_counter:      int,
	frames_delay:        int,
	frames_delay_couter: int,
	frames_speed:        int,
	animation_state:     AnimationState,
	animation_timer:     f32,
	bounds:              rl.Rectangle,
	frame_rec:           rl.Rectangle,
	mooving:             bool,
}

AnimationState :: enum {
	Idle,
	Walking,
	Jumping,
	Falling,
}


init_player :: proc() -> Player {
	player := Player {
		position            = rl.Vector2{100, 100},
		previous_position   = rl.Vector2{100, 100},
		velocity            = rl.Vector2{0, 0},
		health              = 100,
		texture_loaded      = false,
		frames_speed        = 1,
		animation_state     = .Idle,
		facing_left         = false,
		inventory           = init_inventory(),
		animation_timer     = 0.0,
		frames_counter      = 0,
		frames_delay_couter = 0,
		frames_delay        = 5,
	}

	player.texture = rl.LoadTexture(constants.PLAYER_TEXTURE)
	if player.texture.id != 0 {
		player.texture_loaded = true
	}

	return player
}


player_render :: proc(player: ^Player) {
	if !player.texture_loaded {
		return
	}

	frame_width := f32(player.texture.width) / constants.PLAYER_FRAME_NUM
	frame_height := f32(player.texture.height)
	animation_row := int(player.animation_state)

	// Update frame rectangle to display the correct frame and animation row
	player.frame_rec = rl.Rectangle {
		x      = frame_width * f32(player.frames_counter),
		y      = frame_height * f32(animation_row),
		width  = frame_width,
		height = frame_height,
	}

	// Handle frame updates with delay
	player.frames_delay_couter += 1
	if player.frames_delay_couter > player.frames_delay {
		if player.mooving {

			player.frames_delay_couter = 0

			player.frames_counter = (player.frames_counter + 1) % int(constants.PLAYER_FRAME_NUM)
		}

	}

	// Draw the texture using the calculated frame rectangle
	scale: f32 = 1.0 // Adjust for desired scaling
	dest_rec := rl.Rectangle {
		x      = player.position.x - frame_width * scale / 2,
		y      = player.position.y - frame_height * scale / 2,
		width  = frame_width * scale,
		height = frame_height * scale,
	}
	// Determine rotation and flip based on facing direction
	if player.facing_left {
		player.frame_rec.width = -frame_width
	} else {
		player.frame_rec.width = frame_width
	}
	origin := rl.Vector2{frame_width * scale / 2, frame_height * scale / 2}
	rl.DrawTexturePro(player.texture, player.frame_rec, dest_rec, origin, 0.0, rl.WHITE)
}

player_update :: proc(player: ^Player, platforms: []rl.Rectangle) {
	frame_width := f32(player.texture.width) / constants.PLAYER_FRAME_NUM
	delta_time := rl.GetFrameTime()
	player.previous_position = player.position

	// Apply gravity if not on ground
	if !player.is_on_ground {
		player.velocity.y += constants.GRAVITY * delta_time
	}

	// Handle input
	input, mooving := get_input_vec()
	player.velocity.x = input.x * constants.PLAYER_SPEED

	player.mooving = mooving
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

	// Animation frame logic
	//player.animation_timer += delta_time
	//frame_count: int
	//switch player.animation_state {
	//case .Idle:
	///	frame_count = 4
	//case .Walking:
	//	frame_count = 6
	//case .Jumping:
	//	frame_count = 2
	//case .Falling:
	//	frame_count = 2
	//}
	//if player.animation_timer >= 1.0 / f32(player.frames_speed) {
	//	player.animation_timer -= 1.0 / f32(player.frames_speed)
	//	player.current_frame += 1
	//
	//		if player.current_frame >= frame_count {
	//			player.current_frame = 0
	//		}
	//1:when	}
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


//player_update :: proc(player: ^Player, platforms: []rl.Rectangle) {
//	delta_time := rl.GetFrameTime()
///	player.previous_position = player.position
//
//	// Apply gravity if not on ground
///	if !player.is_on_ground {
//		player.velocity.y += constants.GRAVITY * delta_time
///	}
///
//	// Handle input
//	input := get_input_vec()
//	player.velocity.x = input.x * constants.PLAYER_SPEED
//
///	// Apply air resistance
///	player.velocity.x *= 1.0 - (constants.AIR_RESISTANCE * delta_time)
///
//	// Handle jumping
////	if rl.IsKeyPressed(.SPACE) && player.is_on_ground {
//		player.velocity.y = -constants.JUMP_FORCE
//		player.is_on_ground = false
///		player.animation_state = .Jumping
//	}

//	// Update position
//	player.position.x += player.velocity.x * delta_time
//	player.position.y += player.velocity.y * delta_time

//	// Check collisions
//	check_collision(player, platforms)

// Update facing direction
//	if player.velocity.x != 0 {
///		player.facing_left = player.velocity.x < 0
//	}

// Update animation state
//	if !player.is_on_ground {
//		player.animation_state = player.velocity.y < 0 ? .Jumping : .Falling
//	} else if abs(player.velocity.x) > 0.1 {
///		player.animation_state = .Walking
//	} else {
///		player.animation_state = .Idle
//	}
//
//	// Update animation frame counter
//	player.frames_counter += 1
//	if player.frames_counter >= (60 / player.frames_speed) {
//		player.frames_counter = 0
//		player.current_frame += 1
//	}
///
///}
get_input_vec :: proc() -> (rl.Vector2, bool) {
	input := rl.Vector2{}
	mooving := false
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
		input.x = -1
		mooving = true
	}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
		input.x = 1
		mooving = true
	}

	return input, mooving
}

unload_player :: proc(player: ^Player) {
	if player.texture_loaded {
		rl.UnloadTexture(player.texture)
	}
}
