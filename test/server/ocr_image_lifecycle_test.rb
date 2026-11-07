ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../test_helper"
require_relative "../../bin/server"
require_relative "../fixtures/memory_sheets"

class OcrImageLifecycleTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    TestHelper.setup_network_blocking
    @settings = [app.settings.environment, app.settings.google_sheets]
    app.set :environment, :test
    app.set :google_sheets, MemorySheets.new
    @paths = []
    @source = File.expand_path("../fixtures/ocr_events.png", __dir__)
    @original_key = RubyLLM.config.gemini_api_key
    RubyLLM.config.gemini_api_key = "offline-test-key"
  end

  def teardown
    @paths.each { |path| File.unlink(path) if File.exist?(path) }
    app.set :environment, @settings[0]
    app.set :google_sheets, @settings[1]
    RubyLLM.config.gemini_api_key = @original_key
    TestHelper.reset_network_mocks
  end

  def event(day = "21", name = "Concerto")
    {name: name, start_date: "#{day}/11/2026", location: "Centro Cultural", description: "Concerto com entrada gratuita.", category: "Música", organizer: "Associação Cultural"}
  end

  def submit(events: [event], error: nil, use_image: true, method: :api_bearer, provider: false)
    process = ImageService.method(:validate_and_process)
    analyze = EventOcrService.method(:call)
    @output, = capture_io do
      ImageService.stub :validate_and_process, ->(upload) {
        path = process.call(upload)
        @paths << path
        path
      } do
        EventOcrService.stub :call, ->(path, **options) {
          assert File.file?(path), "OCR must receive an existing processed image"
          raise error if error

          provider ? analyze.call(path, **options) : events
        } do
          AuthRegistry.stub :authenticate, {authenticated: true, email: "user@example.com", method: method} do
            input = {event_image: Rack::Test::UploadedFile.new(@source, "image/png")}
            input[:use_event_image] = "on" if use_image
            post "/events_ocr", input
          end
        end
      end
    end
    JSON.parse(last_response.body)
  end

  def assert_cleaned
    refute_empty @paths
    @paths.each { |path| refute File.exist?(path), "Processed image leaked: #{path}" }
    assert File.file?(@source), "The source image must not be removed"
  end

  def test_three_provider_503_retries_leave_no_processed_images
    request = stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent").to_return(
      status: 503, headers: {"Content-Type" => "application/json"},
      body: JSON.generate(error: {code: 503, message: "High demand", status: "UNAVAILABLE"})
    )
    3.times do
      body = submit(provider: true)

      assert_equal 503, last_response.status
      assert_equal "ocr_temporarily_unavailable", body["error_code"]
      assert_cleaned
    end
    assert_equal 3, @paths.uniq.length
    assert_requested request, times: 3
    assert_empty app.settings.google_sheets.rows
  end

  def test_rate_limit_removes_image_without_changing_retry_contract
    body = submit(error: RubyLLM::RateLimitError.new("Quota exceeded"))

    assert_equal 429, last_response.status
    assert_equal true, body["retry_safe"]
    assert_cleaned
    assert_empty app.settings.google_sheets.rows
  end

  def test_timeouts_remove_images_for_both_authentication_policies
    {api_bearer: 503, google_oauth: 422}.each do |method, status|
      submit(error: Faraday::TimeoutError.new("Timed out"), method: method)

      assert_equal status, last_response.status
      assert_cleaned
    end
    assert_empty app.settings.google_sheets.rows
  end

  def test_unexpected_analysis_failure_removes_image
    submit(error: RuntimeError.new("Invalid model output"))

    assert_equal 422, last_response.status
    assert_cleaned
  end

  def test_invalid_analysis_result_removes_image
    submit(events: {unexpected: "object"})

    assert_equal 422, last_response.status
    assert_cleaned
  end

  def test_empty_analysis_removes_unused_image
    submit(events: [])

    assert_equal 200, last_response.status
    assert_cleaned
    assert_empty app.settings.google_sheets.rows
  end

  def test_completed_batch_and_duplicate_replay_remove_their_own_images
    submit(events: [event, event("22")])
    assert_equal 200, last_response.status
    assert_cleaned

    body = submit(events: [event, event("22")])
    assert_equal "skipped", body["outcome"]
    assert_cleaned
    assert_equal 2, app.settings.google_sheets.rows.length
  end

  def test_conflicts_without_flyer_remove_image
    submit
    body = submit(events: [event("21", "Outro título")], use_image: false)

    assert_equal 409, last_response.status
    refute body.key?("image_ref")
    assert_cleaned
  end

  def test_partial_failure_without_flyer_removes_image
    app.settings.google_sheets.append_failure_after = 1
    body = submit(events: [event, event("22"), event("23")], use_image: false)

    assert_equal 503, last_response.status
    assert_equal "ingestion_failed", body["error_code"]
    assert_equal %w[added failed not_attempted], body["results"].map { |result| result["status"] }
    refute body.key?("image_ref")
    assert_cleaned
  end

  def test_uncertain_append_retains_image_and_does_not_advertise_safe_retry
    append = app.settings.google_sheets.method(:append_row)
    body = nil
    app.settings.google_sheets.stub :append_row, ->(*args) {
      append.call(*args)
      raise "Lost append response"
    } do
      body = submit(events: [event, event("22")])
    end

    assert_equal 503, last_response.status
    assert_equal "ingestion_failed", body["error_code"]
    refute body["retry_safe"]
    assert_equal 1, app.settings.google_sheets.rows.length
    assert_equal File.basename(@paths.last, ".webp"), body["image_ref"]
    assert File.file?(@paths.last), "An uncertain write must preserve the review image"
  end

  def test_failed_retry_does_not_remove_another_requests_review_image
    submit
    submit(events: [event("21", "Outro título")])
    assert_equal 409, last_response.status
    review_path = @paths.last
    assert File.file?(review_path)

    submit(error: RubyLLM::ServiceUnavailableError.new("Unavailable"))

    assert_equal 503, last_response.status
    refute File.exist?(@paths.last)
    assert File.file?(review_path), "Cleanup must affect only the current request's image"
  end

  def test_already_removed_image_does_not_change_the_ingestion_result
    append = app.settings.google_sheets.method(:append_row)
    app.settings.google_sheets.stub :append_row, ->(*args) {
      File.unlink(@paths.last)
      append.call(*args)
    } do
      submit(use_image: false)
    end

    assert_equal 200, last_response.status
    assert_cleaned
    assert_equal 1, app.settings.google_sheets.rows.length
    refute_includes @output, "Failed to remove processed image"
  end

  def test_cleanup_failure_is_logged_without_turning_a_saved_batch_into_a_retryable_error
    File.stub :unlink, ->(*) { raise Errno::EACCES, "cleanup denied" } do
      submit
    end

    assert_equal 200, last_response.status
    assert_equal 1, app.settings.google_sheets.rows.length
    assert File.file?(@paths.last)
    assert_includes @output, "cleanup denied"
  end
end
