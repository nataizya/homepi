.PHONY: new up down logs ps pull

# Usage: make new name=uptime-kuma
new:
	@mkdir -p services/$(name)
	@sed 's/myservice/$(name)/g' services/_template/compose.yaml > services/$(name)/compose.yaml
	@echo "  - services/$(name)/compose.yaml" >> compose.yaml
	@echo "Created services/$(name)/compose.yaml and registered in compose.yaml"

up:
	docker network create internal 2>/dev/null || true
	docker compose up -d --remove-orphans

down:
	docker compose down

pull:
	docker compose pull

ps:
	docker compose ps

logs:
	docker compose logs -f $(service)
