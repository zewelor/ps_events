ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

class EventImageEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @original_env = app.settings.environment
    app.set :environment, :test
  end

  def teardown
    app.set :environment, @original_env
  end

  def test_missing_token
    post "/event_image", {}
    assert_equal 401, last_response.status
  end

  def test_not_authorized
    GoogleAuthService.stub :validate_token, {success: true, email: "bad@example.com"} do
      post "/event_image", {google_token: "token"}
    end
    assert_equal 403, last_response.status
  end

  def test_successful_upload
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "admin@example.com"} do
        ImageService.stub :validate_upload, nil do
          ImageService.stub :process_upload, "/tmp/test.webp" do
            post "/event_image", {google_token: "token", event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")}
          end
        end
      end
    end
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
    assert_equal "test", body["filename"]
    assert_includes out, "Image processed successfully"
  end
end
