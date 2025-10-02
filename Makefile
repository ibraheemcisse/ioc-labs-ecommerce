.PHONY: all setup run

all: setup run

setup:
	@echo "📦 Installing dependencies..."
	@go mod download
	@./scripts/setup-all.sh

run:
	@echo "🚀 Starting IOC Labs E-Commerce..."
	@go run cmd/api/main.go
