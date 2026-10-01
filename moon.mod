name = "moonrockz/krueger"

version = "0.2.0"

import {
  "moonrockz/expect@0.6.0",
}

readme = "README.mbt.md"

repository = "https://github.com/moonrockz/krueger"

license = "Apache-2.0"

keywords = [ "elm", "elm-like", "morphir", "parser", "scanner", "ast" ]

description = "Parser and parsing utilities for Elm and Elm-like dialects (e.g. Morphir) in MoonBit"

source = "src"

warnings = "-implicit_impl_as_method"

options(
  exclude: [
    "harness",
    "tests",
    "docs",
    "scripts",
    "mise-tasks",
    "tools",
    ".github",
    ".beads",
    "moon.work",
    "CLAUDE.md",
    "lefthook.yml",
  ],
)
