local Tmux = {}
Tmux.__index = Tmux

---@param str string
local function trim(str)
    if not str then
        return ""
    end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param cmd string
---@param patterns string[]
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

function Tmux.detect_tmux_socket()
    local tmux_env = vim.env.TMUX
    if not tmux_env or tmux_env == "" then
        return nil
    end
    return tmux_env:match("([^,]+)")
end

---@param opts table
function Tmux.new(opts)
    opts = opts or {}
    local instance = {
        socket_name = trim(opts.socket_name or Tmux.detect_tmux_socket() or ""),
        target_pane = trim(opts.target_pane or ""),
        repl_commands = opts.repl_commands or {},
        notify = opts.notify,
    }
    return setmetatable(instance, Tmux)
end

---@param fn function
function Tmux:set_notify(fn)
    self.notify = fn
end

---@param commands string[]
function Tmux:set_repl_commands(commands)
    self.repl_commands = commands or {}
end

function Tmux:_notify(msg, level)
    if self.notify then
        self.notify(msg, level)
    else
        vim.notify(
            msg,
            level or vim.log.levels.INFO,
            { title = "szent" }
        )
    end
end

---@param pane string
function Tmux:set_socket_name(socket)
    self.socket_name = trim(socket or "")
end

---@param pane string
function Tmux:set_target_pane(pane)
    self.target_pane = trim(pane or "")
end

function Tmux:get_target_pane()
    return self.target_pane
end

function Tmux:inside()
    return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

function Tmux:ensure()
    if self:inside() then
        return true
    end
    self:_notify("Not running inside tmux; launch Neovim from a tmux pane.", vim.log.levels.WARN)
    return false
end

function Tmux:base_args()
    local socket = trim(self.socket_name or "")
    if socket == "" then
        return { "tmux" }
    end
    if socket:sub(1, 1) == "/" then
        return { "tmux", "-S", socket }
    end
    return { "tmux", "-L", socket }
end

---@param args string[]
---@param input string|nil
function Tmux:run_tmux(args, input)
    if not self:inside() then
        return ""
    end
    local command = self:base_args()
    vim.list_extend(command, args)
    if input ~= nil then
        return vim.fn.system(command, input)
    end
    return vim.fn.system(command)
end

function Tmux:current_target_command()
    if self.target_pane == "" then
        return nil
    end
    local output = self:run_tmux({
        "display-message",
        "-p",
        "-t",
        self.target_pane,
        "#{pane_current_command}",
    })
    output = trim(output)
    if output == "" then
        return nil
    end
    return output
end

function Tmux:target_pane_exists()
    if not self:ensure() then
        return false
    end
    if not self.target_pane or self.target_pane == "" then
        return false
    end

    self:run_tmux({ "has-session", "-t", self.target_pane })
    if vim.v.shell_error ~= 0 then
        return false
    end

    return true
end

function Tmux:ensure_target_ready()
    if not self:ensure() then
        return false
    end

    if not self.target_pane or self.target_pane == "" then
        self:_notify("No tmux pane configured; run :SzentConfig.", vim.log.levels.WARN)
        return false
    end

    if not self:target_pane_exists() then
        self:_notify(("Target pane [%s] not found; run :SzentConfig."):format(self.target_pane), vim.log.levels.WARN)
        return false
    end

    if not self.repl_commands or vim.tbl_isempty(self.repl_commands) then
        return true
    end

    local cmd = self:current_target_command()
    if not cmd then
        self:_notify("Could not determine command running in target tmux pane.", vim.log.levels.WARN)
        return false
    end

    if matches_any_command(cmd, self.repl_commands) then
        return true
    end

    self:_notify(
        string.format(
            "Target tmux pane %s is running '%s', expected one of: %s",
            self.target_pane or "",
            cmd,
            table.concat(self.repl_commands, ", ")
        ),
        vim.log.levels.WARN
    )

    return false
end

function Tmux:list_panes()
    if not self:ensure() then
        return nil
    end
    local format = "#{pane_index}) #{pane_current_command}#{?pane_active, *,}\tid:[#{pane_id}]"
    local args = { "list-panes", "-F", format }
    local output = self:run_tmux(args)

    if vim.v.shell_error ~= 0 then
        self:_notify(("tmux error: %s"):format(trim(output)), vim.log.levels.ERROR)
        return nil
    end

    if trim(output) == "" then
        self:_notify("No tmux panes found.", vim.log.levels.WARN)
        return nil
    end

    return output
end

---@param text string
function Tmux:send(text)
    if not text or not self:ensure_target_ready() or type(text) ~= "string" or text == "" then
        return
    end

    self:run_tmux({ "send-keys", "-X", "-t", self.target_pane, "cancel" })
    self:run_tmux({ "load-buffer", "-" }, text)
    self:run_tmux({ "paste-buffer", "-d", "-p", "-t", self.target_pane })
end

function Tmux:press(key)
    if not key or not self:ensure_target_ready() or type(key) ~= "string" or key == "" then
        return
    end
    
    self:run_tmux({ "send-keys", "-t", self.target_pane, key })
end

return Tmux
