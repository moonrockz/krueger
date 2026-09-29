Feature: Git hooks directory
  The hooks script installs lefthook into the hooks directory of the git
  common directory, so hooks work in the main clone and in worktrees.

  Scenario Outline: Resolve the hooks directory
    Given git reports the common dir "<common_dir>"
    And the current directory is "<cwd>"
    Then the hooks directory is "<hooks>"

    Examples:
      | common_dir          | cwd        | hooks                     |
      | /repo/.git          | /elsewhere | /repo/.git/hooks          |
      | .git                | /repo      | /repo/.git/hooks          |
      | /main/.git          | /main/wt   | /main/.git/hooks          |
