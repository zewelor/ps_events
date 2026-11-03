require "minitest/autorun"
require "tmpdir"
require "digest"
require_relative "../test_helper"
require_relative "../../lib/server/github_service"

class GitHubServiceTest < Minitest::Test
  def setup
    TestHelper.setup_network_blocking
    @previous_env = ENV.to_h.slice("GH_TOKEN", "GH_REPO")
    ENV["GH_TOKEN"] = "fixture-token"
    ENV["GH_REPO"] = "fixture/images"
    @directory = Dir.mktmpdir
    @path = File.join(@directory, "flyer.webp")
    @bytes = "processed flyer bytes".b
    File.binwrite(@path, @bytes)
    @url = "https://api.github.com/repos/fixture/images/contents/events_listing%2Fassets%2Fimages%2Fflyer.webp"
    @service = GitHubService.new(branch: "review-fixture")
  end

  def teardown
    %w[GH_TOKEN GH_REPO].each { |key| @previous_env.key?(key) ? ENV[key] = @previous_env[key] : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
    TestHelper.reset_network_mocks
  end

  def remote_file(bytes = @bytes)
    {type: "file", path: "events_listing/assets/images/flyer.webp", sha: Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0#{bytes}")}
  end

  def lookup(*responses)
    stub_request(:get, @url).with(query: {ref: "review-fixture"}).to_return(*responses)
  end

  def ensure_image
    result = nil
    capture_io { result = @service.ensure_image(@path) }
    result
  end

  def test_identical_published_image_is_reused_without_another_commit
    lookup(status: 200, body: JSON.generate(remote_file))

    assert ensure_image
    assert_not_requested :put, @url
  end

  def test_published_image_remains_reusable_after_the_temporary_file_is_gone
    File.delete(@path)
    lookup(status: 200, body: JSON.generate(remote_file))

    assert ensure_image
    assert_not_requested :put, @url
  end

  def test_unpublished_image_is_created_once_without_overwriting_an_existing_file
    lookup(status: 404)
    creation = stub_request(:put, @url).with do |request|
      body = JSON.parse(request.body)
      body["branch"] == "review-fixture" && !body.key?("sha") && Base64.strict_decode64(body["content"]) == @bytes
    end.to_return(status: 201)

    assert ensure_image
    assert_requested creation, times: 1
  end

  def test_uncertain_create_is_reconciled_against_the_identical_remote_file
    lookup({status: 404}, {status: 200, body: JSON.generate(remote_file)})
    creation = stub_request(:put, @url).to_timeout

    assert ensure_image
    assert_requested creation, times: 1
  end

  def test_missing_or_mismatched_images_and_remote_failures_prevent_publication
    [
      {status: 200, body: JSON.generate(remote_file("different image"))},
      {status: 503},
      {status: 200, body: JSON.generate(type: "dir", path: "events_listing/assets/images/flyer.webp")}
    ].each do |response|
      WebMock.reset!
      lookup(response)

      capture_io { assert_raises(RuntimeError) { @service.ensure_image(@path) } }
      assert_not_requested :put, @url
    end
    File.delete(@path)
    WebMock.reset!
    lookup(status: 404)

    capture_io { assert_raises(RuntimeError) { @service.ensure_image(@path) } }
    assert_not_requested :put, @url
  end

  def test_failed_create_without_a_matching_remote_file_is_not_reported_as_success
    lookup(status: 404)
    creation = stub_request(:put, @url).to_return(status: 422, body: "Creation failed")

    capture_io { assert_raises(RuntimeError) { @service.ensure_image(@path) } }
    assert_requested creation, times: 1
  end

  def test_a_local_symlink_is_not_published
    other_path = File.join(@directory, "other.webp")
    File.rename(@path, other_path)
    File.symlink(other_path, @path)

    capture_io { assert_raises(RuntimeError) { @service.ensure_image(@path) } }
    assert_not_requested :get, @url
    assert_not_requested :put, @url
  end
end
