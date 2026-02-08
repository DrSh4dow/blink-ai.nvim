local config = require("blink-ai.config")
local providers = require("blink-ai.providers")
local state = require("blink-ai.state")

local M = {}

local function status_message(cfg)
  local provider = cfg.provider
  local model = (cfg.providers[provider] or {}).model or ""
  local stats = state.stats
  local lines = {
    "blink-ai status:",
    "  enabled: " .. tostring(state.is_enabled()),
    "  provider: " .. tostring(provider),
    "  model: " .. (model ~= "" and model or "(none)"),
    "  requests: " .. stats.requests .. " (ok " .. stats.successes .. ", errors " .. stats.errors .. ")",
  }
  if stats.last_duration_ms then
    table.insert(lines, "  last_duration_ms: " .. stats.last_duration_ms)
  end
  if state.last_error then
    table.insert(lines, "  last_error: " .. state.last_error)
  end
  return table.concat(lines, "\n")
end

local function notify_info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "blink-ai" })
end

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "blink-ai" })
end

local function handle_command(args)
  local sub = args.fargs[1] or "status"
  local cfg = config.get()

  if sub == "status" then
    notify_info(status_message(cfg))
    return
  end

  if sub == "toggle" then
    local enabled = state.toggle()
    if not enabled then
      state.cancel()
    end
    notify_info("blink-ai " .. (enabled and "enabled" or "disabled"))
    return
  end

  if sub == "provider" then
    local name = args.fargs[2]
    if not name or name == "" then
      notify_error("Usage: :BlinkAI provider <name>")
      return
    end
    if not providers.get(name) then
      notify_error("Unknown provider: " .. name)
      return
    end
    config.set_provider(name)
    providers.setup(config.get())
    notify_info("blink-ai provider set to " .. name)
    return
  end

  if sub == "model" then
    local model = args.fargs[2]
    if not model or model == "" then
      notify_error("Usage: :BlinkAI model <name>")
      return
    end
    config.set_provider_model(cfg.provider, model)
    providers.setup(config.get())
    notify_info("blink-ai model set to " .. model)
    return
  end

  if sub == "clear" then
    if state.cancel() then
      notify_info("blink-ai request cancelled")
    else
      notify_info("blink-ai no active request")
    end
    return
  end

  notify_error("Unknown subcommand: " .. sub)
end

local function complete_command(arg_lead, cmd_line)
  local parts = vim.split(cmd_line, "%s+", { trimempty = true })
  if #parts <= 2 then
    local items = { "status", "toggle", "provider", "model", "clear" }
    return vim.tbl_filter(function(item)
      return item:find("^" .. vim.pesc(arg_lead)) ~= nil
    end, items)
  end

  local sub = parts[2]
  if sub == "provider" then
    local names = providers.list()
    return vim.tbl_filter(function(item)
      return item:find("^" .. vim.pesc(arg_lead)) ~= nil
    end, names)
  end
  return {}
end

function M.setup()
  pcall(vim.api.nvim_del_user_command, "BlinkAI")
  vim.api.nvim_create_user_command("BlinkAI", handle_command, {
    nargs = "*",
    complete = complete_command,
  })
end

return M
