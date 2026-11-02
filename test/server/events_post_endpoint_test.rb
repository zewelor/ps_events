ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../test_helper"
require_relative "../../bin/server"
require_relative "../fixtures/memory_sheets"

class AddEventEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @original_sheets = app.settings.google_sheets
    app.settings.google_sheets = MemorySheets.new
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
    capture_io do
      post "/add_event", {}
    end
    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "Google authentication is required"
  end

  def test_successful_event_creation
    whitelisted_email = SecurityService::WHITELISTED_EMAILS.first
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: whitelisted_email} do
        post "/add_event", valid_params.merge(google_token: "token", contact_email: "contact@example.com")
      end
    end
    assert last_response.ok?
    assert_equal 1, app.settings.google_sheets.rows.length
    row = app.settings.google_sheets.rows.first
    assert_equal whitelisted_email, row[1]
    assert_equal "contact@example.com", row[11]
  end

  def test_non_whitelisted_email_rejected
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
        post "/add_event", valid_params.merge(google_token: "token")
      end
    end
    assert_equal 403, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "Email not authorized"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_google_auth_failure
    capture_io do
      GoogleAuthService.stub :validate_token, {success: false, error: "Invalid token"} do
        post "/add_event", valid_params.merge(google_token: "bad")
      end
    end
    assert_equal 401, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "Google authentication failed"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_validation_error
    params = valid_params.merge(start_date: "01/13/2025")
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes out, "Validation failed"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_invalid_contact_email
    params = valid_params.merge(contact_email: "bad-email")
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "contact_email"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_invalid_event_link
    params = valid_params.merge(event_link1: "ftp://foo")
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "event_link1"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_end_time_before_start_time
    params = valid_params.merge(
      start_date: "01/12/2025",
      end_date: "01/12/2025",
      start_time: "10:00",
      end_time: "09:00"
    )
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "end_time"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_invalid_price_type
    params = valid_params.merge(price_type: "Expensive")
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["message"], "price_type"
    assert_equal 0, app.settings.google_sheets.rows.length
  end

  def test_iso_formatted_dates_are_converted
    params = valid_params.merge(
      start_date: "2025-12-01",
      end_date: "2025-12-02"
    )
    out, _err = capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end
    assert last_response.ok?, out
    row = app.settings.google_sheets.rows.first
    assert_equal "01/12/2025", row[3]
    assert_equal "02/12/2025", row[5]
  end

  def test_single_digit_dates_are_accepted_and_preserved
    params = valid_params.merge(start_date: "1/2/2026", end_date: "2/2/2026")
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", params.merge(google_token: "token")
      end
    end

    assert last_response.ok?
    assert_equal ["1/2/2026", "2/2/2026"], app.settings.google_sheets.rows.first.values_at(3, 5)
  end

  def submit_event(event = valid_params)
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", event.merge(google_token: "token")
      end
    end
    JSON.parse(last_response.body)
  end

  def test_replaying_form_is_a_friendly_success_without_another_row
    submit_event
    body = submit_event

    assert_equal 200, last_response.status
    assert_equal "skipped", body["outcome"]
    assert_includes body["message"], "já se encontra registado"
    assert_equal 1, app.settings.google_sheets.rows.length
  end

  def test_form_conflict_can_be_explicitly_resolved_as_a_distinct_occurrence
    submit_event
    body = submit_event(valid_params.merge(location: "Outro local"))

    assert_equal 409, last_response.status
    assert_equal "needs_review", body["status"]
    assert_equal 1, app.settings.google_sheets.rows.length

    fingerprints = body["results"].first["candidates"].map { |candidate| candidate["fingerprint"] }
    resolved = submit_event(valid_params.merge(location: "Outro local", distinct_from: JSON.generate(fingerprints)))

    assert_equal 200, last_response.status
    assert_equal "added", resolved["outcome"]
    assert_equal 2, app.settings.google_sheets.rows.length
  end

  def test_invalid_distinct_acknowledgement_is_rejected
    submit_event(valid_params.merge(distinct_from: "true"))

    assert_equal 422, last_response.status
    assert_empty app.settings.google_sheets.rows
  end
end
