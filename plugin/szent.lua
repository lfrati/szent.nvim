-- if vim.g.loaded_szent_plugin then
--     return
-- end
-- vim.g.loaded_szent_plugin = true

local szent = require("szent")

szent.setup()

-- Expose minimal commands so users can reconfigure targets without reloading Neovim.
vim.api.nvim_create_user_command("SzentConfig", function()
    szent.configure()
end, {})

vim.api.nvim_create_user_command("SzentListPanes", function()
    szent.list_panes()
end, {})

local group = vim.api.nvim_create_augroup("SzentCmds", { clear = true })

-- Wire default keymaps when editing supported REPL-friendly languages.
vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "python" },
    callback = function(event)
        local bufnr = event.buf

        vim.keymap.set("x", "<leader><leader>p", function()
            szent.send_visual()
        end, { buffer = bufnr, desc = "szent: send selection", silent = true })

        vim.keymap.set("n", "<leader><leader>p", function()
            szent.send_paragraph()
        end, { buffer = bufnr, desc = "szent: send paragraph", silent = true })

        vim.keymap.set("n", "<leader><leader>r", function()
            szent.send_cell()
        end, { buffer = bufnr, desc = "szent: send cell and advance", silent = true })
    end,
})
