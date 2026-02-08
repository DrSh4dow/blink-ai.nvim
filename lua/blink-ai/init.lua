local config = require("blink-ai.config")
local context = require("blink-ai.context")
local commands = require("blink-ai.commands")
local providers = require("blink-ai.providers")
local state = require("blink-ai.state")
local transform = require("blink-ai.transform")
local util = require("blink-ai.util")

local M = {}

local Source = {}
Source.__index = Source

function M.setup(opts)
  local cfg = config.setup(opts)
  state.set_stats_enabled(cfg.stats and cfg.stats.enabled)
  providers.setup(cfg)
  commands.setup()
end

function M.register_provider(name, provider)
  providers.register(name, provider)
end

function M.new(opts, provider_config)
  local self = setmetatable({}, Source)
  self.opts = opts or {}
  self.provider_config = provider_config or {}
  self._stream_output = nil
  self._cancel = nil

  local cfg = config.get()
  self._debouncer = util.debouncer(cfg.debounce_ms, function(ctx, callback)
    self:_do_complete(ctx, callback)
  end)

  providers.setup(cfg)
  return self
end

function Source:enabled()
  if not state.is_enabled() then
    return false
  end
  local cfg = config.get()
  local ft = vim.bo.filetype
  local provider_name = config.resolve_provider(ft)
  local provider = providers.get(provider_name)
  if not provider then
    return false
  end

  if cfg.filetypes and #cfg.filetypes > 0 then
    if not vim.tbl_contains(cfg.filetypes, ft) then
      return false
    end
  end
  if cfg.filetypes_exclude and vim.tbl_contains(cfg.filetypes_exclude, ft) then
    return false
  end
  return true
end

function Source:get_trigger_characters()
  return {}
end

function Source:get_completions(ctx, callback)
  if self._cancel then
    state.cancel("superseded")
    self._cancel = nil
  end
  self._stream_output = nil
  self._debouncer.call(ctx, callback)

  return function()
    if self._cancel then
      state.cancel("source_cancel")
      self._cancel = nil
    end
    state.clear_cancel()
    self._debouncer.cancel()
  end
end

function Source:_do_complete(ctx, callback)
  local cfg = config.get()
  state.set_stats_enabled(cfg.stats and cfg.stats.enabled)
  local prompt_ctx = context.get(ctx, cfg)
  local provider_name, provider_options = config.resolve_provider(prompt_ctx.filetype)
  local provider = providers.get(provider_name)
  if not provider then
    util.notify_once(
      "provider_missing:" .. tostring(provider_name),
      "blink-ai: provider '" .. tostring(provider_name) .. "' is not registered"
    )
    callback({ items = {}, is_incomplete_forward = false })
    return
  end

  local runtime_cfg = vim.tbl_deep_extend("force", {}, cfg, {
    provider = provider_name,
    effective_provider = provider_name,
    effective_provider_config = provider_options,
    timeout_ms = self.provider_config.timeout_ms or self.opts.timeout_ms,
  })
  local started_at = state.record_request(provider_name, provider_options.model)

  local finished = false

  local function on_chunk(output)
    if finished then
      return
    end
    self._stream_output = output
    local items = transform.items_from_output(self._stream_output, ctx, runtime_cfg)
    callback({ items = items, is_incomplete_forward = true })
  end

  local function on_done()
    if finished then
      return
    end
    finished = true
    self._cancel = nil
    state.clear_cancel()
    state.record_success(started_at)
    local items = transform.items_from_output(self._stream_output, ctx, runtime_cfg)
    callback({ items = items, is_incomplete_forward = false })
  end

  local function on_error(err)
    if finished then
      return
    end
    finished = true
    self._cancel = nil
    state.clear_cancel()
    local message = err
    local key = nil
    if type(err) == "table" then
      message = err.message or err[1] or "Request failed"
      key = err.key
    end
    state.record_error(started_at, message)
    util.notify_once(key or ("error:" .. tostring(message)), tostring(message))
    callback({ items = {}, is_incomplete_forward = false })
  end

  self._cancel = provider.complete(prompt_ctx, on_chunk, on_done, on_error, runtime_cfg) or nil
  if type(self._cancel) ~= "function" then
    self._cancel = nil
  end
  state.set_cancel(self._cancel)
end

function Source:resolve(item, callback)
  if not item.documentation or item.documentation == "" then
    local text = ""
    if item.textEdit and item.textEdit.newText then
      text = item.textEdit.newText
    elseif item.insertText then
      text = item.insertText
    else
      text = item.label
    end
    item.documentation = {
      kind = "plaintext",
      value = text,
    }
  end
  callback(item)
end

M.Source = Source

return M
