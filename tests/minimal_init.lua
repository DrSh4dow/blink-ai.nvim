vim.opt.runtimepath:append(vim.fn.getcwd())

local candidates = {
  vim.fn.getcwd() .. "/.tests/plenary.nvim",
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
}

for _, path in ipairs(candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    break
  end
end
