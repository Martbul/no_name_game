package pkg
import "base:runtime"
import "core:fmt"
import "core:log"

Logger_Data :: struct {
	console_logger: log.Logger,
}

GLOBAL_LOGGER: Logger_Data

init_logger :: proc() {
	console_opts := log.Options{.Level, .Line, .Procedure, .Terminal_Color}
	GLOBAL_LOGGER.console_logger = log.create_console_logger(opt = console_opts)
	context.logger = GLOBAL_LOGGER.console_logger
}

destroy_logger :: proc() {
	log.destroy_console_logger(GLOBAL_LOGGER.console_logger)
}

debug :: proc(args: ..any) {
	context = runtime.default_context()
	context.logger = GLOBAL_LOGGER.console_logger
	log.debug(args)
}

info :: proc(args: ..any) {
	context = runtime.default_context()
	context.logger = GLOBAL_LOGGER.console_logger
	log.info(args)
}

warn :: proc(args: ..any) {
	context = runtime.default_context()
	context.logger = GLOBAL_LOGGER.console_logger
	log.warn(args)
}

error :: proc(args: ..any) {
	context = runtime.default_context()
	context.logger = GLOBAL_LOGGER.console_logger
	log.error(args)
}

fatal :: proc(args: ..any) {
	context = runtime.default_context()
	context.logger = GLOBAL_LOGGER.console_logger
	log.fatal(args)
}
