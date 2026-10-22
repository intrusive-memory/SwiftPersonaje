# SwiftPersonaje Makefile
#
# Every build and test goes through xcodebuild. SwiftPM's own build and test
# drivers are not used in this project, locally or in CI.

# SwiftPM's per-product schemes have no test action; the `-Package` scheme
# holds every target, the test target included.
SCHEME = SwiftPersonaje-Package
CLI_SCHEME = personaje
BINARY = personaje
BIN_DIR = ./bin

DESTINATION = 'platform=macOS,arch=arm64'

# Apple Silicon only.
ARCH = ARCHS=arm64 ONLY_ACTIVE_ARCH=YES

# Dependencies carry macros and build-tool plugins; skip the trust prompts so
# headless and CI runs don't stall.
XCODE_FLAGS = -skipPackagePluginValidation -skipMacroValidation

DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

export GIT_LFS_SKIP_SMUDGE = 1

.PHONY: build test release install clean resolve lint format help

build:
	xcodebuild build -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  $(XCODE_FLAGS) \
	  CODE_SIGNING_ALLOWED=NO \
	  $(ARCH)

test:
	xcodebuild test -scheme $(SCHEME) \
	  -destination $(DESTINATION) \
	  $(XCODE_FLAGS) \
	  CODE_SIGNING_ALLOWED=NO \
	  $(ARCH)

# Release build of the CLI, copied to ./bin.
release: resolve
	xcodebuild build -scheme $(CLI_SCHEME) \
	  -destination $(DESTINATION) \
	  -configuration Release \
	  $(XCODE_FLAGS) \
	  $(ARCH)
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(ls -td $(DERIVED_DATA)/SwiftPersonaje-*/Build/Products/Release 2>/dev/null | head -1); \
	if [ -n "$$PRODUCT_DIR" ] && [ -x "$$PRODUCT_DIR/$(BINARY)" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Release)"; \
	else \
		echo "Error: could not find $(BINARY) in $(DERIVED_DATA)/SwiftPersonaje-*/Build/Products/Release"; \
		exit 1; \
	fi

# Debug build of the CLI, copied to ./bin.
install: resolve
	xcodebuild build -scheme $(CLI_SCHEME) \
	  -destination $(DESTINATION) \
	  $(XCODE_FLAGS) \
	  $(ARCH)
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(ls -td $(DERIVED_DATA)/SwiftPersonaje-*/Build/Products/Debug 2>/dev/null | head -1); \
	if [ -n "$$PRODUCT_DIR" ] && [ -x "$$PRODUCT_DIR/$(BINARY)" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Debug)"; \
	else \
		echo "Error: could not find $(BINARY) in $(DERIVED_DATA)/SwiftPersonaje-*/Build/Products/Debug"; \
		exit 1; \
	fi

resolve:
	xcodebuild -resolvePackageDependencies -scheme $(SCHEME) -destination $(DESTINATION)

clean:
	xcodebuild clean -scheme $(SCHEME) -destination $(DESTINATION) $(ARCH) 2>/dev/null || true
	rm -rf .build
	rm -rf $(BIN_DIR)
	rm -rf $(DERIVED_DATA)/SwiftPersonaje-*

# Rewrites Swift sources in place with swift-format. Run before committing;
# never a CI gate.
lint:
	swift format -i -r Package.swift Sources Tests
	@echo "Swift sources formatted."

format: lint

help:
	@echo "SwiftPersonaje — available targets:"
	@echo "  build     - Build every target for macOS (arm64)"
	@echo "  test      - Run the test suite on macOS (arm64)"
	@echo "  release   - Release build of the personaje CLI, copied to $(BIN_DIR)/"
	@echo "  install   - Debug build of the personaje CLI, copied to $(BIN_DIR)/"
	@echo "  resolve   - Resolve package dependencies"
	@echo "  lint      - Format Swift sources in place with swift-format (alias: format)"
	@echo "  clean     - Remove build artifacts, $(BIN_DIR)/, and DerivedData"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "macOS destination: $(DESTINATION)"
