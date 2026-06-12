require "bundler/setup"
require "minitest/autorun"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/event_ocr_service"

class TestEventOcrPrompt < Minitest::Test
  INSTRUCTIONS = EventOcrService.build_instructions

  def test_returns_non_empty_string
    assert_kind_of String, INSTRUCTIONS
    refute_empty INSTRUCTIONS
  end

  def test_contains_current_year
    assert_includes INSTRUCTIONS, Time.now.year.to_s
  end

  def test_instructs_to_skip_porto_santo_in_location
    assert_includes INSTRUCTIONS, "Porto Santo"
    assert_match(/skip.*Porto Santo/i, INSTRUCTIONS)
  end

  def test_mentions_json_output_format
    assert_includes INSTRUCTIONS, "JSON"
  end

  def test_mentions_european_portuguese
    assert_includes INSTRUCTIONS, "Portuguese"
  end

  def test_mentions_europe_lisbon_timezone
    assert_includes INSTRUCTIONS, "Europe/Lisbon"
  end

  def test_directs_single_event_when_same_day_and_location
    assert_match(/same day AND same place/i, INSTRUCTIONS)
  end

  def test_defines_price_type_fallback
    assert_includes INSTRUCTIONS, "Desconhecido"
  end

  def test_instructs_to_use_only_image_information
    assert_match(/do not make assumptions/i, INSTRUCTIONS)
  end
end
