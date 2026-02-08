local M = {}

local function default_system_prompt(ctx)
  local ft = ctx.filetype or "text"
  local name = ctx.filename or ""
  local parts = {
    "You are an AI code completion engine.",
    "Return only the completion text with no Markdown or explanation.",
    "The completion must fit at the <cursor> position.",
    ("Filetype: %s."):format(ft),
  }
  if name ~= "" then
    table.insert(parts, ("Filename: %s."):format(name))
  end
  return table.concat(parts, " ")
end

function M.system_prompt(ctx, cfg)
  if cfg and type(cfg.system_prompt) == "function" then
    return cfg.system_prompt(ctx)
  end
  if cfg and type(cfg.system_prompt) == "string" then
    return cfg.system_prompt
  end
  return default_system_prompt(ctx)
end

function M.chat_messages(ctx, cfg)
  local system = M.system_prompt(ctx, cfg)
  local before = ctx.context_before_cursor or ""
  local after = ctx.context_after_cursor or ""
  local user = before .. "<cursor>" .. after
  return {
    { role = "system", content = system },
    { role = "user", content = user },
  }
end

function M.fim_prompt(ctx, fim_tokens)
  local tokens = fim_tokens or { prefix = "<prefix>", suffix = "<suffix>", middle = "<middle>" }
  local before = ctx.context_before_cursor or ""
  local after = ctx.context_after_cursor or ""
  return table.concat({
    tokens.prefix,
    before,
    tokens.suffix,
    after,
    tokens.middle,
  }, "")
end

return M
