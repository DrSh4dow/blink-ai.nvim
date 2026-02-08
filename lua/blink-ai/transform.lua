local M = {}

local function normalize_output(output)
  if type(output) == "string" then
    return { output }
  end
  if type(output) ~= "table" then
    return {}
  end
  local keys = {}
  for k, v in pairs(output) do
    if type(k) == "number" and type(v) == "string" then
      table.insert(keys, k)
    end
  end
  table.sort(keys)
  local list = {}
  for _, k in ipairs(keys) do
    table.insert(list, output[k])
  end
  return list
end

local function first_line(text)
  local line = text:match("([^\r\n]+)")
  return line or text
end

local function truncate(text, max)
  if #text <= max then
    return text
  end
  return text:sub(1, max - 3) .. "..."
end

local function ctx_cursor(ctx)
  local cursor = (ctx and ctx.cursor) or vim.api.nvim_win_get_cursor(0)
  return cursor[1] - 1, cursor[2]
end

local function ctx_line_text(ctx, line)
  if ctx and type(ctx.line) == "string" then
    return ctx.line
  end
  if
    ctx
    and type(ctx.line_before_cursor) == "string"
    and type(ctx.line_after_cursor) == "string"
  then
    return ctx.line_before_cursor .. ctx.line_after_cursor
  end
  local bufnr = (ctx and ctx.bufnr) or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
  return lines[1] or ""
end

local function keyword_start_from_ctx(ctx, line, col)
  if ctx then
    if type(ctx.word_start) == "number" then
      return ctx.word_start
    end
    if type(ctx.keyword) == "string" then
      return math.max(0, col - #ctx.keyword)
    end
    if type(ctx.word) == "string" then
      return math.max(0, col - #ctx.word)
    end
    if type(ctx.offset) == "number" then
      local candidate = ctx.offset - 1
      if candidate >= 0 and candidate <= col then
        return candidate
      end
    end
  end

  local line_text = ctx_line_text(ctx, line)
  if line_text == "" then
    return col
  end
  local max_col = math.min(col, #line_text)
  local start_col = max_col
  while start_col > 0 do
    local char = line_text:sub(start_col, start_col)
    if not char:match("[%w_]") then
      break
    end
    start_col = start_col - 1
  end
  return start_col
end

function M.lsp_range_from_ctx(ctx)
  if ctx and ctx.text_edit and ctx.text_edit.range then
    return ctx.text_edit.range
  end
  if ctx and ctx.range and ctx.range.start and ctx.range["end"] then
    return ctx.range
  end
  if ctx and ctx.bounds and ctx.bounds.start and ctx.bounds["end"] then
    return ctx.bounds
  end

  local line, col = ctx_cursor(ctx)
  local start_col = keyword_start_from_ctx(ctx, line, col)
  return {
    start = { line = line, character = start_col },
    ["end"] = { line = line, character = col },
  }
end

local function clone_range(range)
  return {
    start = {
      line = range.start.line,
      character = range.start.character,
    },
    ["end"] = {
      line = range["end"].line,
      character = range["end"].character,
    },
  }
end

function M.items_from_output(output, ctx, cfg, fixed_range)
  local entries = normalize_output(output)
  local items = {}
  local provider = cfg and (cfg.effective_provider or cfg.provider) or "unknown"
  local edit_range = fixed_range or M.lsp_range_from_ctx(ctx)

  for index, text in ipairs(entries) do
    if text ~= "" then
      local label = truncate(first_line(text), 80)
      local item = {
        label = label,
        kind = vim.lsp.protocol.CompletionItemKind.Text,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        textEdit = {
          newText = text,
          range = clone_range(edit_range),
        },
        documentation = {
          kind = "plaintext",
          value = text,
        },
        filterText = "",
        sortText = string.format("0_ai_%03d", index),
        data = {
          source = "blink-ai",
          provider = provider,
          candidate = index,
        },
      }
      table.insert(items, item)
    end
  end

  if cfg and type(cfg.transform_items) == "function" then
    items = cfg.transform_items(items) or items
  end

  return items
end

return M
