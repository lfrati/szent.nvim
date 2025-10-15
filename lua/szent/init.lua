local M = {}
local api = vim.api
local ui = require("szent.ui")

-- Core tmux -> REPL bridge with bracketed-paste safety.
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

local state = {
    socket_name = "",
    target_pane = M.opts.target_pane,
}

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

local function inside_tmux()
    return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function detect_tmux_socket()
    local tmux_env = vim.env.TMUX
    if not tmux_env or tmux_env == "" then
        return nil
    end
    return tmux_env:match("([^,]+)")
end

local function ensure_tmux()
    if inside_tmux() then
        return true
    end
    notify("Not running inside tmux; launch Neovim from a tmux pane.", vim.log.levels.WARN)
    return false
end

state.socket_name = detect_tmux_socket() or state.socket_name

-- Assemble the base tmux invocation depending on socket configuration.
local function tmux_base_args()
    local socket = trim(state.socket_name or "")
    -- Allow tmux to use its default socket when none is configured.
    if socket == "" then
        return { "tmux" }
    end
    if socket:sub(1, 1) == "/" then
        return { "tmux", "-S", socket }
    end
    -- Named sockets require the -L flag (tmux -L <name>).
    return { "tmux", "-L", socket }
end

-- Wrapper around vim.fn.system that feeds the composed tmux command.
local function run_tmux(args, input)
    if not inside_tmux() then
        return ""
    end
    local command = {}
    vim.list_extend(command, tmux_base_args())
    vim.list_extend(command, args)
    if input ~= nil then
        return vim.fn.system(command, input)
    end
    return vim.fn.system(command)
end

local function current_target_command()
    if state.target_pane == "" then
        return nil
    end
    local output = run_tmux({
        "display-message",
        "-p",
        "-t",
        state.target_pane,
        "#{pane_current_command}",
    })
    output = trim(output)
    if output == "" then
        return nil
    end
    return output
end

-- Helper for case-insensitive substring checks against user-specified lists.
local function matches_any_command(cmd, patterns)
    if not cmd or cmd == "" then
        return false
    end
    if type(patterns) ~= "table" or vim.tbl_isempty(patterns) then
        return false
    end
    local haystack = cmd:lower()
    for _, pattern in ipairs(patterns) do
        if type(pattern) == "string" and pattern ~= "" then
            if haystack:find(pattern:lower(), 1, true) then
                return true
            end
        end
    end
    return false
end

local function target_pane_exists()
    if not ensure_tmux() then
        return false
    end
    if not state.target_pane or state.target_pane == "" then
        return false
    end

    -- has-session will fail (non-zero exit) if the target pane doesn't exist
    run_tmux({ "has-session", "-t", state.target_pane })
    if vim.v.shell_error ~= 0 then
        return false
    end

    return true
end

local function ensure_target_ready()
    if not ensure_tmux() then
        return false
    end

    if not state.target_pane or state.target_pane == "" then
        notify("No tmux pane configured; run :SzentConfig.", vim.log.levels.WARN)
        return false
    end

    -- ensure the configured pane actually exists
    if not target_pane_exists() then
        notify(("Target pane [%s] not found; run :SzentConfig."):format(state.target_pane), vim.log.levels.WARN)
        return false
    end

    local expected = M.opts.repl_commands
    if not expected or vim.tbl_isempty(expected) then
        return true
    end

    local cmd = current_target_command()
    if not cmd then
        notify("Could not determine command running in target tmux pane.", vim.log.levels.WARN)
        return false
    end

    if matches_any_command(cmd, expected) then
        return true
    end

    notify(
        string.format(
            "Target tmux pane %s is running '%s', expected one of: %s",
            state.target_pane or "",
            cmd,
            table.concat(expected, ", ")
        ),
        vim.log.levels.WARN
    )

    return false
end

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

    state.socket_name = detect_tmux_socket() or ""
    state.target_pane = M.opts.target_pane or ""
end

local function list_panes()
    if not ensure_tmux() then
        return nil
    end
    local format = "#{pane_index}) #{pane_current_command}#{?pane_active, *,}\tid:[#{pane_id}]"
    local args = { "list-panes", "-F", format }
    local output = run_tmux(args)

    if vim.v.shell_error ~= 0 then
        notify(("tmux error: %s"):format(trim(output)), vim.log.levels.ERROR)
        return nil
    end

    if trim(output) == "" then
        notify("No tmux panes found.", vim.log.levels.WARN)
        return nil
    end

    return output
end

function M.configure()
    local panes_output = list_panes()
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
        prompt = string.format("Select target pane [current: %s] (C-b q)", state.target_pane),
        format_item = nil,
    }, function(choice)
        if not choice then
            return notify("No pane selected.", vim.log.levels.INFO)
        end
        state.target_pane = trim(choice:match("%[(.-)%]") or choice)
        notify("Configured target pane = " .. state.target_pane, vim.log.levels.INFO)
    end)
end

-- #################################################################################
-- ##                              CORE                                           ##
-- #################################################################################

-- Main entry point: push text to tmux using load-buffer/paste-buffer.
function M.send(text)
    if not ensure_target_ready() or not text then
        return
    end

    if type(text) == "table" then
        if vim.tbl_isempty(text) then
            return
        end
        text = table.concat(text, "\n") .. "\n"
    else
        text = tostring(text)
    end

    if text == "" then
        return
    end

    run_tmux({ "send-keys", "-X", "-t", state.target_pane, "cancel" })

    if text ~= "" then
        run_tmux({ "load-buffer", "-" }, text)
        local paste_args = { "paste-buffer", "-d", "-p", "-t", state.target_pane }
        run_tmux(paste_args)
    end

    run_tmux({ "send-keys", "-t", state.target_pane, "Enter" })
end

function M.send_visual()
    local range = M.visual_range()
    -- highlight_range(range) -- no need to highlight the highlighting
    local lines = get_range(range.start_line, range.end_line)
    M.send(lines)
end

function M.send_cell()
    local range = M.cell_range()
    highlight_range(range)

    local lines = get_range(range.start_line, range.end_line)
    M.send(lines)

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
    M.send(lines)
end

return M
