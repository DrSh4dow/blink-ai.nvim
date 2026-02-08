local context = require("blink-ai.context")

describe("context.get", function()
  it("extracts before/after context and user hook output", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local foo = 1",
      "return foo",
    })

    local result = context.get({
      bufnr = bufnr,
      cursor = { 2, 6 },
    }, {
      context = {
        before_cursor_lines = 5,
        after_cursor_lines = 5,
        enable_treesitter = false,
        user_context = function()
          return "test-hook"
        end,
      },
    })

    assert.truthy(result.context_before_cursor:find("local foo = 1", 1, true))
    assert.truthy(result.context_before_cursor:find("return", 1, true))
    assert.are.equal(" foo", result.context_after_cursor)
    assert.are.equal("test-hook", result.user_context)
  end)
end)
