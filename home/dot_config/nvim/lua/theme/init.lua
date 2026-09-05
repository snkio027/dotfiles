--- DX Semantic Color System (DX-COLOR-003)
--- Assembly entry point for Catppuccin custom_highlights.

local palette_mod = require("theme.palette")
local compose = require("theme.compose")
local c3_1 = require("theme.visual.c3_1")
local c4 = require("theme.visual.c4")

local M = {}

M.default_profile = "c3_1"

local profiles = {
  c3_1 = c3_1,
  c4 = c4,
}

---@param profile_name? unknown
---@return string profile_name
---@return table visual_profile
function M.resolve_profile(profile_name)
  local selected = profile_name == nil and M.default_profile or profile_name
  if type(selected) ~= "string" or profiles[selected] == nil then
    error(("DX-COLOR-003 visual profile %s is invalid; expected one of: c3_1, c4"):format(vim.inspect(selected)), 2)
  end
  return selected, profiles[selected]
end

---@return string profile_name
---@return table visual_profile
function M.active_profile()
  return M.resolve_profile(vim.g.dx_color_profile)
end

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local profile_name, visual = M.active_profile()
  local p = palette_mod.resolve(colors, profile_name)
  return compose.highlights(p, visual)
end

return M
