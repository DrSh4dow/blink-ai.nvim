STYLUA ?= stylua
LUACHECK ?= luacheck
NVIM ?= nvim

.PHONY: format format-check lint docs-check test smoke test-all

format:
	$(STYLUA) lua doc tests scripts

format-check:
	$(STYLUA) --check lua doc tests scripts

lint:
	$(LUACHECK) lua tests scripts

docs-check:
	bash scripts/check-doc-sync.sh

test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" -c "qa"

smoke:
	$(NVIM) --headless -u NONE -i NONE -c "luafile scripts/provider_smoke.lua" -c "qa"

test-all: format-check lint docs-check test
