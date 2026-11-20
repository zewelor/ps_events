require "ruby_llm"

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

module Ocr
  module Client
    SUPPORTED_PROVIDERS = %w[openai gemini].freeze

    module_function

    def resolve_model(model)
      # Pin the first-party provider even when its credentials are missing.
      model_info = RubyLLM.models.find(model)
      raise ArgumentError, "unsupported OCR provider: #{model_info.provider}" unless SUPPORTED_PROVIDERS.include?(model_info.provider)

      model_info
    end

    def context(request_timeout:)
      RubyLLM.context do |config|
        config.request_timeout = request_timeout if request_timeout
        config.max_retries = 0
      end
    end
  end
end
