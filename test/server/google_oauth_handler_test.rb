# frozen_string_literal: true

ENV["APP_ENV"] = "test"

require "minitest/autorun"
require_relative "../../lib/server/param_utils"

class ParamUtilsTest < Minitest::Test
  def test_fetch_reads_google_token_from_string_key
    assert_equal "token", ParamUtils.fetch({"google_token" => "token"}, :google_token)
  end

  def test_fetch_reads_google_token_from_symbol_key
    assert_equal "token", ParamUtils.fetch({google_token: "token"}, :google_token)
  end
end
