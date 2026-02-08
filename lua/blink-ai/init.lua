local config = require("blink-ai.config")
local context = require("blink-ai.context")
local providers = require("blink-ai.providers")
local transform = require("blink-ai.transform")
local util = require("blink-ai.util")

local M = {}

local Source = {}
Source.__index = Source

function M.setup(opts)
  config.setup(opts)
  providers.setup(config.get())
end

function M.register_provider(name, provider)
  providers.register(name, provider)
end

function M.new(opts, _)
  local self = setmetatable({}, Source)
  self.opts = opts or {}
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
  local cfg = config.get()
  local provider = providers.get(cfg.provider)
  if not provider then
    return false
  end

  local ft = vim.bo.filetype
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
    self._cancel()
    self._cancel = nil
  end
  self._stream_output = nil
  self._debouncer.call(ctx, callback)

  return function()
    if self._cancel then
      self._cancel()
      self._cancel = nil
    end
    self._debouncer.cancel()
  end
end

function Source:_do_complete(ctx, callback)
  local cfg = config.get()
  local provider = providers.get(cfg.provider)
  if not provider then
    util.notify_once(
      "provider_missing:" .. tostring(cfg.provider),
      "blink-ai: provider '" .. tostring(cfg.provider) .. "' is not registered"
    )
    callback({ items = {}, is_incomplete_forward = false })
    return
  end

  local prompt_ctx = context.get(ctx, cfg)

  local function on_chunk(output)
    self._stream_output = output
    local items = transform.items_from_output(self._stream_output, ctx, cfg)
    callback({ items = items, is_incomplete_forward = true })
  end

  local function on_done()
    local items = transform.items_from_output(self._stream_output, ctx, cfg)
    callback({ items = items, is_incomplete_forward = false })
  end

  local function on_error(err)
    util.notify(err)
    callback({ items = {}, is_incomplete_forward = false })
  end

  self._cancel = provider.complete(prompt_ctx, on_chunk, on_done, on_error, cfg) or nil
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
