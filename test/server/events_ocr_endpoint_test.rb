ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

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
    post "/events_ocr", {}
    assert_equal 401, last_response.status
  end

  def test_not_authorized
    GoogleAuthService.stub :validate_token, {success: true, email: "bad@example.com"} do
      post "/events_ocr", {google_token: "token"}
    end
    assert_equal 403, last_response.status
  end

  def test_successful_ocr
    out, _err = capture_io do
      EventOcrService.stub :call, [valid_event] do
        GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
          ImageService.stub :validate_and_process, "/tmp/test.webp" do
            post "/events_ocr", {
              google_token: "token",
              event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"),
              use_event_image: "on"
            }
          end
        end
      end
    end

    assert last_response.ok?, out
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
    assert_equal 1, app.settings.google_sheets.rows.length
    row = app.settings.google_sheets.rows.first
    assert_equal "OCR Event", row[2]
    assert_includes row[1], "+ocr@"
    assert_equal "test", row[14]
  end

  def test_ocr_without_event_image
    out, _err = capture_io do
      EventOcrService.stub :call, [valid_event] do
        GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
          ImageService.stub :validate_and_process, "/tmp/test.webp" do
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
end
