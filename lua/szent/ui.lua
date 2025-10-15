local M = {}



function M.select(items, opts, on_choice)
  opts = opts or {}
  local prompt = opts.prompt or ""
  local width = 50
  local height = #items
  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = prompt,
    title_pos = "center",
  })

  -- format items
  local lines = {}
  for i, item in ipairs(items) do
    local text = opts.format_item and opts.format_item(item) or tostring(item)
    table.insert(lines, text)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local current = 1
  local function highlight_line()
    vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Visual", current - 1, 0, -1)
    vim.api.nvim_win_set_cursor(win, { current, 0 })
  end
  highlight_line()

  local function close(choice)
    vim.api.nvim_win_close(win, true)
    if on_choice then
      on_choice(choice, choice and current or nil)
    end
  end

  -- simple keymaps: {Up/Down | j/k} + Enter + {q | Esc}
  vim.keymap.set("n", "j", function()
    current = math.min(current + 1, #items)
    highlight_line()
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Down>", function()
    current = math.min(current + 1, #items)
    highlight_line()
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "k", function()
    current = math.max(current - 1, 1)
    highlight_line()
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Up>", function()
    current = math.max(current - 1, 1)
    highlight_line()
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "<CR>", function()
    close(items[current])
  end, { buffer = buf, nowait = true })
  
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    close(nil)
  end, { buffer = buf, nowait = true })
end

return M
