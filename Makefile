COMPOSE_FILE := docker-compose.yml
PROJECT_NAME := inadc-jupyter

DOCKER_COMPOSE = docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME)

BLUE=\033[34;1m
GREEN=\033[32m
YELLOW=\033[33m
RED=\033[31m
NC=\033[0m

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "$(BLUE)Make Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##";} \
	     /^[a-zA-Z0-9_.-]+:.*##/ { printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the Jupyter Docker image
	@echo "$(BLUE)Building Jupyter image...$(NC)"
	$(DOCKER_COMPOSE) build jupyter

.PHONY: up
up: ## Start Jupyter (requires inadc-core stack running)
	@echo "$(BLUE)Starting Jupyter...$(NC)"
	@$(DOCKER_COMPOSE) up -d && \
	echo "$(GREEN)Jupyter available at http://localhost:8888$(NC)"

.PHONY: stop
stop: ## Stop Jupyter container
	@echo "$(BLUE)Stopping Jupyter...$(NC)"
	$(DOCKER_COMPOSE) stop

.PHONY: down
down: ## Stop and remove Jupyter container
	@echo "$(BLUE)Removing Jupyter container...$(NC)"
	$(DOCKER_COMPOSE) down

.PHONY: restart
restart: ## Restart Jupyter container
	@echo "$(BLUE)Restarting Jupyter...$(NC)"
	$(DOCKER_COMPOSE) restart

.PHONY: ps
ps: ## Show container status
	@echo "$(BLUE)Container status:$(NC)"
	$(DOCKER_COMPOSE) ps

.PHONY: logs
logs: ## Tail Jupyter logs
	@echo "$(BLUE)Jupyter logs (Ctrl+C to exit):$(NC)"
	$(DOCKER_COMPOSE) logs -f

.PHONY: bash
bash: ## Open a shell in the Jupyter container
	@echo "$(BLUE)Opening shell in Jupyter...$(NC)"
	$(DOCKER_COMPOSE) exec jupyter bash

.PHONY: rebuild
rebuild: ## Rebuild and restart Jupyter (no cache)
	@echo "$(BLUE)Rebuilding Jupyter (no cache)...$(NC)"
	$(DOCKER_COMPOSE) build --no-cache jupyter
	@$(MAKE) up
