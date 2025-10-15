-- lua/szent/health.lua
local M = {}
local health = vim.health
local szent = require("szent")

local function detect_tmux_socket()
    local tmux_env = vim.env.TMUX
    if not tmux_env or tmux_env == "" then
        return nil
    end
    return tmux_env:match("([^,]+)")
end

local function run_tmux(args)
    local command = { "tmux" }
    local socket = detect_tmux_socket()
    if socket and socket ~= "" then
        if socket:sub(1, 1) == "/" then
            table.insert(command, "-S")
        else
            table.insert(command, "-L")
        end
        table.insert(command, socket)
    end
    vim.list_extend(command, args)
    local output = vim.fn.system(command)
    return vim.v.shell_error, output
end

function M.check()
    health.start("szent.nvim")

    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim >= 0.10 detected")
    else
        health.error("szent.nvim requires Neovim 0.10 or newer")
    end

    if vim.fn.executable("tmux") == 1 then
        health.ok("tmux executable found in PATH")
    else
        health.error("tmux not found in PATH")
    end

    if vim.env.TMUX and vim.env.TMUX ~= "" then
        health.ok("Running inside a tmux session")
    else
        health.warn("Not inside tmux; send commands will no-op")
    end

    local target = szent.opts.target_pane or ""
    if target == "" then
        health.warn("No target pane configured; run :SzentConfig")
    else
        local code = run_tmux({ "has-session", "-t", target })
        if code == 0 then
            health.ok(("Target pane '%s' is available"):format(target))
        else
            health.error(("Target pane '%s' is not reachable"):format(target))
        end
    end

    if vim.tbl_isempty(szent.opts.repl_commands or {}) then
        health.info("No REPL command guard configured (optional)")
    else
        health.ok("REPL command guard enabled: " .. table.concat(szent.opts.repl_commands, ", "))
    end
end

return M
