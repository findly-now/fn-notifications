.PHONY: help up down setup test test-unit test-integration test-all logs
.PHONY: deploy-schema-postgres check-env

help: ## Show available commands
	@echo "Available commands:"
	@echo ""
	@echo "Development (Cloud Native):"
	@echo "  up              - Start application with cloud services"
	@echo "  down            - Stop application"
	@echo "  setup           - Setup cloud dependencies and deploy schema"
	@echo "  deploy-schema-postgres - Deploy schema to PostgreSQL (cloud)"
	@echo "  check-env       - Check cloud environment configuration"
	@echo ""
	@echo "Testing:"
	@echo "  test            - Run all tests"
	@echo "  test-unit       - Run unit tests only"
	@echo "  test-integration - Run integration tests only"
	@echo "  test-all        - Run all tests with coverage"
	@echo ""
	@echo "Utilities:"
	@echo "  logs            - View application logs"

up: ## Start application with cloud services
	@echo "Starting FN-Notifications with cloud services..."
	@echo "Make sure your .env file contains cloud service credentials!"
	docker-compose up -d

down: ## Stop application
	docker-compose down

setup: ## Setup cloud dependencies and deploy schema
	@echo "Setting up cloud-native development environment..."
	@echo "1. Installing dependencies..."
	mix deps.get
	@echo "2. Deploying schema to Supabase..."
	@make deploy-schema-postgres || echo "Schema deployment failed - make sure DATABASE_URL is set"
	@echo "3. Cloud setup complete!"

test: ## Run all tests
	@if ! docker-compose ps app | grep -q "Up"; then \
		echo "Starting services..."; \
		make up; \
		sleep 15; \
	fi
	docker-compose exec app mix test

test-unit: ## Run unit tests only
	mix test --exclude integration

test-integration: ## Run integration tests only
	@echo "Running integration tests with cloud services..."
	@if [ -z "$$TEST_DATABASE_URL" ] && [ -z "$$DATABASE_URL" ]; then \
		echo "ERROR: TEST_DATABASE_URL or DATABASE_URL environment variable not set"; \
		echo "Integration tests require cloud database connection"; \
		exit 1; \
	fi
	docker-compose run --rm -e MIX_ENV=test app mix test --only integration

test-all: ## Run all tests with coverage
	@if ! docker-compose ps app | grep -q "Up"; then \
		echo "Starting services..."; \
		make up; \
		sleep 15; \
	fi
	docker-compose exec app mix test --cover

logs: ## View logs
	docker-compose logs -f app

deploy-schema-postgres: ## Deploy schema.sql to PostgreSQL (cloud)
	@if [ -z "$$DATABASE_URL" ]; then \
		echo "ERROR: DATABASE_URL environment variable not set"; \
		echo "Set it in your .env file or export it manually"; \
		exit 1; \
	fi
	@echo "Deploying schema to PostgreSQL..."
	psql "$$DATABASE_URL" -f schema.sql
	@echo "Schema deployed successfully!"

# Development helpers
check-env: ## Check if environment variables are set for cloud development
	@echo "Checking cloud environment configuration..."
	@echo -n "ENVIRONMENT: "; echo $${ENVIRONMENT:-"not set (will default to staging)"}
	@echo -n "DATABASE_URL: "; echo $${DATABASE_URL:-"not set"}
	@echo -n "KAFKA_BROKERS: "; echo $${KAFKA_BROKERS:-"not set"}
	@echo -n "BUCKET_NAME: "; echo $${BUCKET_NAME:-"not set"}
	@if [ "$$ENVIRONMENT" = "staging" ] || [ "$$ENVIRONMENT" = "production" ]; then \
		echo "✅ Environment configured for cloud services"; \
	else \
		echo "ℹ️  Environment configured for staging by default"; \
	fi