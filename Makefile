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

.PHONY: build test test-eval release install clean resolve lint format help

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

# Model-backed character-summary evaluation: the separate Evals/ package
# (macOS 27, SwiftLlavero, Apple's Evaluations framework). Never run in CI.
# Needs Apple Intelligence on this Mac. See Docs/build-and-test.md.
#   PROJECT=<folder holding episodes/>   default: the CC0 example in Evals/Fixtures
#   FIXTURES=<folder of CHARACTER/ dirs> default: $$PROJECT/evals/character-summaries
#   EPISODES=<glob over episodes/>       default: *.fountain
#   MODEL=on-device | pcc | account:model | bruja:<MLX model id>  default: on-device
#     bruja: runs a downloaded local MLX model through SwiftBruja, e.g.
#     MODEL=bruja:mlx-community/Qwen3.5-9B-MLX-4bit
# Reports go to .build/eval/.
EVAL_DIR = Evals
EVAL_SCHEME = PersonajeEvals
# Where SwiftBruja finds the shared local models (from the environment if set).
ACERVO_APP_GROUP_ID ?= group.intrusive-memory.models
# The test runner can't read the App Group container, so a bruja: model is
# cloned (APFS, no extra space) into EVAL_MODELS_DIR and read from there.
EVAL_MODELS_DIR = $(CURDIR)/.build/eval-models
BRUJA_MODEL = $(patsubst bruja:%,%,$(filter bruja:%,$(MODEL)))

test-eval:
	@test "$$GITHUB_ACTIONS" != "true" || { echo "test-eval never runs in GitHub Actions."; exit 1; }
	$(if $(BRUJA_MODEL),sh $(EVAL_DIR)/Scripts/stage-bruja-model.sh "$(BRUJA_MODEL)" "$(EVAL_MODELS_DIR)" "$(ACERVO_APP_GROUP_ID)")
	cd $(EVAL_DIR) && \
	  $(if $(BRUJA_MODEL),TEST_RUNNER_ACERVO_MODELS_DIR="$(EVAL_MODELS_DIR)") \
	  TEST_RUNNER_PERSONAJE_EVAL_PROJECT="$(PROJECT)" \
	  TEST_RUNNER_PERSONAJE_EVAL_FIXTURES="$(FIXTURES)" \
	  TEST_RUNNER_PERSONAJE_EVAL_EPISODES="$(EPISODES)" \
	  TEST_RUNNER_PERSONAJE_EVAL_MODEL="$(or $(MODEL),on-device)" \
	  TEST_RUNNER_PERSONAJE_EVAL_REPORT_DIR="$(CURDIR)/.build/eval" \
	  TEST_RUNNER_ACERVO_APP_GROUP_ID="$(ACERVO_APP_GROUP_ID)" \
	  xcodebuild test -scheme $(EVAL_SCHEME) \
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
	swift format -i -r Package.swift Sources Tests Evals/Package.swift Evals/Sources Evals/Tests
	@echo "Swift sources formatted."

format: lint

help:
	@echo "SwiftPersonaje — available targets:"
	@echo "  build     - Build every target for macOS (arm64)"
	@echo "  test      - Run the test suite on macOS (arm64)"
	@echo "  test-eval - Model-backed character-summary evaluation (Evals/; never in CI)"
	@echo "  release   - Release build of the personaje CLI, copied to $(BIN_DIR)/"
	@echo "  install   - Debug build of the personaje CLI, copied to $(BIN_DIR)/"
	@echo "  resolve   - Resolve package dependencies"
	@echo "  lint      - Format Swift sources in place with swift-format (alias: format)"
	@echo "  clean     - Remove build artifacts, $(BIN_DIR)/, and DerivedData"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "macOS destination: $(DESTINATION)"
