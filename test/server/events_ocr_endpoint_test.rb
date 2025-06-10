ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

class EventsOcrEndpointTest < Minitest::Test
  include Rack::Test::Methods

  class DummySheets
    attr_reader :rows

    def initialize
      @rows = []
    end

    def append_row(_spreadsheet_id, _range, data)
      @rows << data
    end
  end

  def app
    Sinatra::Application
  end

  def setup
    @orig_env = app.settings.environment
    @orig_sheets = app.settings.google_sheets
    app.set :environment, :test
    app.settings.google_sheets = DummySheets.new
  end

  def teardown
    app.set :environment, @orig_env
    app.settings.google_sheets = @orig_sheets
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
    mock = Object.new
    def mock.analyze(_path)
      '[{"name":"Test","description":"Uma descricao valida","location":"Porto","organizer":"Org","start_date":"01/12/2025","start_time":"","end_date":"02/12/2025","end_time":"","category":"Música","price_type":"Gratuito"}]'
    end

    EventOcrService.stub :new, mock do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        ImageService.stub :validate_upload, nil do
          ImageService.stub :process_upload, "/tmp/test.webp" do
            post "/events_ocr", {google_token: "token", event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")}
          end
        end
      end
    end
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
    assert_equal 1, app.settings.google_sheets.rows.length
  end
end
