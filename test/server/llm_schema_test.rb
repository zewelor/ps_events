require "bundler/setup"
require "minitest/autorun"
require "json"
require "json-schema"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/llm_schema"

class TestLLMSchema < Minitest::Test
  # ----- A. Simple patterns are kept -----

  def test_sanitize_keeps_date_pattern
    schema = {"type" => "string", "pattern" => "^\\d{2}/\\d{2}/\\d{4}$"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_keeps_time_pattern
    schema = {"type" => "string", "pattern" => "^(|\\d{2}:\\d{2})$"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_keeps_url_pattern
    schema = {"type" => "string", "pattern" => "^(|https?://.+)$"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_keeps_simple_email_pattern
    schema = {"type" => "string", "pattern" => "^[\\w.+-]+@[\\w.-]+$"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_keeps_empty_alternation
    schema = {"type" => "string", "pattern" => "^(|foo|bar)$"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  # ----- B. Problematic patterns are stripped -----

  def test_sanitize_strips_lookahead
    schema = {"type" => "string", "pattern" => "(?=foo)bar"}
    assert_equal({"type" => "string"}, LLMSchema.sanitize(schema))
  end

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

  def test_sanitize_strips_complex_lookahead_in_anchored_pattern
    schema = {"type" => "string", "pattern" => "^(|(?=(?:.*\\d){7,})[\\d\\s\\-\\(\\)\\+]+)$"}
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

  # ----- C. Other schema fields are untouched -----

  def test_sanitize_preserves_enum
    schema = {"type" => "string", "enum" => %w[Gratuito Pago Desconhecido]}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_min_max_length
    schema = {"type" => "string", "minLength" => 3, "maxLength" => 200}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_required
    schema = {"type" => "object", "required" => %w[name start_date]}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_description
    schema = {"type" => "string", "description" => "Field docs"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_type
    schema = {"type" => "string"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_additional_properties
    schema = {"type" => "object", "additionalProperties" => false}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_format
    schema = {"type" => "string", "format" => "date-time"}
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  def test_sanitize_preserves_properties_keys
    schema = {
      "type" => "object",
      "properties" => {
        "name" => {"type" => "string", "minLength" => 3},
        "category" => {"type" => "string", "enum" => %w[Music Food]}
      }
    }
    assert_equal schema, LLMSchema.sanitize(schema)
  end

  # ----- D. Recursion -----

  def test_sanitize_recurses_into_nested_properties
    schema = {
      "type" => "object",
      "properties" => {
        "outer" => {
          "type" => "object",
          "properties" => {
            "inner" => {"type" => "string", "pattern" => "(?=foo)bar"}
          }
        }
      }
    }
    expected = {
      "type" => "object",
      "properties" => {
        "outer" => {
          "type" => "object",
          "properties" => {
            "inner" => {"type" => "string"}
          }
        }
      }
    }
    assert_equal expected, LLMSchema.sanitize(schema)
  end

  def test_sanitize_recurses_into_array_items
    schema = {
      "type" => "array",
      "items" => {"type" => "string", "pattern" => "(?=x)y"}
    }
    expected = {
      "type" => "array",
      "items" => {"type" => "string"}
    }
    assert_equal expected, LLMSchema.sanitize(schema)
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

  def test_sanitize_handles_deeply_nested_schema
    schema = {
      "type" => "object",
      "properties" => {
        "a" => {
          "type" => "object",
          "properties" => {
            "b" => {
              "type" => "object",
              "properties" => {
                "c" => {
                  "type" => "object",
                  "properties" => {
                    "d" => {"type" => "string", "pattern" => "(?!x)y"}
                  }
                }
              }
            }
          }
        }
      }
    }
    sanitized = LLMSchema.sanitize(schema)
    assert_nil sanitized.dig("properties", "a", "properties", "b", "properties", "c", "properties", "d", "pattern")
  end

  # ----- E. Non-mutation -----

  def test_sanitize_does_not_mutate_input_hash
    schema = {"type" => "string", "pattern" => "(?=x)y"}
    original = Marshal.load(Marshal.dump(schema))
    LLMSchema.sanitize(schema)
    assert_equal original, schema
  end

  def test_sanitize_does_not_mutate_input_array
    schema = [{"type" => "string", "pattern" => "(?=x)y"}]
    original = Marshal.load(Marshal.dump(schema))
    LLMSchema.sanitize(schema)
    assert_equal original, schema
  end

  def test_sanitize_does_not_mutate_nested_values
    inner = {"type" => "string", "pattern" => "(?=x)y"}
    schema = {"properties" => {"x" => inner}}
    original_inner_pattern = inner["pattern"]
    LLMSchema.sanitize(schema)
    assert_equal original_inner_pattern, inner["pattern"]
  end

  def test_sanitize_produces_independent_copy
    schema = {"type" => "string", "pattern" => "(?=x)y"}
    sanitized = LLMSchema.sanitize(schema)
    sanitized["type"] = "integer"
    assert_equal "string", schema["type"]
  end

  # ----- F. Edge cases for value types -----

  def test_sanitize_passes_through_string_unchanged
    assert_equal "hello", LLMSchema.sanitize("hello")
  end

  def test_sanitize_passes_through_integer_unchanged
    assert_equal 42, LLMSchema.sanitize(42)
  end

  def test_sanitize_passes_through_boolean_unchanged
    assert_equal true, LLMSchema.sanitize(true)
    assert_equal false, LLMSchema.sanitize(false)
  end

  def test_sanitize_passes_through_nil_unchanged
    assert_nil LLMSchema.sanitize(nil)
  end

  def test_sanitize_handles_empty_hash
    assert_equal({}, LLMSchema.sanitize({}))
  end

  def test_sanitize_handles_empty_array
    assert_equal([], LLMSchema.sanitize([]))
  end

  def test_sanitize_handles_nil_pattern_value
    schema = {"type" => "string", "pattern" => nil}
    sanitized = LLMSchema.sanitize(schema)
    assert_equal schema, sanitized
  end

  def test_sanitize_handles_non_string_pattern
    schema = {"type" => "string", "pattern" => 42}
    sanitized = LLMSchema.sanitize(schema)
    assert_equal schema, sanitized
  end

  # ----- G. Integration: against the real event_schema.json -----

  REAL_SCHEMA_PATH = File.expand_path("../../lib/event_schema.json", __dir__)

  def real_schema
    JSON.parse(File.read(REAL_SCHEMA_PATH))
  end

  def test_real_schema_has_no_problematic_patterns_left
    sanitized = LLMSchema.sanitize(real_schema)
    patterns = collect_patterns(sanitized)
    problematic = patterns.select { |p| LLMSchema.problematic_pattern?(p) }
    assert_empty problematic, "Sanitized schema still has problematic patterns: #{problematic.inspect}"
  end

  def test_real_schema_preserves_simple_patterns
    sanitized = LLMSchema.sanitize(real_schema)
    start_date = sanitized["properties"]["start_date"]
    assert_equal "^\\d{2}/\\d{2}/\\d{4}$", start_date["pattern"]
  end

  def test_real_schema_field_count_unchanged
    schema = real_schema
    assert_equal schema["properties"].keys.sort, LLMSchema.sanitize(schema)["properties"].keys.sort
  end

  def test_real_schema_only_strips_contact_tel_pattern
    schema = real_schema
    sanitized = LLMSchema.sanitize(schema)
    assert_nil sanitized["properties"]["contact_tel"]["pattern"]
    %w[start_date start_time end_date end_time contact_email event_link1 event_link2 event_link3 event_link4].each do |field|
      original = schema["properties"][field]["pattern"]
      next if original.nil?
      assert_equal original, sanitized["properties"][field]["pattern"], "Pattern for #{field} should be preserved"
    end
  end

  def test_real_schema_can_be_consumed_by_json_validator
    sanitized = LLMSchema.sanitize(real_schema)
    result = JSON::Validator.fully_validate(sanitized, {"name" => "X"}, errors_as_objects: true)
    assert_kind_of Array, result
  end

  def test_real_schema_is_parseable_json_after_sanitize
    sanitized = LLMSchema.sanitize(real_schema)
    assert_kind_of Hash, JSON.parse(JSON.generate(sanitized))
  end

  # ----- H. Sanitize modes -----

  def test_problematic_mode_keeps_simple_pattern
    schema = {"type" => "string", "pattern" => "^\\d{2}/\\d{2}/\\d{4}$"}
    assert_equal schema, LLMSchema.sanitize(schema, mode: :problematic)
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

  def collect_patterns(node, acc = [])
    case node
    when Hash
      acc << node["pattern"] if node.key?("pattern")
      node.each_value { |v| collect_patterns(v, acc) }
    when Array
      node.each { |v| collect_patterns(v, acc) }
    end
    acc
  end
end
