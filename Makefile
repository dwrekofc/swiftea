# SwiftEA Makefile
# Usage:
#   make build    - Build release binary
#   make install  - Build and install to ~/.local/bin (code-signed)
#   make dev      - Build debug and install (code-signed, faster builds)
#   make uninstall - Remove from ~/.local/bin
#   make clean    - Clean build artifacts
#   make test     - Run tests

PREFIX ?= $(HOME)/.local
BINARY_NAME = swea
BUILD_DIR = .build
RELEASE_BIN = $(BUILD_DIR)/release/$(BINARY_NAME)
DEBUG_BIN = $(BUILD_DIR)/debug/$(BINARY_NAME)
IDENTIFIER = com.swiftea.cli

.PHONY: build install dev uninstall clean test help

help:
	@echo "SwiftEA Build Commands:"
	@echo "  make build     - Build release binary"
	@echo "  make install   - Build release and install to $(PREFIX)/bin (code-signed)"
	@echo "  make dev       - Build debug and install (code-signed, faster iteration)"
	@echo "  make uninstall - Remove from $(PREFIX)/bin"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make test      - Run tests"
	@echo ""
	@echo "After 'make install' or 'make dev', run 'swea' from anywhere."
	@echo "Binary is ad-hoc signed as $(IDENTIFIER) for persistent macOS permissions."

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
	@codesign -f -s - --identifier $(IDENTIFIER) $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Installed swea to $(PREFIX)/bin/$(BINARY_NAME) (signed as $(IDENTIFIER))"

# Dev install copies binary (not symlink) to preserve code signature
dev: debug
	@echo "Installing dev build to $(PREFIX)/bin/$(BINARY_NAME)..."
	@mkdir -p $(PREFIX)/bin
	@rm -f $(PREFIX)/bin/$(BINARY_NAME)
	@cp $(DEBUG_BIN) $(PREFIX)/bin/$(BINARY_NAME)
	@codesign -f -s - --identifier $(IDENTIFIER) $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Dev install: $(PREFIX)/bin/$(BINARY_NAME) (signed as $(IDENTIFIER))"
	@echo "Note: Run 'make dev' again after code changes."

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
