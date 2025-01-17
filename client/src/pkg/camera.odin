package pkg

import pl "../player"
import rl "vendor:raylib"

init_camera :: proc(player: ^pl.Player) -> rl.Camera2D {
	camera := rl.Camera2D {
		target   = rl.Vector2{player.position.x, player.position.y},
		offset   = rl.Vector2{f32(rl.GetScreenWidth()) / 2.0, f32(rl.GetScreenHeight()) / 2.0},
		rotation = 0.0,
		zoom     = 1.0,
	}

	return camera
}

update_camera :: proc(camera: ^rl.Camera2D, player: ^pl.Player, delta_time: f32) {
	lerp_factor := 5.0 * delta_time

	camera.target = rl.Vector2 {
		camera.target.x + (player.position.x - camera.target.x) * lerp_factor,
		camera.target.y + (player.position.y - camera.target.y) * lerp_factor,
	}
}
