local M = {}

-- DAP evaluates a callable configuration before resolving its fields. Capture
-- the editing project once, before the executable prompt can change focus.
function M.launch()
  return setmetatable({
    type = "codelldb",
    request = "launch",
    name = "Launch Zig executable",
    stopOnEntry = false,
  }, {
    __call = function(config)
      local root = LazyVim.root()
      local program = vim.fn.input("Path to executable: ", vim.fs.joinpath(root, "zig-out/bin/"), "file")
      local resolved = vim.deepcopy(config)
      setmetatable(resolved, nil)
      resolved.cwd = root
      if program == "" then
        resolved.program = require("dap").ABORT
      else
        program = vim.fn.expand(program)
        resolved.program = vim.fs.abspath(vim.fs.joinpath(root, program))
        if program:sub(1, 1) == "/" then
          resolved.program = vim.fs.normalize(program)
        end
      end
      return resolved
    end,
  })
end

return M
