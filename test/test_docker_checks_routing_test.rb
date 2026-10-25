require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "minitest/autorun"

class DockerChecksRoutingTest < Minitest::Test
  SCRIPT = File.expand_path("../.github/scripts/docker_checks_tests_required.sh", __dir__)

  def test_documentation_only_changes_skip_tests
    refute tests_required("AGENTS.md", "README.md", "README.adoc", "docs/lessons.md")
  end

  def test_mixed_documentation_and_code_changes_run_tests
    assert tests_required("README.md", "lib/server/event_validation.rb")
  end

  def test_markdown_outside_documentation_paths_runs_tests
    assert tests_required("events_listing/about_us.md")
    assert tests_required("lib/templates/email.md")
    assert tests_required("bin/runtime-help.md")
    assert tests_required(".github/workflows/README.md")
    assert tests_required(".agents/skills/README.md")
  end

  def test_workflow_changes_and_empty_change_sets_run_tests
    assert tests_required(".github/workflows/docker_checks.yml")
    assert tests_required
  end

  def test_pr_rename_from_runtime_source_into_docs_keeps_tests_enabled
    Dir.mktmpdir do |directory|
      git!(directory, "init", "-q")
      git!(directory, "config", "user.name", "Routing Test")
      git!(directory, "config", "user.email", "routing@example.invalid")

      source_path = File.join(directory, "lib/server/event.rb")
      FileUtils.mkdir_p(File.dirname(source_path))
      File.write(source_path, "source content\n")
      git!(directory, "add", ".")
      git!(directory, "commit", "-qm", "add runtime source")
      base_sha = git_output!(directory, "rev-parse", "HEAD").strip

      destination_path = File.join(directory, "docs/event.md")
      FileUtils.mkdir_p(File.dirname(destination_path))
      FileUtils.mv(source_path, destination_path)
      git!(directory, "add", "-A")
      git!(directory, "commit", "-qm", "move runtime source into docs")

      changed_paths = git_output!(directory, "diff", "--name-only", "--no-renames", "#{base_sha}...HEAD")
        .lines.map(&:chomp).sort
      assert_equal ["docs/event.md", "lib/server/event.rb"], changed_paths
      assert tests_required(*changed_paths)
    end
  end

  def test_push_compare_rename_includes_previous_filename
    response = {
      files: [{filename: "docs/event.md", previous_filename: "lib/server/event.rb"}]
    }.to_json
    jq_filter = ".files[] | .filename, .previous_filename? | select(. != null)"
    changed_paths, status = Open3.capture2("jq", "-r", jq_filter, stdin_data: response)

    assert status.success?, "jq failed: #{changed_paths}"
    changed_paths = changed_paths.lines.map(&:chomp).sort
    assert_equal ["docs/event.md", "lib/server/event.rb"], changed_paths
    assert tests_required(*changed_paths)
  end

  private

  def tests_required(*paths)
    output, status = Open3.capture2("bash", SCRIPT, stdin_data: paths.join("\n"))
    assert status.success?, "routing helper failed: #{output}"
    output.strip == "true"
  end

  def git!(directory, *arguments)
    output, status = Open3.capture2("git", *arguments, chdir: directory)
    assert status.success?, "git #{arguments.join(" ")} failed: #{output}"
  end

  def git_output!(directory, *arguments)
    output, status = Open3.capture2("git", *arguments, chdir: directory)
    assert status.success?, "git #{arguments.join(" ")} failed: #{output}"
    output
  end
end
