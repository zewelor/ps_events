require "bundler/setup"
require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class DockerizedRunnerTest < Minitest::Test
  def setup
    @workspace = Dir.mktmpdir("ps-events-runner-")
    FileUtils.cp(File.expand_path("../../dockerized.sh", __dir__), @workspace)
    FileUtils.mkdir_p(File.join(@workspace, "bin"))
    @calls_path = File.join(@workspace, "calls")
    @environment = {
      "PATH" => "#{@workspace}/bin:#{ENV.fetch("PATH")}",
      "DOCKER_TEST_CALLS" => @calls_path,
      "DOCKER_TEST_MODE" => "rootless",
      "COMPOSE_FILE" => "",
      "DOCKER_CONTEXT" => "custom-context"
    }
    File.write(File.join(@workspace, "bin/docker"), <<~SH)
      #!/bin/bash
      printf '%s\\0' "$@" >> "$DOCKER_TEST_CALLS"
      printf '\\n' >> "$DOCKER_TEST_CALLS"
      if [[ "$1" == info ]]; then
        case "$DOCKER_TEST_MODE" in
          rootless) printf '%s\\n' '["name=seccomp,profile=builtin","name=rootless"]' ;;
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

  private

  def run_shell(command, environment = {})
    File.write(@calls_path, "")
    Open3.capture3(@environment.merge(environment), "bash", "-c", command, chdir: @workspace)
  end

  def launches
    File.readlines(@calls_path, chomp: true).map { |line| line.split("\0") }.select { |args| args.first == "compose" }
  end
end
