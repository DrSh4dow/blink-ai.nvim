STYLUA ?= stylua
LUACHECK ?= luacheck
NVIM ?= nvim

.PHONY: format lint test

format:
	$(STYLUA) lua doc tests

lint:
	$(LUACHECK) lua tests

test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" -c "qa"
