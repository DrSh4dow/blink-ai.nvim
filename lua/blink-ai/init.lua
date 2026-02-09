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
local DEFAULT_LOADING_WATCHDOG_MS = 1200

local function apply_completion_model_strategy(provider_name, provider_options)
  if provider_name ~= "openai" or type(provider_options) ~= "table" then
    return provider_options
  end

  local strategy = provider_options.model_strategy or "fast_for_completion"
  if strategy ~= "fast_for_completion" then
    return provider_options
  end

  if type(provider_options.fast_model) == "string" and provider_options.fast_model ~= "" then
    provider_options.model = provider_options.fast_model
  end

  return provider_options
end

local function loading_item(range, provider)
  return {
    label = "AI (thinking...)",
    kind = vim.lsp.protocol.CompletionItemKind.Text,
    kind_name = "AI",
    kind_icon = "󰚩",
    insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    textEdit = {
      newText = "",
      range = {
        start = {
          line = range.start.line,
          character = range.start.character,
        },
        ["end"] = {
          line = range["end"].line,
          character = range["end"].character,
        },
      },
    },
    filterText = "",
    sortText = "0_ai_000",
    data = {
      source = "blink-ai",
      provider = provider,
      loading = true,
    },
  }
end

local function stop_timer(timer)
  if not timer then
    return
  end
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function loading_placeholder_config(cfg)
  local ui = (cfg and cfg.ui) or {}
  local placeholder = ui.loading_placeholder or {}
  return {
    enabled = placeholder.enabled ~= false,
    watchdog_ms = math.max(0, tonumber(placeholder.watchdog_ms) or DEFAULT_LOADING_WATCHDOG_MS),
  }
end

local function stop_request_watchdog(req)
  if not req then
    return
  end
  stop_timer(req.watchdog)
  req.watchdog = nil
end

local function emit(req, payload)
  if not req or type(req.callback) ~= "function" then
    return
  end
  req.callback(payload)
end

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
  self._request_seq = 0
  self._active_request = nil

  local cfg = config.get()
  self._debouncer = util.debouncer(cfg.debounce_ms, function(ctx, callback)
    self:_do_complete(ctx, callback)
  end)

  providers.setup(cfg)
  return self
end

function Source:_is_active_request(req)
  if not req or req.finished then
    return false
  end
  return self._active_request ~= nil and self._active_request.id == req.id
end

function Source:_clear_loading(req, is_incomplete_forward)
  if not self:_is_active_request(req) or not req.loading_visible then
    return
  end
  req.loading_visible = false
  emit(req, {
    items = {},
    is_incomplete_forward = is_incomplete_forward,
  })
end

function Source:_finalize_request(req, payload)
  if not req or req.finished then
    return
  end
  req.finished = true
  req.loading_visible = false
  stop_request_watchdog(req)
  if self._active_request and self._active_request.id == req.id then
    self._active_request = nil
  end
  if self._cancel == req.cancel_wrapper then
    self._cancel = nil
  end
  state.clear_cancel()
  if payload then
    emit(req, payload)
  end
end

function Source:enabled()
  local _ = self
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
  local _ = self
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
  local placeholder_cfg = loading_placeholder_config(cfg)
  state.set_stats_enabled(cfg.stats and cfg.stats.enabled)
  local prompt_ctx = context.get(ctx, cfg)
  local provider_name, provider_options = config.resolve_provider(prompt_ctx.filetype)
  provider_options = apply_completion_model_strategy(provider_name, provider_options)
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
  self._request_seq = self._request_seq + 1
  local req = {
    id = self._request_seq,
    callback = callback,
    loading_visible = false,
    finished = false,
    watchdog = nil,
    cancel_wrapper = nil,
    provider_cancel = nil,
    started_at = nil,
  }
  self._active_request = req
  local completion_range = transform.lsp_range_from_ctx(ctx)
  req.started_at = state.record_request(provider_name, provider_options.model)
  if placeholder_cfg.enabled then
    req.loading_visible = true
    emit(req, {
      items = { loading_item(completion_range, provider_name) },
      is_incomplete_forward = true,
    })
    if placeholder_cfg.watchdog_ms > 0 then
      req.watchdog = vim.loop.new_timer()
      req.watchdog:start(placeholder_cfg.watchdog_ms, 0, function()
        vim.schedule(function()
          if not self:_is_active_request(req) then
            stop_request_watchdog(req)
            return
          end
          stop_request_watchdog(req)
          self:_clear_loading(req, true)
        end)
      end)
    end
  end

  local function on_chunk(output)
    if not self:_is_active_request(req) then
      return
    end
    self._stream_output = output
  end

  local function on_done()
    if not self:_is_active_request(req) then
      return
    end
    state.record_success(req.started_at)
    local items =
      transform.items_from_output(self._stream_output, ctx, runtime_cfg, completion_range)
    self:_finalize_request(req, { items = items, is_incomplete_forward = false })
  end

  local function on_error(err)
    if not self:_is_active_request(req) then
      return
    end
    local message = err
    local key = nil
    if type(err) == "table" then
      message = err.message or err[1] or "Request failed"
      key = err.key
    end
    state.record_error(req.started_at, message)
    util.notify_once(key or ("error:" .. tostring(message)), tostring(message))
    self:_finalize_request(req, { items = {}, is_incomplete_forward = false })
  end

  local provider_cancel = provider.complete(prompt_ctx, on_chunk, on_done, on_error, runtime_cfg)
    or nil
  if type(provider_cancel) == "function" then
    req.provider_cancel = provider_cancel
  end

  req.cancel_wrapper = function()
    if req.finished then
      return
    end
    if type(req.provider_cancel) == "function" then
      req.provider_cancel()
    end
    self:_finalize_request(
      req,
      req.loading_visible and { items = {}, is_incomplete_forward = false } or nil
    )
  end

  if self:_is_active_request(req) then
    self._cancel = req.cancel_wrapper
    state.set_cancel(self._cancel)
  end
end

function Source:resolve(item, callback)
  local _ = self
  if not item.documentation or item.documentation == "" then
    local text
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
