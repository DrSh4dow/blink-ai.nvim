local M = { name = "fim" }

function M.setup(_) end

function M.complete(_, _, on_done, on_error)
  if on_error then
    on_error("FIM provider is not implemented yet")
  end
  if on_done then
    on_done()
  end
  return function() end
end

return M
