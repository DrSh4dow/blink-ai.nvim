local M = {}

local function health_api()
  local ok, health = pcall(require, "vim.health")
  if ok then
    return health.start, health.ok, health.warn, health.error
  end
  return vim.health.report_start,
    vim.health.report_ok,
    vim.health.report_warn,
    vim.health.report_error
end

local function has_neovim_010()
  return vim.fn.has("nvim-0.10") == 1
end

local function has_value(value)
  return type(value) == "string" and value ~= ""
end

function M.check()
  local start, ok, warn, err = health_api()
  local cfg = require("blink-ai.config").get()

  start("blink-ai.nvim")

  if has_neovim_010() then
    ok("Neovim 0.10+ detected")
  else
    err("Neovim 0.10+ is required (vim.system support)")
  end

  if vim.fn.executable("curl") == 1 then
    ok("curl executable found")
  else
    err("curl executable is missing; install curl and ensure it is on PATH")
  end

  local provider = cfg.provider
  if has_value(provider) then
    ok("Active provider: " .. provider)
  else
    warn("No active provider configured")
  end

  local p = cfg.providers or {}
  local openai = p.openai or {}
  if has_value(openai.endpoint) then
    ok("OpenAI endpoint configured")
  else
    warn("OpenAI endpoint is empty")
  end
  if has_value(openai.api_key) or has_value(os.getenv("OPENAI_API_KEY")) then
    ok("OpenAI key configured")
  else
    warn("OpenAI key missing (providers.openai.api_key or OPENAI_API_KEY)")
  end

  local anthropic = p.anthropic or {}
  if has_value(anthropic.endpoint) then
    ok("Anthropic endpoint configured")
  else
    warn("Anthropic endpoint is empty")
  end
  if has_value(anthropic.api_key) or has_value(os.getenv("ANTHROPIC_API_KEY")) then
    ok("Anthropic key configured")
  else
    warn("Anthropic key missing (providers.anthropic.api_key or ANTHROPIC_API_KEY)")
  end

  local compat = p.openai_compatible or {}
  if has_value(compat.endpoint) then
    ok("OpenAI-compatible endpoint configured")
  else
    warn("OpenAI-compatible endpoint is empty (set when using this provider)")
  end

  local fim = p.fim or {}
  if has_value(fim.endpoint) then
    ok("FIM endpoint configured")
  else
    warn("FIM endpoint is empty (set when using this provider)")
  end

  if
    type(cfg.context) == "table"
    and type(cfg.context.before_cursor_lines) == "number"
    and type(cfg.context.after_cursor_lines) == "number"
  then
    ok("Context window configured")
  else
    warn("Context window configuration is invalid")
  end

  if type(cfg.debounce_ms) == "number" and cfg.debounce_ms >= 0 then
    ok("Debounce configured: " .. tostring(cfg.debounce_ms) .. "ms")
  else
    warn("debounce_ms should be a non-negative number")
  end
end

return M
