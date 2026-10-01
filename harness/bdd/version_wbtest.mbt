///|
async test "version() equals the version in moon.mod" {
  let moon_mod = @fs.read_file_to_string(repo_path("moon.mod"))
  @expect.expect(moon_mod).to_contain("version = \"\{@krueger.version()}\"")
}
