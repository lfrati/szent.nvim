local M = {}
local api = vim.api

-- Core tmux -> REPL bridge with bracketed-paste safety.
local defaults = {
    socket_name = "default",
    -- format: session:window.pane
    target_pane = ":.2",
    move_to_next_cell = true,
    cell_delimiter = [[^\s*#\s*%%]],
    repl_commands = { "python", "ipython", "ssh", "uv" },
    warn_no_repl = true,
    highlight_ns = vim.api.nvim_create_namespace("szent_highlight"),
    timeout = 200
}

local state = {
    socket_name = defaults.socket_name,
    target_pane = defaults.target_pane,
    configured = false,
    configuring = false,
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

local function detect_tmux_defaults()
    local tmux_env = vim.env.TMUX
    if not tmux_env or tmux_env == "" then
        return nil, nil
    end
    local socket = tmux_env:match("([^,]+)")
    return socket, ":."
end

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
    local command = {}
    vim.list_extend(command, tmux_base_args())
    vim.list_extend(command, args)
    if input ~= nil then
        return vim.fn.system(command, input)
    end
    return vim.fn.system(command)
end

local function ensure_configured()
    if state.target_pane ~= "" then
        state.configured = true
        return true
    end

    if state.configuring then
        return false
    end

    state.configuring = true
    local ok = M.configure()
    state.configuring = false

    if ok then
        state.configured = true
    end
    return ok
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


local function highlight_range(range)
    vim.hl.range(
        0,
        M.opts.highlight_ns,
        "Visual",
        { range.start_line, 0 },
        { range.stop_line - 1, 0 },
        { timeout = M.opts.timeout } -- auto-clear after 300 ms
    )
end

function M.get_range(start_line, end_line)
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

function M.paragraph_range()
    local start_line = vim.fn.search('^\\s*$', 'bcnW')
    local end_line = vim.fn.search('^\\s*$', 'cnW')
    end_line = (end_line == 0) and vim.fn.line('$') + 1 or end_line
    return {
        start_line = start_line,
        end_line = end_line,
    }
end

function M.setup(opts)
    local detected_socket, detected_pane = detect_tmux_defaults()
    local base = vim.deepcopy(defaults)

    if detected_socket then
        base.socket_name = detected_socket
    end

    if detected_pane and base.target_pane == "" then
        base.target_pane = detected_pane
    end

    M.opts = vim.tbl_deep_extend("force", base, opts or {})
    M.opts.repl_commands = normalize_list(M.opts.repl_commands)
    M.opts.bracketed_paste = nil
    M.opts.force_bracketed_paste_for = nil

    state.socket_name = M.opts.socket_name or ""
    state.target_pane = M.opts.target_pane or ""
    state.configured = state.target_pane ~= ""
end

function M.configure()
    local socket_input = vim.fn.input("tmux socket name or absolute path: ", state.socket_name or "")
    if socket_input == nil then
        return false
    end
    if socket_input ~= "" then
        state.socket_name = socket_input
    end

    local panes = trim(M.list_panes({ silent = true }) or "")
    if panes ~= "" then
        notify("Available tmux panes:\n" .. panes, vim.log.levels.INFO)
    end

    local pane_input = vim.fn.input("tmux target pane: ", state.target_pane or "")
    if pane_input == nil then
        return false
    end
    pane_input = trim(pane_input)
    if pane_input ~= "" then
        state.target_pane = pane_input
    end
    state.configured = state.target_pane ~= ""
    return state.configured
end

function M.list_panes(opts)
    local format = "#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{window_name}#{?window_active, (active),}"
    local output = run_tmux({ "list-panes", "-a", "-F", format })

    if opts and opts.silent then
        return output
    end

    if output == "" then
        notify("No tmux panes found.", vim.log.levels.WARN)
    else
        notify(output, vim.log.levels.INFO)
    end

    return output
end

-- Main entry point: push text to tmux using load-buffer/paste-buffer.
function M.send(text)
    if not M.repl_check() or not text then
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
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_line = math.min(start_pos[2], end_pos[2])
    local end_line = math.max(start_pos[2], end_pos[2])
    if start_line == 0 or end_line == 0 then
        notify("No visual selection to send.", vim.log.levels.WARN)
        return
    end
    local lines = M.get_range(start_line, end_line)
    M.send(lines)
end

function M.send_cell()
    local range = M.cell_range()
    highlight_range(range)

    local lines = M.get_range(range.start_line, range.end_line)
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

    local lines = M.get_range(range.start_line, range.end_line)
    M.send(lines)
end

function M.repl_check()
    local cmd = current_target_command()
    if not cmd then
        notify("Could not determine command running in target tmux pane.", vim.log.levels.WARN)
        return false
    end

    local expected = M.opts.repl_commands
    if vim.tbl_isempty(expected) then
        return true
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

function M.set_target_pane(pane)
    state.target_pane = pane or ""
    M.opts.target_pane = state.target_pane
    state.configured = state.target_pane ~= ""
end

function M.set_socket_name(socket_name)
    state.socket_name = socket_name or ""
    M.opts.socket_name = state.socket_name
end

function M.get_config()
    return {
        socket_name = state.socket_name,
        target_pane = state.target_pane,
    }
end

M.setup()

return M
