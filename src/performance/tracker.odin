package performance

import "base:runtime"
import "core:fmt"
import "core:time"
import rl "vendor:raylib"

Performance_Stats :: struct {
	cpu_usage: f32,
	ram_usage: u64,
	gpu_usage: f32,
	timestamp: time.Time,
}
Stats_History :: struct {
	stats:         [60]Performance_Stats,
	current_index: int,
}

history: Stats_History
is_tracking: bool
start_time: time.Time

init_performance_tracking :: proc() {
	is_tracking = true
	start_time = time.now()
}

update_performance_stats :: proc() -> Performance_Stats {
	if !is_tracking do return Performance_Stats{}

	current_time := time.now()

	stats := Performance_Stats {
		cpu_usage = get_cpu_usage(),
		ram_usage = get_ram_usage(),
		gpu_usage = get_gpu_usage(),
		timestamp = current_time,
	}

	history.stats[history.current_index] = stats
	history.current_index = (history.current_index + 1) % len(history.stats)

	return stats
}

get_cpu_usage :: proc() -> f32 {
	return 0
}

get_ram_usage :: proc() -> u64 {
	when ODIN_OS == .Windows {
		info := runtime.Memory_Info{}
		return u64(len(runtime.Arena.buf))
	} else {
		return 0
	}
}

get_gpu_usage :: proc() -> f32 {
	return 0
}


draw_performance_overlay :: proc() {
	if !is_tracking do return

	current_stats := history.stats[history.current_index]
	y_pos := 40
	text_color := rl.GREEN

	y_pos += 20

	y_pos += 20

	ram_mb := f32(current_stats.ram_usage) / (1024 * 1024)
	rl.DrawText(fmt.ctprintf("RAM Usage: %.1f MB", ram_mb), 10, i32(y_pos), 20, text_color)
	y_pos += 20

}

log_performance_data :: proc(filename: string) {
}
