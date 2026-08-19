ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../test_helper"
require_relative "../../bin/server"
require_relative "../../lib/server/auth_registry"

class EventsOcrEndpointTest < Minitest::Test
  include Rack::Test::Methods

  class DummySheets
    attr_reader :rows

    MockUpdates = Struct.new(:updated_range)
    MockResponse = Struct.new(:updates)

    def initialize
      @rows = []
    end

    def append_row(_id, range, data)
      @rows << data
      MockResponse.new(MockUpdates.new("#{range}!A#{@rows.size}"))
    end
  end

  def app
    Sinatra::Application
  end

  def setup
    @orig_env = app.settings.environment
    @orig_sheets = app.settings.google_sheets
    app.settings.google_sheets = DummySheets.new
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
      description: "Desc",
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

  def test_ocr_ignores_blank_additional_text
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first
    ocr_call = nil

    capture_io do
      EventOcrService.stub :call, lambda { |path, **options|
        ocr_call = [path, options]
        [valid_event]
      } do
        ImageService.stub :validate_and_process, "/tmp/test.webp" do
          AuthRegistry.stub :authenticate, {authenticated: true, email: whitelisted_email, method: :google_oauth} do
            post "/events_ocr", {
              google_token: "token",
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"),
              event_text: "  "
            }
          end
        end
      end
    end

    assert last_response.ok?
    assert_equal ["/tmp/test.webp", {retry_sleep: 5, additional_text: nil}], ocr_call
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

  def test_bearer_auth_success
    out, _err = capture_io do
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

    assert last_response.ok?, out
    row = app.settings.google_sheets.rows.first
    assert_includes row[1], "+ocr@"
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
end
