# szent.nvim

A tiny Neovim bridge that sends code from your current buffer to a tmux REPL using safe bracketed paste.

## Features
- Target any tmux pane and paste via `load-buffer`/`paste-buffer -p`.
- Visual- and normal-mode motions for paragraphs or `# %%` style cells.
- Optionally checks that the target pane runs a known REPL command before sending.

## Requirements
- Neovim 0.10 or newer.
- A running tmux session with bracketed paste enabled.

## Installation
Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "lfrati/szent.nvim",
  config = function()
      local szent = require("szent")
      
      szent.setup {
        target_pane = ":.2",
        repl_commands = { "python", "ipython", "uv" },
      }
      
      vim.keymap.set("x", "<leader><leader>p", szent.send_visual, { desc = "szent: send selection", silent = true })
      vim.keymap.set("n", "<leader><leader>p", szent.send_paragraph, { desc = "szent: send paragraph", silent = true })
      vim.keymap.set("n", "<leader><leader>r", szent.send_cell, { desc = "szent: send cell and advance", silent = true })
  end
}
```

## Usage
- `:SzentConfig` prompts for a socket name and tmux pane (e.g. `:.1`).
- `:SzentListPanes` prints every tmux pane with window/pane identifiers.
- `send_visual()` sends the currently selected visual range verbatim. Helpful for arbitrary snippets.
- `send_paragraph()` expands to the surrounding block separated by blank lines, highlights it briefly, and sends it.
- `send_cell()` targets the current `# %%` style cell, highlights it, sends it, and (by default) moves the cursor to the next cell.


## Configuration
All options are optional and merge with the defaults below:

```lua
require("szent").setup({
  socket_name = "default",                 -- tmux socket (string or absolute path)
  target_pane = ":.2",                     -- tmux pane target (session:window.pane)
  move_to_next_cell = true,                -- jump to the next cell after sending
  cell_delimiter = [[^\s*#\s*%%]],         -- pattern that marks cell boundaries
  repl_commands = {},                      -- optional commands to assert before sending
  timeout = 200,                           -- highlight timeout in milliseconds
})
```
