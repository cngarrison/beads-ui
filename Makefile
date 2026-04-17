# Makefile — BeadsUI
# Compiles BeadsUI.swift into a macOS app bundle.
#
# Usage:
#   make             — build native-arch BeadsUI.app (fast, for local dev)
#   make universal   — build universal binary (arm64 + x86_64) via lipo
#   make run         — build and open the app
#   make icon        — convert BeadsUI.svg → BeadsUI.icns (requires: brew install librsvg)
#   make clean       — remove the built app and icon scratch files
#   make setup       — one-time repo setup (git hooks, bd bootstrap)

APP_NAME  := BeadsUI
BUNDLE    := $(APP_NAME).app
BINARY    := $(BUNDLE)/Contents/MacOS/$(APP_NAME)
PLIST_DST := $(BUNDLE)/Contents/Info.plist
RES_DIR   := $(BUNDLE)/Contents/Resources
ICONSET   := $(APP_NAME).iconset
ICNS      := $(APP_NAME).icns

# Detect host architecture (arm64 on Apple Silicon, x86_64 on Intel)
ARCH   := $(shell uname -m)
TARGET := $(ARCH)-apple-macos13.0
SDK    := $(shell xcrun --sdk macosx --show-sdk-path)

.PHONY: all universal run icon clean setup

all: $(BUNDLE)
	@echo ""
	@echo "✅  Built $(BUNDLE)  —  run with: make run"

$(BUNDLE): $(wildcard *.swift) Info.plist
	@echo "→ Compiling $(APP_NAME) for $(TARGET)…"
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(RES_DIR)
	swiftc \
		-parse-as-library \
		-sdk "$(SDK)" \
		-target $(TARGET) \
		-O \
		-o "$(BINARY)" \
		*.swift
	@cp Info.plist "$(PLIST_DST)"
	@# Copy icon into bundle if it has been built
	@if [ -f "$(ICNS)" ]; then \
		cp "$(ICNS)" "$(RES_DIR)/AppIcon.icns"; \
		echo "✓  Bundled icon: AppIcon.icns"; \
	fi

# ───────────────────────────────────────────────────────────────────────────
# Icon pipeline: SVG → PNG → .iconset → .icns
# Requires: brew install librsvg
# ───────────────────────────────────────────────────────────────────────────
icon: $(ICNS)
	@echo "✅  $(ICNS) ready — rebuild the app bundle with: make"

$(ICNS): BeadsUI.svg
	@echo "→ Converting SVG → PNG → .icns…"
	@command -v rsvg-convert >/dev/null 2>&1 || \
		{ echo "❌ rsvg-convert not found. Install with: brew install librsvg"; exit 1; }
	@mkdir -p $(ICONSET)
	@rsvg-convert -w 1024 -h 1024 BeadsUI.svg -o _icon_1024.png
	@sips -z 16   16   _icon_1024.png --out $(ICONSET)/icon_16x16.png    > /dev/null
	@sips -z 32   32   _icon_1024.png --out $(ICONSET)/icon_16x16@2x.png > /dev/null
	@sips -z 32   32   _icon_1024.png --out $(ICONSET)/icon_32x32.png    > /dev/null
	@sips -z 64   64   _icon_1024.png --out $(ICONSET)/icon_32x32@2x.png > /dev/null
	@sips -z 128  128  _icon_1024.png --out $(ICONSET)/icon_128x128.png  > /dev/null
	@sips -z 256  256  _icon_1024.png --out $(ICONSET)/icon_128x128@2x.png > /dev/null
	@sips -z 256  256  _icon_1024.png --out $(ICONSET)/icon_256x256.png  > /dev/null
	@sips -z 512  512  _icon_1024.png --out $(ICONSET)/icon_256x256@2x.png > /dev/null
	@sips -z 512  512  _icon_1024.png --out $(ICONSET)/icon_512x512.png  > /dev/null
	@cp _icon_1024.png $(ICONSET)/icon_512x512@2x.png
	@iconutil -c icns $(ICONSET) -o $(ICNS)
	@rm -rf $(ICONSET) _icon_1024.png

setup:
	@echo "→ Configuring git hooks…"
	@git config core.hooksPath .githooks
	@echo "→ Bootstrapping beads issue tracker…"
	@bd bootstrap
	@echo "✅  Setup complete."

# ───────────────────────────────────────────────────────────────────────────
# Universal binary: arm64 + x86_64 combined with lipo
# Used by the CI release workflow; not needed for local dev
# ───────────────────────────────────────────────────────────────────────────
universal:
	@echo "→ Compiling $(APP_NAME) for arm64…"
	@mkdir -p $(BUNDLE)/Contents/MacOS $(RES_DIR)
	swiftc \
		-parse-as-library \
		-sdk "$(SDK)" \
		-target arm64-apple-macos13.0 \
		-O \
		-o "$(BINARY)-arm64" \
		*.swift
	@echo "→ Compiling $(APP_NAME) for x86_64…"
	swiftc \
		-parse-as-library \
		-sdk "$(SDK)" \
		-target x86_64-apple-macos13.0 \
		-O \
		-o "$(BINARY)-x86_64" \
		*.swift
	@echo "→ Creating universal binary with lipo…"
	lipo -create -output "$(BINARY)" "$(BINARY)-arm64" "$(BINARY)-x86_64"
	@rm "$(BINARY)-arm64" "$(BINARY)-x86_64"
	@cp Info.plist "$(PLIST_DST)"
	@if [ -f "$(ICNS)" ]; then \
		cp "$(ICNS)" "$(RES_DIR)/AppIcon.icns"; \
		echo "✓  Bundled icon: AppIcon.icns"; \
	fi
	@echo ""
	@echo "✅  Built universal $(BUNDLE)  —  run with: make run"
	@echo "    $(lipo -archs \"$(BINARY)\")"

run: $(BUNDLE)
	open "$(BUNDLE)"

clean:
	@rm -rf "$(BUNDLE)" $(ICONSET) _icon_1024.png
	@echo "✔  Cleaned."
