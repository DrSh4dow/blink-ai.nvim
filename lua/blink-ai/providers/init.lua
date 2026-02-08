local M = {}

local registry = {}

function M.register(name, provider)
  if not name or name == "" then
    return
  end
  provider = provider or {}
  provider.name = provider.name or name
  registry[name] = provider
end

function M.get(name)
  return registry[name]
end

function M.list()
  return vim.tbl_keys(registry)
end

function M.setup(cfg)
  local providers_cfg = (cfg and cfg.providers) or {}
  for name, provider in pairs(registry) do
    if provider.setup then
      provider.setup(providers_cfg[name] or {}, cfg or {})
    end
  end
end

M.register("openai", require("blink-ai.providers.openai"))
M.register("anthropic", require("blink-ai.providers.anthropic"))
M.register("ollama", require("blink-ai.providers.ollama"))
M.register("openai_compatible", require("blink-ai.providers.openai_compatible"))
M.register("fim", require("blink-ai.providers.fim"))

return M
