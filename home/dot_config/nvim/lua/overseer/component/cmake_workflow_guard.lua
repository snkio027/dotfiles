return {
  desc = "Keep a native CMake workflow bound to its saved project",
  params = { root = { type = "string" } },
  constructor = function(params)
    return require("config.cmake_native_workflow").guard(params.root)
  end,
}
