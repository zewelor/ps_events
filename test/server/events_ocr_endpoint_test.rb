ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../test_helper"
require_relative "../../bin/server"
require_relative "../../lib/server/auth_registry"
require_relative "../fixtures/memory_sheets"

class EventsOcrEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @orig_env = app.settings.environment
    @orig_sheets = app.settings.google_sheets
    app.settings.google_sheets = MemorySheets.new
    app.set :environment, :test
  end

  def teardown
    app.set :environment, @orig_env
    app.settings.google_sheets = @orig_sheets
  end

  def valid_event
    {
      name: "OCR Event",
      start_date: "01/12/2025",
      end_date: "01/12/2025",
      location: "Lisboa",
      description: "Descrição válida do evento de teste.",
      category: "Música",
      organizer: "Org"
    }
  end

  def test_missing_token
    AuthRegistry.stub :authenticate, {authenticated: false, error: "Authentication required"} do
      post "/events_ocr", {}
    end
    assert_equal 401, last_response.status
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_not_authorized
    AuthRegistry.stub :authenticate, {authenticated: false, error: "Email not authorized", status_code: 403} do
      post "/events_ocr", {google_token: "token"}
    end
    assert_equal 403, last_response.status
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_successful_ocr
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first
    ocr_call = nil
    out, _err = capture_io do
      EventOcrService.stub :call, lambda { |path, **options|
        ocr_call = [path, options]
        [valid_event]
      } do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: whitelisted_email, method: :google_oauth} do
            post "/events_ocr", {
              google_token: "token",
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"),
              event_text: "Entrada gratuita até às 20:00.",
              use_event_image: "on"
            }
          end
        end
      end
    end

    assert last_response.ok?, out
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
    assert_equal 1, body["events"].length
    assert_equal "OCR Event", body["events"].first["name"]
    assert_equal 1, app.settings.google_sheets.rows.length
    row = app.settings.google_sheets.rows.first
    assert_equal "OCR Event", row[2]
    assert_includes row[1], "+ocr@"
    assert_equal "test", row[14]
    assert_equal ["/tmp/test.webp", {retry_sleep: 5, additional_text: "Entrada gratuita até às 20:00."}], ocr_call
  end

  def test_ocr_rejects_additional_text_over_limit
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first

    AuthRegistry.stub :authenticate, {authenticated: true, email: whitelisted_email, method: :google_oauth} do
      post "/events_ocr", {
        google_token: "token",
        event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"),
        event_text: "a" * (EventOcrService::ADDITIONAL_TEXT_MAX_LENGTH + 1)
      }
    end

    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "5000 caracteres"
  end

  def test_ocr_without_event_image
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first
    out, _err = capture_io do
      EventOcrService.stub :call, [valid_event] do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: whitelisted_email, method: :google_oauth} do
            post "/events_ocr", {
              google_token: "token",
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")
            }
          end
        end
      end
    end

    assert last_response.ok?, out
    row = app.settings.google_sheets.rows.first
    assert_equal "", row[14]
  end

  def test_authenticated_api_submitter_does_not_require_google_token
    capture_io do
      EventOcrService.stub :call, [valid_event] do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: "api@service.test", method: :api_bearer} do
            post "/events_ocr", {
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")
            }
          end
        end
      end
    end

    assert last_response.ok?
    assert_equal 1, app.settings.google_sheets.rows.length
    assert_equal "api+ocr@service.test", app.settings.google_sheets.rows.first[1]
  end

  class UnavailableChat
    def initialize(error)
      @error = error
    end

    def with_schema(_schema)
      self
    end

    def with_thinking(**_options)
      self
    end

    def with_instructions(_instructions)
      self
    end

    def ask(*_args, **_options)
      raise @error
    end
  end

  def test_transient_ocr_errors_are_retryable_before_any_event_is_saved
    TestHelper.setup_network_blocking

    [RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError, RubyLLM::ServerError].each do |error_class|
      chat = UnavailableChat.new(error_class.new("Model temporarily unavailable"))
      capture_io do
        RubyLLM.stub :chat, chat do
          ImageService.stub :validate_and_process, "/tmp/test.webp" do
            AuthRegistry.stub :authenticate, {authenticated: true, email: "api@service.test", method: :api_bearer} do
              post "/events_ocr", {
                event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")
              }
            end
          end
        end
      end

      assert_equal 503, last_response.status, error_class.name
      body = JSON.parse(last_response.body)
      assert_equal "error", body["status"]
      assert_equal "ocr_temporarily_unavailable", body["error_code"]
      assert_equal "O serviço de análise está temporariamente indisponível. Tente novamente mais tarde.", body["message"]
      assert_empty app.settings.google_sheets.rows
    end
  ensure
    TestHelper.reset_network_mocks
  end

  def test_failure_while_saving_events_does_not_claim_ocr_can_be_retried
    capture_io do
      EventOcrService.stub :call, [valid_event] do
        app.settings.google_sheets.stub :append_row, ->(*) { raise RubyLLM::ServiceUnavailableError, "Write failed" } do
          ImageService.stub :validate_and_process, "/tmp/test.webp" do
            AuthRegistry.stub :authenticate, {authenticated: true, email: "api@service.test", method: :api_bearer} do
              post "/events_ocr", {
                event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")
              }
            end
          end
        end
      end
    end

    assert_equal 503, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_equal "ingestion_failed", body["error_code"]
    refute_equal "ocr_temporarily_unavailable", body["error_code"]
  end

  def test_rate_limit_error
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first
    _out, _err = capture_io do
      EventOcrService.stub :call, ->(*_args, **_kwargs) { raise RubyLLM::RateLimitError, "Quota exceeded" } do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: whitelisted_email, method: :google_oauth} do
            post "/events_ocr", {
              google_token: "token",
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")
            }
          end
        end
      end
    end

    assert_equal 429, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_equal "rate_limit_exceeded", body["error_code"]
    assert_includes body["message"], "Quota exceeded"
  end

  def submit_events(events)
    capture_io do
      EventOcrService.stub :call, events do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: "api@service.test", method: :api_bearer} do
            post "/events_ocr", {event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")}
          end
        end
      end
    end
    JSON.parse(last_response.body)
  end

  def test_batch_replay_and_duplicates_within_batch_add_zero_extra_rows
    first = submit_events([valid_event, valid_event])
    replay = submit_events([valid_event])

    assert_equal({"added" => 1, "skipped" => 1, "conflicted" => 0}, first["counts"])
    assert_equal({"added" => 0, "skipped" => 1, "conflicted" => 0}, replay["counts"])
    assert_equal "skipped", replay["outcome"]
    assert_equal 1, app.settings.google_sheets.rows.size
  end

  def test_partial_append_failure_reports_successes_and_retry_adds_only_missing_occurrences
    later_event = valid_event.merge(start_date: "04/12/2025", end_date: "04/12/2025")
    app.settings.google_sheets.append_failure_after = 1
    failed = submit_events([valid_event, later_event])

    assert_equal 503, last_response.status
    assert_equal 1, failed["counts"]["added"]
    assert_equal "Events!A2:S2", failed["results"].first["range"]
    assert_equal "failed", failed["results"].last["status"]

    app.settings.google_sheets.append_failure_after = nil
    retried = submit_events([valid_event, later_event])

    assert_equal 200, last_response.status
    assert_equal({"added" => 1, "skipped" => 1, "conflicted" => 0}, retried["counts"])
    assert_equal 2, app.settings.google_sheets.rows.size
  end

  def test_ocr_conflicts_are_reported_separately_from_successful_appends
    submit_events([valid_event])
    body = submit_events([
      valid_event.merge(name: "Outro título OCR", category: "Arte", location: "Outro local"),
      valid_event.merge(start_date: "04/12/2025", end_date: "04/12/2025")
    ])

    assert_equal 409, last_response.status
    assert_equal({"added" => 1, "skipped" => 0, "conflicted" => 1}, body["counts"])
    assert_equal "Events!A2:S2", body["results"].first["candidates"].first["reference"]
    assert_equal 2, app.settings.google_sheets.rows.size
  end

  def test_live_read_failure_does_not_append
    app.settings.google_sheets.read_error = "Offline"
    body = submit_events([valid_event])

    assert_equal 503, last_response.status
    assert_equal "ingestion_failed", body["error_code"]
    assert_equal 0, body["counts"]["added"]
    assert_empty app.settings.google_sheets.rows
  end
end
