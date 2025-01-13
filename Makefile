ODIN = odin
APP_NAME = no_name_game


.PHONY: all
all: run


.PHONY: build
build:
	$(ODIN) run  src/main/main.odin -file


.PHONY: run
run: build
	./$(APP_NAME)

.PHONY: clean
clean:
	rm main

.PHONY: test
test:
	$(ODIN) test ./...

