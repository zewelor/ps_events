ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require_relative "../../bin/server"

class HealthEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_health_endpoint
    get "/health"
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
  end

  def test_health_endpoint_diagnostics_flag
    old = ENV["HEALTH_DIAGNOSTICS"]
    ENV["HEALTH_DIAGNOSTICS"] = "1"

    get "/health"
    assert last_response.ok?
    body = JSON.parse(last_response.body)

    # Should remain minimal in test env to avoid leaking details into CI logs.
    refute body.key?("auth_methods"), body.inspect
  ensure
    ENV["HEALTH_DIAGNOSTICS"] = old
  end
end
