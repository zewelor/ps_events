require "digest"
require "fileutils"
require "json"
require "json-schema"
require "ruby_llm"
require "stringio"
require_relative "../event_ocr_service"
require_relative "admission"
require_relative "prompts"
require_relative "schemas"

module Ocr
  class SourceWorkflow
    def self.call(path, **options)
      analyze_options = options.slice(:additional_text, :fallback_year, :artifact_dir)
      new(**options.except(:additional_text, :fallback_year, :artifact_dir)).analyze(path, **analyze_options)
    end

    def initialize(model: ENV.fetch("OCR_MODEL", EventOcrService::MODEL), reasoning_effort: ENV["OCR_REASONING_EFFORT"] || EventOcrService::REASONING_EFFORT, llm_recovery: :none, request_timeout: 180)
      raise ArgumentError, "source workflow does not support retries" unless llm_recovery == :none

      @model = EventOcrService.resolve_model(model)
      @effort = reasoning_effort.to_sym
      @request_timeout = request_timeout
    end

    def run_evidence
      costs = @calls.map { |call| RubyLLM::Cost.from_h(call.fetch(:cost)) }
      {
        stage: @stage, image_detail: "original", models: {reader: @model.id, reader_effort: @effort.to_s},
        hashes: @hashes, calls: @calls,
        timing: {total_seconds: (clock - @started).round(4), stages: @timings},
        usage_totals: %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].to_h { |key| [key, @calls.sum { |call| call.dig(:tokens, key).to_i }] },
        cost_totals: RubyLLM::Cost.aggregate(costs, complete: costs.all? { |cost| !cost.total.nil? }).to_h
      }
    end

    def analyze(path, additional_text: nil, fallback_year: Time.now.year, artifact_dir: nil)
      @started = clock
      @stage = "init"
      @calls = []
      @timings = {}
      @hashes = {}
      raise ArgumentError, "PDF is unsupported; use the legacy EventOcrService path" if File.extname(path.to_s).casecmp(".pdf").zero?
      raise ArgumentError, "Input file does not exist: #{path}" unless File.file?(path)

      if artifact_dir && Dir.exist?(artifact_dir) && !Dir.empty?(artifact_dir)
        raise ArgumentError, "Artifact directory must be empty: #{artifact_dir}"
      end

      bytes = File.binread(path)
      attachment = RubyLLM::Attachment.new(StringIO.new(bytes), filename: File.basename(path), resolution: :original)
      raise ArgumentError, "Source must be an image: #{path}" unless attachment.image?

      @hashes[:source_sha256] = Digest::SHA256.hexdigest(bytes)
      year = Integer(fallback_year)
      schema = Schemas.reader_schema([1], additional_text: additional_text)
      instructions = Prompts.reader_instructions(route: "whole_source", fallback_year: year)
      prompt = Prompts.build_reader_prompt(route: "whole_source", heading: nil, panel_ids: [1], additional_text: additional_text)
      @hashes[:reader_prompt_sha256] = Digest::SHA256.hexdigest(instructions)
      @hashes[:reader_request_sha256] = Digest::SHA256.hexdigest(prompt)
      @hashes[:reader_schema_sha256] = Digest::SHA256.hexdigest(JSON.generate(schema))
      @hashes[:places_catalogue_sha256] = Places.catalogue_sha256
      @hashes[:canonical_schema_sha256] = Digest::SHA256.file(EventValidation::SCHEMA_PATH).hexdigest
      if artifact_dir
        FileUtils.mkdir_p(artifact_dir)
        File.binwrite(File.join(artifact_dir, "source#{File.extname(path)}"), bytes)
        File.write(File.join(artifact_dir, "reader_request.json"), JSON.pretty_generate({instructions: instructions, prompt: prompt, schema: schema}) + "\n")
      end
      @stage = "reader"
      chat = EventOcrService.llm_client(llm_recovery: :none, request_timeout: @request_timeout)
        .chat(model: @model.id, provider: @model.provider).with_schema(schema).with_thinking(effort: @effort).with_instructions(instructions)
      started = clock
      begin
        response = chat.ask(prompt, with: [attachment])
      rescue => e
        @calls << {call_index: 1, stage: "reader", model: @model.id, provider: @model.provider,
                   seconds: (clock - started).round(4), tokens: chat.tokens.to_h, cost: chat.cost.to_h,
                   error: {type: e.class.name, message: e.message}}
        File.write(File.join(artifact_dir, "reader_response.json"), JSON.pretty_generate(@calls.last) + "\n") if artifact_dir
        raise
      ensure
        @timings["reader"] = (clock - started).round(4)
      end
      @calls << {call_index: 1, stage: "reader", model: response.model || @model.id, provider: @model.provider,
                 seconds: @timings["reader"], tokens: chat.tokens.to_h, cost: chat.cost.to_h,
                 finish_reason: response.finish_reason, raw_text: response.content}
      File.write(File.join(artifact_dir, "reader_response.json"), JSON.pretty_generate(@calls.last) + "\n") if artifact_dir
      raise WorkflowError.new("Resposta do leitor OCR incompleta: #{response.finish_reason || "unknown"}", stage: :reader) unless response.stopped?

      begin
        parsed = response.parsed
      rescue JSON::ParserError => e
        raise WorkflowError.new("Erro ao analisar JSON (reader): #{e.message}", stage: :reader)
      end
      errors = JSON::Validator.fully_validate(schema, parsed)
      raise WorkflowError.new("Formato de resposta OCR inválido: #{errors.join("; ")}", stage: :reader, details: errors) unless errors.empty?

      @stage = "admission"
      admitted = Admission.evaluate(parsed.fetch("panels"), panel_meta: {1 => {banner_policy: {action: "direct"}}}, additional_text: additional_text)
      {route: "whole_source", fallback_year: year, events: admitted[:events], review_items: admitted[:review_items], diagnostics: {panels: admitted[:panels], artifact_dir: artifact_dir}}.merge(run_evidence)
    end

    private

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
