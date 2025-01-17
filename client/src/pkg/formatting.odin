package pkg

import pl "../player"
import "core:fmt"

format_screen_text :: proc(player: ^pl.Player) -> map[string]cstring {
	screen_text := make(map[string]cstring)

	coord_text := fmt.aprintf("x: %.2f, y: %.2f", player.position.x, player.position.y)

	coords: cstring = fmt.caprintf(coord_text)

	screen_text["coords"] = coords

	return screen_text
}
