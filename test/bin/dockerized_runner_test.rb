require "bundler/setup"
require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

class DockerizedRunnerTest < Minitest::Test
  def setup
    @workspace = Dir.mktmpdir("ps-events-runner-")
    FileUtils.cp(File.expand_path("../../dockerized.sh", __dir__), @workspace)
    FileUtils.mkdir_p(File.join(@workspace, ".dev/bin"))
    FileUtils.cp(File.expand_path("../../.dev/run", __dir__), File.join(@workspace, ".dev/run"))
    %w[ruby-lsp ruby rails bundle rake gem standardrb rubocop rspec jekyll].each do |name|
      FileUtils.ln_s("../run", File.join(@workspace, ".dev/bin", name))
    end
    FileUtils.mkdir_p(File.join(@workspace, "bin"))
    @calls_path = File.join(@workspace, "calls")
    @environment = {
      "PATH" => "#{@workspace}/bin:#{ENV.fetch("PATH")}",
      "DOCKER_TEST_CALLS" => @calls_path,
      "DOCKER_TEST_MODE" => "rootless",
      "COMPOSE_FILE" => "",
      "COMPOSE_PROJECT_NAME" => "fixture-editor",
      "XDG_CACHE_HOME" => "#{@workspace}/foreign-cache",
      "DOCKER_CONTEXT" => "custom-context"
    }
    File.write(File.join(@workspace, "Gemfile.lock"), "")
    File.write(File.join(@workspace, "bin/docker"), <<~SH)
      #!/bin/bash
      printf '%s\\0' "$@" >> "$DOCKER_TEST_CALLS"
      printf '\\n' >> "$DOCKER_TEST_CALLS"
      printf '%s\\n' "$PWD" > "$DOCKER_TEST_CALLS.cwd"
      printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR" "$COMPOSE_PROJECT_NAME" \\
        "$(test -d "$DOCKER_BUNDLE_DIR" && printf yes || printf no)" \\
        "$(test -d "$DOCKER_CACHE_DIR" && printf yes || printf no)" >> "$DOCKER_TEST_CALLS.context"
      if [[ "$*" == *" config --no-env-resolution --images editor" ]]; then
        printf '%s\\n' 'fixture:dev'
      fi
      if [[ "$1" == image && "$DOCKER_TEST_MODE" == image-missing ]]; then
        exit 42
      fi
      if [[ "$1" == info ]]; then
        case "$DOCKER_TEST_MODE" in
          rootless|image-missing) printf '%s\\n' '["name=seccomp,profile=builtin","name=rootless"]' ;;
          rootful) printf '%s\\n' '["name=seccomp,profile=builtin"]' ;;
          unavailable) exit 42 ;;
        esac
      fi
    SH
    FileUtils.chmod(0o755, File.join(@workspace, "bin/docker"))
  end

  def teardown
    FileUtils.remove_entry(@workspace)
  end

  def test_rootless_runner_forwards_arguments
    _, stderr, status = run_shell('source ./dockerized.sh >/dev/null; rake test "argument with spaces"')

    assert status.success?, stderr
    assert_equal ["app", "bundle", "exec", "rake", "test", "argument with spaces"], launches.fetch(0).last(6)
  end

  def test_runner_refuses_rootful_and_unavailable_daemons
    %w[rootful unavailable].each do |mode|
      _, stderr, status = run_shell("bash ./dockerized.sh rake test", "DOCKER_TEST_MODE" => mode, "DOCKER_CONTEXT" => "rootless")

      refute status.success?, mode
      assert_includes stderr.downcase, "rootless"
      assert_empty launches
    end
  end

  def test_explicit_local_compose_does_not_bypass_guard
    _, stderr, status = run_shell("bash ./dockerized.sh ruby -v", "DOCKER_TEST_MODE" => "rootful", "COMPOSE_FILE" => "docker-compose.yml")

    refute status.success?
    assert_includes stderr.downcase, "rootless"
    assert_empty launches
  end

  def test_ci_environment_cannot_bypass_guard_for_explicit_local_compose
    _, stderr, status = run_shell("bash ./dockerized.sh compose -f docker-compose.yml up", "DOCKER_TEST_MODE" => "rootful", "COMPOSE_FILE" => "docker-compose.ci.yml")

    refute status.success?
    assert_includes stderr.downcase, "rootless"
    assert_empty launches
  end

  def test_sourced_runner_rechecks_daemon_before_each_launch
    _, stderr, status = run_shell("source ./dockerized.sh >/dev/null; rake test; export DOCKER_TEST_MODE=rootful; rake test")

    refute status.success?
    assert_includes stderr.downcase, "rootless"
    assert_equal 1, launches.size
  end

  def test_compose_entry_point_forwards_arguments_and_refuses_rootful_docker
    _, stderr, status = run_shell("bash ./dockerized.sh compose run --rm --service-ports jekyll bundle exec jekyll server")

    assert status.success?, stderr
    assert_equal ["compose", "--progress", "quiet", "run", "--rm", "--service-ports", "jekyll", "bundle", "exec", "jekyll", "server"], launches.fetch(0)

    _, stderr, status = run_shell("bash ./dockerized.sh compose up", "DOCKER_TEST_MODE" => "rootful")

    refute status.success?
    assert_includes stderr.downcase, "rootless"
    assert_empty launches
  end

  def test_editor_uses_prepared_bundle_without_app_boot_or_install
    prepare_bundle
    _, stderr, status = run_shell("bash ./dockerized.sh lsp")

    assert status.success?, stderr
    command = launches.find { |args| args.include?("run") }
    assert_includes command, "--no-deps"
    assert_includes command, "-T"
    assert_equal "editor", command.last
    refute launches.any? { |args| args.include?("build") || args.include?("up") }
  end

  def test_editor_missing_dependencies_and_image_never_start_a_container
    prepare_bundle
    _, stderr, status = run_shell("bash ./dockerized.sh lsp", "DOCKER_TEST_MODE" => "image-missing")
    refute status.success?
    assert_includes stderr, "setup"
    refute launches.any? { |args| args.include?("run") || args.include?("build") }

    FileUtils.rm(File.join(@workspace, "Gemfile.lock"))
    _, stderr, status = run_shell("bash ./dockerized.sh lsp")
    refute status.success?
    assert_includes stderr, "setup"
    assert_empty launches
  end

  def test_sourced_commands_preserve_caller_environment
    _, stderr, status = run_shell(<<~SH)
      source ./dockerized.sh >/dev/null
      cd bin
      before="$PWD:$COMPOSE_PROJECT_NAME:${DOCKER_BUNDLE_DIR-unset}"
      ruby --version
      [[ "$before" == "$PWD:$COMPOSE_PROJECT_NAME:${DOCKER_BUNDLE_DIR-unset}" ]]
    SH
    assert status.success?, stderr
    assert_equal @workspace, File.read("#{@calls_path}.cwd").strip
  end

  def test_context_uses_checkout_paths_when_home_and_xdg_cache_home_are_unset
    _, stderr, status = run_shell(
      "bash ./dockerized.sh compose ps",
      "HOME" => nil,
      "XDG_CACHE_HOME" => nil
    )

    assert status.success?, stderr
    assert_equal [bundle_dir, cache_dir, "fixture-editor", "no", "no"], context
  end

  def test_context_ignores_foreign_xdg_cache_home
    _, stderr, status = run_shell("bash ./dockerized.sh compose ps")

    assert status.success?, stderr
    assert_equal [bundle_dir, cache_dir, "fixture-editor", "no", "no"], context
    refute_path_exists File.join(@workspace, "foreign-cache")
  end

  def test_compose_maps_tool_caches_into_the_checkout_cache
    compose = YAML.safe_load_file(File.expand_path("../../docker-compose.yml", __dir__), aliases: true)
    environment = compose.fetch("services").fetch("app").fetch("environment")

    assert_equal "${DOCKER_CACHE_DIR:?Use ./dockerized.sh}", environment.fetch("XDG_CACHE_HOME")
    assert_equal "${DOCKER_CACHE_DIR:?Use ./dockerized.sh}/rubocop", environment.fetch("RUBOCOP_CACHE_ROOT")
  end

  def test_context_uses_each_captured_checkout_root_from_another_directory
    outside = Dir.mktmpdir("ps-events-outside-")
    other = Dir.mktmpdir("ps-events-worktree-")
    other_runner = File.join(other, "dockerized.sh")
    FileUtils.cp(File.expand_path("../../dockerized.sh", __dir__), other_runner)

    paths = [@workspace, other].map do |root|
      runner = File.join(root, "dockerized.sh")
      _, stderr, status = run_shell(
        "bash \"#{runner}\" compose ps",
        {"COMPOSE_PROJECT_NAME" => nil, "HOME" => nil, "XDG_CACHE_HOME" => "/tmp/foreign-cache"},
        "bash",
        outside
      )

      assert status.success?, stderr
      context
    end

    assert_equal [bundle_dir, cache_dir], paths[0][0, 2]
    assert_equal [File.join(other, ".bundle/gems"), File.join(other, ".dev/cache")], paths[1][0, 2]
    refute_equal paths[0][2], paths[1][2]
    assert_equal %w[no no], paths[0][3, 2]
    assert_equal %w[no no], paths[1][3, 2]
    refute_path_exists File.join(@workspace, ".bundle")
    refute_path_exists File.join(@workspace, ".dev/cache")
    refute_path_exists File.join(other, ".bundle")
    refute_path_exists File.join(other, ".dev/cache")
  ensure
    FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    FileUtils.remove_entry(other) if other && File.exist?(other)
  end

  def test_setup_precreates_local_bundle_and_cache_as_host_user
    _, stderr, status = run_shell("bash ./dockerized.sh setup")

    assert status.success?, stderr
    assert_equal Process.uid, File.stat(bundle_dir).uid
    assert_equal Process.uid, File.stat(cache_dir).uid
    assert_equal %w[yes yes], context[3, 2]
    assert_equal [["yes", "yes"]], File.readlines("#{@calls_path}.context", chomp: true).drop(1).map { |line| line.split("\t")[3, 2] }.uniq
    assert_includes launches.fetch(0), "build"
    assert_includes launches.fetch(1), "install"
    refute_includes launches.fetch(1), "--entrypoint"
  end

  %w[bash zsh].each do |shell|
    define_method("test_source_is_silent_idempotent_and_adds_project_bin_in_#{shell}") do
      output, stderr, status = run_shell(<<~SH, {}, shell)
        before_pwd=$PWD
        before_options=$-
        ruby() { :; }
        eval 'function bin/old { :; }'
        _dockerized_path_functions=(bin/old)
        rake() { :; }
        source ./dockerized.sh
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        source ./dockerized.sh
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        [[ "$PWD" == "$before_pwd" && "$-" == "$before_options" ]] || exit 91
        [[ "$PATH" == "$PWD/.dev/bin:"* ]] || exit 92
        typeset -f ruby >/dev/null && exit 93
        typeset -f rake >/dev/null && exit 94
        count=$(printf '%s' ":$PATH:" | tr ':' '\n' | awk -v path="$PWD/.dev/bin" '$0 == path { count++ } END { print count + 0 }')
        [[ "$count" == 1 ]] || exit 93
      SH

      assert status.success?, "#{shell}: #{stderr}"
      assert_empty output
      assert_empty stderr
      assert_empty File.read(@calls_path)
      refute_path_exists bundle_dir
      refute_path_exists cache_dir
    rescue Errno::ENOENT
      raise unless shell == "zsh"
      skip "Optional host-shell compatibility check: Zsh is not installed"
    end

    define_method("test_sourcing_another_project_replaces_project_bin_in_#{shell}") do
      other = Dir.mktmpdir("ps-events-other-")
      FileUtils.cp(File.expand_path("../../dockerized.sh", __dir__), other)
      FileUtils.mkdir_p(File.join(other, ".dev/bin"))
      FileUtils.cp(File.expand_path("../../.dev/run", __dir__), File.join(other, ".dev/run"))
      %w[ruby-lsp ruby rails bundle rake gem standardrb rubocop rspec jekyll].each do |name|
        FileUtils.ln_s("../run", File.join(other, ".dev/bin", name))
      end

      output, stderr, status = run_shell(<<~SH, {"OTHER_DOCKERIZED_RUNNER" => File.join(other, "dockerized.sh")}, shell)
        source ./dockerized.sh
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        source "$OTHER_DOCKERIZED_RUNNER"
        source ./dockerized.sh
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        [[ "$PATH" == "$PWD/.dev/bin:"* ]] || exit 91
        case ":$PATH:" in *":${OTHER_DOCKERIZED_RUNNER%/dockerized.sh}/.dev/bin:"*) exit 92 ;; esac
      SH

      assert status.success?, "#{shell}: #{stderr}"
      assert_empty output
      assert_empty stderr
      assert_empty File.read(@calls_path)
    rescue Errno::ENOENT
      raise unless shell == "zsh"
      skip "Optional host-shell compatibility check: Zsh is not installed"
    ensure
      FileUtils.remove_entry(other) if other && File.exist?(other)
    end
  end

  def test_ruby_lsp_path_command_uses_the_existing_lsp_runner
    prepare_bundle
    output, stderr, status = run_shell("source ./dockerized.sh; ruby-lsp")

    assert status.success?, stderr
    assert_equal ["compose", "--progress", "quiet", "run", "--rm", "--no-deps", "-T", "--pull", "never", "editor"], launches.last
    refute launches.any? { |args| args.include?("build") || args.include?("install") }
    assert_empty output
  end

  def test_ruby_lsp_wrapper_uses_its_project_from_a_different_directory
    prepare_bundle
    outside = Dir.mktmpdir("ps-events-outside-")
    environment = {"PATH" => "#{@workspace}/.dev/bin:#{@environment.fetch("PATH")}"}
    output, stderr, status = run_shell("ruby-lsp", environment, "bash", outside)

    assert status.success?, stderr
    assert_equal "editor", launches.last.last
    assert_equal @workspace, File.read("#{@calls_path}.cwd").strip
    assert_empty output
  ensure
    FileUtils.remove_entry(outside) if outside && File.exist?(outside)
  end

  private

  def run_shell(command, environment = {}, shell = "bash", chdir = @workspace)
    File.write(@calls_path, "")
    File.write("#{@calls_path}.context", "")
    Open3.capture3(@environment.merge(environment), shell, "-c", command, chdir: chdir)
  rescue Errno::ENOENT
    raise unless shell == "zsh"
    skip "Optional host-shell compatibility check: Zsh is not installed"
  end

  def launches
    File.readlines(@calls_path, chomp: true).map { |line| line.split("\0") }.select { |args| args.first == "compose" }
  end

  def context
    File.readlines("#{@calls_path}.context", chomp: true).last.split("\t")
  end

  def bundle_dir
    File.join(@workspace, ".bundle/gems")
  end

  def cache_dir
    File.join(@workspace, ".dev/cache")
  end

  def prepare_bundle
    FileUtils.mkdir_p(bundle_dir)
  end
end
