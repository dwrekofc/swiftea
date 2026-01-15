# SwiftEA Makefile
# Usage:
#   make build    - Build release binary
#   make install  - Build and install to /usr/local/bin
#   make dev      - Build debug and install (faster builds)
#   make uninstall - Remove from /usr/local/bin
#   make clean    - Clean build artifacts
#   make test     - Run tests

PREFIX ?= $(HOME)/.local
BINARY_NAME = swea
BUILD_DIR = .build
RELEASE_BIN = $(BUILD_DIR)/release/$(BINARY_NAME)
DEBUG_BIN = $(BUILD_DIR)/debug/$(BINARY_NAME)

.PHONY: build install dev uninstall clean test help

help:
	@echo "SwiftEA Build Commands:"
	@echo "  make build     - Build release binary"
	@echo "  make install   - Build release and install to $(PREFIX)/bin"
	@echo "  make dev       - Build debug and install (faster iteration)"
	@echo "  make uninstall - Remove from $(PREFIX)/bin"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make test      - Run tests"
	@echo ""
	@echo "After 'make install' or 'make dev', run 'swea' from anywhere."

build:
	@echo "Building release..."
	swift build -c release
	@echo "Done: $(RELEASE_BIN)"

debug:
	@echo "Building debug..."
	swift build
	@echo "Done: $(DEBUG_BIN)"

install: build
	@echo "Installing to $(PREFIX)/bin/$(BINARY_NAME)..."
	@mkdir -p $(PREFIX)/bin
	@cp -f $(RELEASE_BIN) $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Installed! Run 'swea --help' to verify."

# Dev install uses symlink for faster iteration (no copy needed after rebuild)
dev: debug
	@echo "Installing dev symlink to $(PREFIX)/bin/$(BINARY_NAME)..."
	@mkdir -p $(PREFIX)/bin
	@ln -sf "$(CURDIR)/$(DEBUG_BIN)" $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Installed! Run 'swea --help' to verify."
	@echo "Note: Run 'make debug' or 'swift build' to update after code changes."

uninstall:
	@echo "Removing $(PREFIX)/bin/$(BINARY_NAME)..."
	@rm -f $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Uninstalled."

clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	@rm -rf $(BUILD_DIR)
	@echo "Clean."

test:
	@echo "Running tests..."
	swift test
