module LLMSchema
  PROBLEMATIC_FEATURES = /\(\?[=!]|\(\?<[=!]|\\[1-9]\d*|\(\?(?:R|0|\d+|\{)|\(\?#/

  # Characters that cause EBNF/grammar-parser providers (e.g. Alibaba Qwen's
  # xgrammar) to fail. These appear in pattern strings but the parser mistakenly
  # interprets them as grammar operators.
  GRAMMAR_UNSAFE_CHARS = /[|\\]/

  module_function

  # Sanitize a JSON Schema for LLM providers.
  # mode: :problematic       (default) - strip pattern with unsupported regex features
  #       :grammar            - strip pattern with grammar-unsafe chars (|) — for EBNF providers
  #       :all                - strip all pattern fields (most permissive)
  #       :none               - pass schema through unchanged
  def sanitize(schema, mode: :problematic)
    case schema
    when Hash
      schema.each_with_object({}) do |(key, value), acc|
        case key
        when "pattern" then next if drop_pattern?(value, mode)
        end
        acc[key] = sanitize(value, mode: mode)
      end
    when Array
      schema.map { |item| sanitize(item, mode: mode) }
    else
      schema
    end
  end

  def drop_pattern?(pattern, mode)
    case mode
    when :all then true
    when :none then false
    when :problematic then problematic_pattern?(pattern)
    when :grammar then grammar_unsafe_pattern?(pattern)
    else raise ArgumentError, "Unknown sanitize mode: #{mode.inspect}"
    end
  end

  def problematic_pattern?(pattern)
    pattern.to_s.match?(PROBLEMATIC_FEATURES)
  end

  def grammar_unsafe_pattern?(pattern)
    pattern.to_s.match?(GRAMMAR_UNSAFE_CHARS)
  end
end
