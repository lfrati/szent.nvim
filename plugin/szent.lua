if vim.g.loaded_szent_plugin then
    return
end
vim.g.loaded_szent_plugin = true

local szent = require("szent")

-- Expose minimal commands so users can reconfigure targets without reloading Neovim.
vim.api.nvim_create_user_command("SzentConfig", function()
    szent.configure()
end, {})