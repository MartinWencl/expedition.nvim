std = "luajit"
globals = { "vim" }
max_line_length = false

files["spec/**/*_spec.lua"] = {
  read_globals = {
    "describe",
    "it",
    "assert",
    "before_each",
    "after_each",
    "setup",
    "teardown",
    "pending",
    "spy",
    "stub",
    "mock",
  },
  globals = {
    "test_reset",
    "test_create_expedition",
    "test_clear_active",
    "test_reset_route",
    "_test_notifications",
  },
}

files["spec/spec_helper.lua"] = {
  globals = {
    "test_reset",
    "test_create_expedition",
    "test_clear_active",
    "test_reset_route",
    "_test_notifications",
    "vim",
  },
}

files["spec/coverage_helper.lua"] = {
  read_globals = { "dofile" },
}
