ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

class EventsOcrEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @orig_env = app.settings.environment
    app.set :environment, :test
  end

  def teardown
    app.set :environment, @orig_env
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
      "csv"
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
    assert_equal '"csv"', body["text"]
  end
end
