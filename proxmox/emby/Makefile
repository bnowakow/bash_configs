.DEFAULT_GOAL := help
.PHONY: help upgrade install-cron

help:
	@printf '\033[1;32mEmby and Nubile targets\033[0m\n\n'
	@printf '  \033[36m%-18s\033[0m %s\n' 'make upgrade' 'Check images and update Emby and Nubile' 'make install-cron' 'Install daily updates at 04:30 (requires sudo)'

upgrade:
	./upgrade.sh

install-cron:
	./install-cron.sh
