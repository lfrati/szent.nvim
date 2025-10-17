local M = {}
local api = vim.api
local ui = require("szent.ui")

local defaults = {
    -- format: session:window.pane
    target_pane = ":.2",
    move_to_next_cell = true,
    cell_delimiter = [[^\s*#\s*%%]],
    repl_commands = {},
    highlight_ns = vim.api.nvim_create_namespace("szent_highlight"),
    timeout = 200
}

M.opts = vim.deepcopy(defaults)

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "szent" })
end

local function trim(str)
    if not str then
        return ""
    end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_list(value)
    if type(value) == "string" then
        return { value }
    end
    if type(value) ~= "table" then
        return {}
    end
    local result = {}
    for _, item in ipairs(value) do
        if type(item) == "string" and item ~= "" then
            table.insert(result, item)
        end
    end
    return result
end

local Tmux = require("szent.tmux")
local tmux = Tmux.new({
    notify = notify,
    target_pane = M.opts.target_pane,
    repl_commands = M.opts.repl_commands,
})

-- #################################################################################
-- ##                              TEXT UTILS                                     ##
-- #################################################################################

local function highlight_range(range)
    vim.hl.range(
        0,
        M.opts.highlight_ns,
        "Visual",
        { range.start_line, 0 },
        { range.end_line - 1, 0 },
        { timeout = M.opts.timeout }
    )
end

local function get_range(start_line, end_line)
    if not start_line or not end_line then
        error("get_range requires explicit start_line and end_line", 0)
    end

    -- nvim_buf_get_lines({buffer}, {start}, {end}, {strict_indexing})
    -- Indexing is zero-based, end-exclusive. Negative indices are interpreted as
    -- length+1+index: -1 refers to the index past the end. So to get the last
    -- element use start=-2 and end=-1.
    -- Out-of-bounds indices are clamped to the nearest valid value, unless
    -- `strict_indexing` is set.
    local lines = api.nvim_buf_get_lines(0, start_line, end_line - 1, false)
    return lines
end

-- Locate the active cell bounded by delimiter lines around the cursor.
--[[
    1|     cell_range() -> start:1 stop:2
    2|
    3|# %% cell_range() -> start:4 stop:6
    4|
    5|     cell_range() -> start:4 stop:6
    6|
    7|# %%
    8|     cell_range() -> start:8 stop:9
    9|
]]
function M.cell_range()
    local pattern = M.opts.cell_delimiter
    local start_line = vim.fn.searchpos(pattern, "bcnW")[1]
    local end_line = vim.fn.searchpos(pattern, "nW")[1]

    if end_line == 0 then
        end_line = vim.fn.line("$") + 1 -- of course this is 1 based >_>
    end

    return {
        start_line = start_line,
        end_line = end_line,
    }
end

function M.visual_range()
    local start_line = vim.fn.getpos("v")[2]
    local end_line = vim.fn.getpos(".")[2]

    -- start doesn't mean top, it means start
    -- if you start at a line and go up, start > end
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    return {
        start_line = start_line - 1,
        end_line = end_line + 1,
    }
end

function M.paragraph_range()
    local start_line = vim.fn.search('^\\s*$', 'bcnW')
    local end_line = vim.fn.search('^\\s*$', 'cnW')

    -- at the end of the file there are no empty lines after
    end_line = (end_line == 0) and vim.fn.line('$') + 1 or end_line

    return {
        start_line = start_line,
        end_line = end_line,
    }
end

-- #################################################################################
-- ##                              CONF                                           ##
-- #################################################################################

function M.setup(opts)
    local base = vim.deepcopy(defaults)
    M.opts = vim.tbl_deep_extend("force", base, opts or {})
    M.opts.repl_commands = normalize_list(M.opts.repl_commands)

    tmux:set_notify(notify)
    tmux:set_socket_name(Tmux.detect_tmux_socket() or "")
    tmux:set_target_pane(M.opts.target_pane or "")
    tmux:set_repl_commands(M.opts.repl_commands)
    M.opts.target_pane = tmux:get_target_pane()
end

function M.configure()
    local panes_output = tmux:list_panes()
    if not panes_output then
        return
    end
    panes_output = trim(panes_output)
    if panes_output == "" then
        return
    end

    -- Split tmux output into lines for selection
    local panes = {}
    for line in panes_output:gmatch("[^\r\n]+") do
        table.insert(panes, line)
    end

    ui.select(panes, {
        prompt = string.format("Select target pane [current: %s] (C-b q)", tmux:get_target_pane()),
        format_item = nil,
    }, function(choice)
        if not choice then
            return notify("No pane selected.", vim.log.levels.INFO)
        end
        local selected = trim(choice:match("%[(.-)%]") or choice)
        tmux:set_target_pane(selected)
        M.opts.target_pane = tmux:get_target_pane()
        notify("Configured target pane = " .. tmux:get_target_pane(), vim.log.levels.INFO)
    end)
end

-- #################################################################################
-- ##                              CORE                                           ##
-- #################################################################################

-- Main entry point: push text to tmux using load-buffer/paste-buffer.
function M.send(text)
    tmux:send(text)
    tmux:press("Enter")
end

local function ensure_two_newlines(s)
    -- Count how many newlines are at the end
    local n = 0
    while s:sub(-1 - n, -1 - n) == "\n" do
        n = n + 1
    end
    if n >= 2 then
        return s
    else
        return s .. string.rep("\n", 2 - n)
    end
end

function M.send_visual()
    local range = M.visual_range()
    -- highlight_range(range) -- no need to highlight the highlighting

    local lines = get_range(range.start_line, range.end_line)
    local text = table.concat(lines, "\n")
    text = ensure_two_newlines(text)
    M.send(text)
end

function M.send_cell()
    local range = M.cell_range()
    highlight_range(range)

    local lines = get_range(range.start_line, range.end_line)
    local text = table.concat(lines, "\n")
    text = ensure_two_newlines(text)
    M.send(text)

    if not M.opts.move_to_next_cell then
        return
    end

    local destination = range.next_delim or math.min(range.end_line + 1, api.nvim_buf_line_count(0))
    api.nvim_win_set_cursor(0, { destination, 0 })
    vim.cmd("normal! zz")
end

function M.send_paragraph()
    local range = M.paragraph_range()
    highlight_range(range)

    local lines = get_range(range.start_line, range.end_line)
    local text = table.concat(lines, "\n")
    text = ensure_two_newlines(text)
    M.send(text)
end

return M
