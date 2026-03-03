.PHONY: help test test-swift test-mcp test-evals lint lint-swift lint-shell clean build build-release install dev

# Default target
help:
	@echo "HomeKit Automator - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make test          - Run all tests (Swift + MCP + evals)"
	@echo "  make test-swift    - Run Swift unit tests"
	@echo "  make test-mcp      - Run MCP server integration tests"
	@echo "  make test-evals    - Run eval suite"
	@echo "  make lint          - Run all linters (Swift + shell scripts)"
	@echo "  make lint-swift    - Run SwiftLint"
	@echo "  make lint-shell    - Check shell scripts with shellcheck"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make build         - Build debug version"
	@echo "  make build-release - Build release version"
	@echo "  make install       - Build and install to /Applications"
	@echo "  make dev           - Build, test, and lint (full dev cycle)"
	@echo ""

# Run all tests
test: test-swift test-mcp

# Swift tests
test-swift:
	@echo "==> Running Swift tests..."
	cd scripts/swift && swift test

# Swift tests with coverage (requires llvm-cov)
test-swift-coverage:
	@echo "==> Running Swift tests with coverage..."
	cd scripts/swift && swift test --enable-code-coverage
	cd scripts/swift && swift test --show-codecov-path

# MCP server tests (requires Node.js)
test-mcp:
	@echo "==> Running MCP server tests..."
	cd scripts/mcp-server && npm test

# Run eval suite
test-evals:
	@echo "==> Running evals..."
	@if [ -f "scripts/run-evals.sh" ]; then \
		./scripts/run-evals.sh; \
	else \
		echo "No evals script found. Evals are defined in evals/evals.json"; \
	fi

# Lint all code
lint: lint-swift lint-shell

# SwiftLint
lint-swift:
	@echo "==> Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --strict; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi

# Check shell scripts with shellcheck
lint-shell:
	@echo "==> Checking shell scripts with shellcheck..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find scripts -name "*.sh" -type f -exec shellcheck -x {} +; \
	else \
		echo "shellcheck not installed. Install with: brew install shellcheck"; \
		exit 1; \
	fi

# Clean build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	./scripts/build.sh --clean
	rm -rf scripts/swift/.build
	rm -rf scripts/mcp-server/node_modules

# Build debug version
build:
	@echo "==> Building debug version..."
	./scripts/build.sh

# Build release version
build-release:
	@echo "==> Building release version..."
	./scripts/build.sh --release

# Build and install
install:
	@echo "==> Building and installing..."
	./scripts/build.sh --release --install

# Full dev cycle: clean, build, test, lint
dev: clean build test lint
	@echo ""
	@echo "✅ Development cycle complete!"

# Sync models
sync-models:
	@echo "==> Syncing models..."
	./scripts/sync-models.sh

# Check models sync
check-models:
	@echo "==> Checking models sync..."
	./scripts/sync-models.sh

# Update Homebrew formula (requires tag as argument: make update-formula TAG=v1.2.0)
update-formula:
	@if [ -z "$(TAG)" ]; then \
		echo "Usage: make update-formula TAG=v1.2.0"; \
		exit 1; \
	fi
	./scripts/update-formula.sh $(TAG)
