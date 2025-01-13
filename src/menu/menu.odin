package menu

import "../constants"
import "../pkg"
import "core:fmt"
import "core:log"
import rl "vendor:raylib"

Menu_State :: enum {
	Main,
	Options,
	Credits,
}

Menu :: struct {
	state:           Menu_State,
	selected_option: int,
	background:      rl.Texture2D,
	title_font:      rl.Font,
	button_rect:     rl.Rectangle,
	is_active:       bool,
}

create_menu :: proc() -> Menu {
	menu := Menu {
		state = .Main,
		selected_option = 0,
		background = rl.LoadTexture("assets/menu/background.jpg"),
		title_font = rl.LoadFont("assets/fonts/betteroutline/Better Outline.ttf"),
		button_rect = rl.Rectangle {
			x = f32(constants.SCREEN_WIDTH / 2 - 100),
			y = f32(constants.SCREEN_HEIGHT / 2 - 100),
			width = 200,
			height = 50,
		},
		is_active = true,
	}

	return menu
}

update_menu :: proc(menu: ^Menu) -> bool {
	mouse_pos := rl.GetMousePosition()

	menu.selected_option = -1
	for i := 0; i < get_option_count(menu.state); i += 1 {
		button_bounds := get_button_bounds(menu.button_rect, i)
		if rl.CheckCollisionPointRec(mouse_pos, button_bounds) {
			menu.selected_option = i
			if rl.IsMouseButtonPressed(.LEFT) {
				handle_menu_click(menu, i)
				if menu.state == .Main && i == 0 {
					return false // Start game
				}
			}
		}
	}


	return true // Continue showing menu
}

draw_menu :: proc(menu: ^Menu) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.DrawTexture(menu.background, 0, 0, rl.WHITE)

	title_text: cstring = fmt.caprint("SkyWays")
	title_pos := rl.Vector2 {
		f32(
			constants.SCREEN_WIDTH / 2 -
			rl.MeasureTextEx(menu.title_font, title_text, 60, 2).x / 2,
		),
		100,
	}
	rl.DrawTextEx(menu.title_font, title_text, title_pos, 60, 2, rl.WHITE)

	options := get_menu_options(menu.state)

	for i := 0; i < len(options); i += 1 {
		button_bounds := get_button_bounds(menu.button_rect, i)
		button_color := menu.selected_option == i ? rl.SKYBLUE : rl.DARKBLUE

		rl.DrawRectangleRec(button_bounds, button_color)
		rl.DrawRectangleLinesEx(button_bounds, 2, rl.WHITE)

		text_size := rl.MeasureText(fmt.caprint(options[i]), 20)
		text_pos_x := i32(button_bounds.x + button_bounds.width / 2) - text_size / 2
		text_pos_y := i32(button_bounds.y + button_bounds.height / 2 - 10)
		rl.DrawText(fmt.caprint(options[i]), text_pos_x, text_pos_y, 20, rl.WHITE)
	}


}

get_menu_options :: proc(state: Menu_State, allocator := context.allocator) -> []string {
	#partial switch state {
	case .Main:
		options := make([]string, 4, allocator)
		options[0] = "Start Game"
		options[1] = "Options"
		options[2] = "Credits"
		options[3] = "Exit"
		return options
	case .Options:
		options := make([]string, 4, allocator)
		options[0] = "Graphics"
		options[1] = "Sound"
		options[2] = "Controls"
		options[3] = "Back"
		return options
	case .Credits:
		options := make([]string, 1, allocator)
		options[0] = "Back"
		return options
	}
	return make([]string, 0, allocator)
}

get_option_count :: proc(state: Menu_State) -> int {
	return len(get_menu_options(state))
}

get_button_bounds :: proc(base_rect: rl.Rectangle, index: int) -> rl.Rectangle {
	return rl.Rectangle {
		x = base_rect.x,
		y = base_rect.y + f32(index * 60),
		width = base_rect.width,
		height = base_rect.height,
	}
}

handle_menu_click :: proc(menu: ^Menu, option: int) {
	#partial switch menu.state {
	case .Main:
		switch option {
		case 1:
			menu.state = .Options
		case 2:
			menu.state = .Credits
		case 3:
			rl.CloseWindow()
		}
	case .Options, .Credits:
		if option == get_option_count(menu.state) - 1 {
			menu.state = .Main
		}
	}
}

cleanup_menu :: proc(menu: ^Menu) {
	rl.UnloadTexture(menu.background)
	rl.UnloadFont(menu.title_font)
}
