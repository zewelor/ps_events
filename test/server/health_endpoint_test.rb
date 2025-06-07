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
end
