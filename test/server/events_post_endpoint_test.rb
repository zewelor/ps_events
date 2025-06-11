ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

class AddEventEndpointTest < Minitest::Test
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
    @original_sheets = app.settings.google_sheets
    app.settings.google_sheets = DummySheets.new
  end

  def teardown
    app.settings.google_sheets = @original_sheets
  end

  def valid_params
    {
      name: "Test Event",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Porto",
      description: "Um evento de teste valido",
      category: "Música",
      organizer: "Tester"
    }
  end

  def test_missing_google_token
    out, _err = capture_io do
      post "/add_event", {}
    end
    assert_equal 401, last_response.status
    assert_includes out, "No Google token provided"
  end

  def test_successful_event_creation
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", valid_params.merge(google_token: "token")
      end
    end
    assert last_response.ok?
    assert_equal 1, app.settings.google_sheets.rows.length
    assert_includes out, "Event successfully added"
  end

  def test_google_auth_failure
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: false, error: "Invalid token"} do
        post "/add_event", valid_params.merge(google_token: "bad")
      end
    end
    assert_equal 401, last_response.status
    assert_includes out, "Google auth failed: Invalid token"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_validation_error
    params = valid_params.merge(start_date: "01/13/2025")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "Validation failed"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_contact_email_logged_when_different
    params = valid_params.merge(contact_email: "contact@example.com")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "submit@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert last_response.ok?
    assert_equal 1, app.settings.google_sheets.rows.length
    assert_includes out, "Event submitted by submit@example.com for contact contact@example.com"
  end

  def test_invalid_contact_email
    params = valid_params.merge(contact_email: "bad-email")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "contact_email"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_invalid_event_link
    params = valid_params.merge(event_link1: "ftp://foo")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "event_link1"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_end_time_before_start_time
    params = valid_params.merge(
      start_date: "01/12/2025",
      end_date: "01/12/2025",
      start_time: "10:00",
      end_time: "09:00"
    )
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "end_time"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_invalid_price_type
    params = valid_params.merge(price_type: "Expensive")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "price_type"
    assert_equal 0, app.settings.google_sheets.rows.length
  end
end
