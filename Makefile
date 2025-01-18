ODIN = odin

# App names
CLIENT_NAME = game_client

# Directories
CLIENT_DIR = client
CLIENT_BUILD_DIR = $(CLIENT_DIR)/build
CLIENT_MAIN_FILE = client/src/main/main.odin

# Targets
.PHONY: all client server clean

all: client
# Build client
client: $(CLIENT_BUILD_DIR)
	$(ODIN) build $(CLIENT_MAIN_FILE) -file -out:$(CLIENT_BUILD_DIR)/$(CLIENT_NAME)

# Run server
run: client
	$(CLIENT_BUILD_DIR)/$(CLIENT_NAME)

# Create build directory if it doesn't exist
$(CLIENT_BUILD_DIR):
	mkdir -p $(CLIENT_BUILD_DIR)


# Clean build directories
clean:
	rm -rf $(CLIENT_BUILD_DIR)
