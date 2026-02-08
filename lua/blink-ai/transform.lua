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

local function lsp_range_from_ctx(ctx)
  if ctx and ctx.text_edit and ctx.text_edit.range then
    return ctx.text_edit.range
  end
  if ctx and ctx.range and ctx.range.start and ctx.range["end"] then
    return ctx.range
  end
  local cursor = (ctx and ctx.cursor) or vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]
  return {
    start = { line = line, character = col },
    ["end"] = { line = line, character = col },
  }
end

function M.items_from_output(output, ctx, cfg)
  local entries = normalize_output(output)
  local items = {}

  for index, text in ipairs(entries) do
    if text ~= "" then
      local label = truncate(first_line(text), 80)
      local item = {
        label = label,
        kind = vim.lsp.protocol.CompletionItemKind.Text,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        textEdit = {
          newText = text,
          range = lsp_range_from_ctx(ctx),
        },
        documentation = {
          kind = "plaintext",
          value = text,
        },
        filterText = "",
        sortText = string.format("ai%02d", index),
        data = { source = "blink-ai" },
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
