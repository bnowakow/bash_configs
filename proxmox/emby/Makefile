.DEFAULT_GOAL := help
.PHONY: help upgrade restart logs install-cron

COMPOSE := docker compose -f $(CURDIR)/compose.yaml

help:
	@printf '\033[1;32mEmby and Nubile targets\033[0m\n\n'
	@printf '  \033[36m%-18s\033[0m %s\n' 'make upgrade' 'Check images and update Emby and Nubile' 'make restart' 'Recreate Emby and Nubile and wait until healthy' 'make logs' 'Follow logs (SERVICE=emby|nubile to filter)' 'make install-cron' 'Install daily updates at 04:30 (requires sudo)'

upgrade:
	./upgrade.sh

# Recreate rather than `docker compose restart`, so mounts and config are
# re-established from scratch; --wait fails if a media healthcheck fails.
restart:
	$(COMPOSE) up -d --force-recreate --wait --wait-timeout 120

# Follow the last 100 lines; SERVICE=emby or SERVICE=nubile limits output.
logs:
	$(COMPOSE) logs -f --tail=100 $(SERVICE)

install-cron:
	./install-cron.sh
