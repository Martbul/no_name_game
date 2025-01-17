ODIN = odin
APP_NAME = no_name_game
BUILD_DIR = ./build
SRC_FILE = src/main/main.odin

.PHONY: all
all: build run_server

.PHONY: build
build:
	$(ODIN) build $(SRC_FILE) -out:$(BUILD_DIR)/$(APP_NAME)

.PHONY: run_server
run_server:
	$(ODIN) run src/main/main.odin server

.PHONY: run_client
run_client:
	$(ODIN) run src/main/main.odin client

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: test
test:
	$(ODIN) test ./...
