require "bundler/setup"
require "minitest/autorun"
require "json"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/llm_schema"

class TestLLMSchema < Minitest::Test
  REAL_SCHEMA_PATH = File.expand_path("../../lib/event_schema.json", __dir__)

  def test_sanitize_strips_negative_lookahead
    schema = {"type" => "string", "pattern" => "(?!foo)bar"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_strips_lookbehind
    schema = {"type" => "string", "pattern" => "(?<=foo)bar"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_strips_negative_lookbehind
    schema = {"type" => "string", "pattern" => "(?<!foo)bar"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_strips_backreference
    schema = {"type" => "string", "pattern" => "(foo)\\1"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_strips_subroutine_call
    schema = {"type" => "string", "pattern" => "(?R)"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_strips_free_form_comment
    schema = {"type" => "string", "pattern" => "(?#comment)foo"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

  def test_sanitize_recurses_into_array_of_schemas
    schema = {
      "anyOf" => [
        {"type" => "string", "pattern" => "(?<=a)b"},
        {"type" => "integer"}
      ]
    }
    expected = {
      "anyOf" => [
        {"type" => "string"},
        {"type" => "integer"}
      ]
    }
    assert_equal expected, LLMSchema.sanitize(schema)
  end

  def test_real_schema_only_strips_contact_tel_pattern
    schema = {"type" => "array", "items" => real_schema}
    original = JSON.parse(JSON.generate(schema))
    expected = JSON.parse(JSON.generate(schema))
    expected.dig("items", "properties", "contact_tel").delete("pattern")

    assert_equal expected, LLMSchema.sanitize(schema)
    assert_equal original, schema
  end

  def test_grammar_mode_strips_pipe_pattern
    schema = {"type" => "string", "pattern" => "^(|foo)$"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema, mode: :grammar))
  end

  def test_grammar_mode_strips_backslash_pattern
    schema = {"type" => "string", "pattern" => "^\\d{2}$"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema, mode: :grammar))
  end

  def test_grammar_mode_keeps_clean_pattern
    schema = {"type" => "string", "pattern" => "^[a-z]+$"}
    assert_equal schema, LLMSchema.sanitize(schema, mode: :grammar)
  end

  def test_all_mode_strips_every_pattern
    schema = {"type" => "string", "pattern" => "^[a-z]+$"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema, mode: :all))
  end

  def test_none_mode_keeps_everything
    schema = {"type" => "string", "pattern" => "(?=x)y"}
    assert_equal schema, LLMSchema.sanitize(schema, mode: :none)
  end

  def test_unknown_mode_raises
    assert_raises(ArgumentError) do
      LLMSchema.sanitize({"type" => "string", "pattern" => "^x$"}, mode: :bogus)
    end
  end

  private

  def real_schema
    JSON.parse(File.read(REAL_SCHEMA_PATH))
  end
end
