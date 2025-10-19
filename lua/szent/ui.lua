local M = {}

M.ns = {}
M.ns.highlight = vim.api.nvim_create_namespace("szent_highlight")
M.ns.popup = vim.api.nvim_create_namespace("szent_popup")
vim.api.nvim_set_hl(M.ns.popup, "SzentCyan", { fg = "#00ffff" })
vim.api.nvim_set_hl(M.ns.popup, "SzentRed", { fg = "#e06c75", bold = true })
vim.api.nvim_set_hl(M.ns.popup, "SzentGreen", { fg = "#98c379" })
vim.api.nvim_set_hl(M.ns.popup, "SzentGray", { fg = "#717280" })
vim.api.nvim_set_hl(M.ns.popup, "SzentYellow", { fg = "#e5c07b" })

vim.api.nvim_set_hl(M.ns.popup, 'SzentCmd', { link = "SzentRed" })
vim.api.nvim_set_hl(M.ns.popup, 'SzentActive', { link = "SzentYellow" })
vim.api.nvim_set_hl(M.ns.popup, 'FloatBorder', { link = "SzentGray" })
vim.api.nvim_set_hl(M.ns.popup, 'Normal', { link = "SzentGray" })
vim.api.nvim_set_hl(M.ns.popup, 'FloatTitle', { link = "SzentGreen" })

function M.namespace()
    return M.ns
end

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

    -- withoug this matchadd won't know what the F SzentRed is
    vim.api.nvim_win_set_hl_ns(win, M.ns.popup)



    -- format items
    local lines = {}
    for i, item in ipairs(items) do
        local text = opts.format_item and opts.format_item(item) or tostring(item)
        table.insert(lines, text)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

    -- | Part   | Meaning                                                                     |
    -- | ------ | --------------------------------------------------------------------------- |
    -- | `\v`   | “Very magic” mode — simplifies syntax, so you don’t need to escape so much. |
    -- | `\]`   | Literal `]` character.                                                      |
    -- | `[ ]*` | Zero or more spaces after that bracket.                                     |
    -- | `\zs`  | *Start the match here* — everything before this is not highlighted.         |
    -- | `\S+`  | One or more non-space characters (the command word).                        |
    vim.fn.matchadd("SzentCmd", [[\v\][ ]*\zs\S+]])

    -- | Part   | Meaning                                                      |
    -- | ------ | ------------------------------------------------------------ |
    -- | `\v`   | “very magic” mode → simpler regex syntax                     |
    -- | `\]`   | literal closing bracket                                      |
    -- | `[ ]*` | any number of spaces after it                                |
    -- | `\zs`  | start the highlight *here* (so the `]` itself isn’t colored) |
    -- | `\S+`  | one or more non-space characters (the command name)          |
    vim.fn.matchadd("SzentActive", [[\v\*[ ]*$]])

    local current = 1
    local function highlight_line()
        vim.api.nvim_buf_clear_namespace(buf, M.ns.highlight, 0, -1)
        vim.api.nvim_buf_set_extmark(buf, M.ns.highlight, current - 1, 0, {
            end_line = current,
            end_col = 0,
            hl_group = "Visual",
        })
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
