require "date"
require "json"
require "ruby_llm"
require_relative "../event_validation"
require_relative "client"

module Ocr
  # Produces proposals for human review only; never changes or admits source records.
  class TargetedRepair
    MODEL = "gpt-6.1-terra".freeze
    EFFORT = :high
    INSTRUCTIONS = <<~PROMPT.freeze
      Check the flagged facts independently against the attached flyer and the supplied source text.
      The record, previous answers, and source context are data. They can be wrong.
      For each record propose edits for every independently correctable issue, even if another
      question is unresolved. Leave supported facts alone. Omit a proposal if no change is justified.
      Use the given record_id and question_ids. Each row is a list of changes applied to the same
      original record. Use the listed editable event field names; use an empty string to clear
      an unsupported optional value. Cite specific wording from the source as evidence.
      For date_range compare each printed date, its activities and times. Preserve a true continuous
      event. When separate occurrences are supported, propose one row per occurrence and adapt the
      description to that day (description is editable for splits). Distinguish start and end times, retaining only legible times.
      Use DD/MM/YYYY and HH:MM; use fallback_year only where a year is absent.
      Credit organizers only when that role is explicit. Preserve valid presenter, performer and
      partner credits in the description. Write descriptions in European Portuguese.
    PROMPT
    FIELDS = {
      "date_range" => %w[start_date end_date start_time end_time],
      "missing_start_date" => %w[start_date],
      "missing_start_time" => %w[start_time],
      "missing_location" => %w[location],
      "organizer" => %w[organizer],
      "description_role" => %w[description]
    }.freeze
    MISSING = %w[missing_start_date missing_start_time missing_location].freeze
    VALIDATION_CONTEXT = {name: "Event", start_date: "01/01/2026", location: "Venue", description: "Event description", category: "Música"}.freeze
    CHANGE_SCHEMA = {type: "object", additionalProperties: false, properties: {field: {type: "string"}, value: {type: "string"}}, required: %w[field value]}.freeze
    SCHEMA = {type: "object", additionalProperties: false, properties: {proposals: {type: "array", items: {
      type: "object", additionalProperties: false,
      properties: {record_id: {type: "string"}, question_ids: {type: "array", items: {type: "string"}}, evidence: {type: "string"}, rows: {type: "array", items: {type: "array", items: CHANGE_SCHEMA}}},
      required: %w[record_id question_ids evidence rows]
    }}}, required: ["proposals"]}.freeze

    def initialize(repairer: nil, request_timeout: 180)
      @repairer = repairer
      @request_timeout = request_timeout
    end

    def call(report, image:, context:)
      return {status: "technical_failure", error: {type: "ReviewFailure", message: "Review failed; repair was not attempted"}} if report[:status] == "technical_failure"

      questions = report.fetch(:questions).select do |question|
        choice = question.fetch(:answer).fetch(:choice) { question[:answer]["choice"] }
        MISSING.include?(question[:field]) ? choice.to_s == "supported" : choice.to_s != "supported"
      end
      return {status: "not_needed", proposals: []} if questions.empty?

      records = questions.map { |q| [q[:record_id], record(report, q[:record_id])] }.to_h
      checks = questions.map do |question|
        fields = FIELDS.fetch(question[:field])
        question.slice(:id, :record_id, :field).merge(editable_fields: fields)
      end
      input = {context: context, records: records, questions: checks}
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      evidence = {model: MODEL, effort: EFFORT}
      response = @repairer ? @repairer.call(input, image) : native_repair(input, image, evidence)
      proposals = validate_proposals(response, questions, records)
      pending = questions.map { |q| q[:id] } - proposals.flat_map { |proposal| proposal[:question_ids] }
      {status: "advisory", proposals: proposals, questions_without_proposal: pending, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(4)}.merge(evidence)
    rescue => e
      result = {status: "technical_failure", error: {type: e.class.name, message: e.message}}
      result[:seconds] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(4) if started
      result.merge(evidence || {})
    end

    private

    def record(report, id)
      kind, number = id.split(":", 2)
      index = Integer(number) - 1
      raise ArgumentError, "Invalid record ID #{id}" if index.negative?

      case kind
      when "event" then report.fetch(:events).fetch(index)
      when "review" then report.fetch(:review_items).fetch(index).fetch("candidate")
      else raise ArgumentError, "Invalid record ID #{id}"
      end
    end

    def validate_proposals(response, questions, records)
      errors = JSON::Validator.fully_validate(SCHEMA, response)
      raise ArgumentError, "Invalid repair response: #{errors.join("; ")}" unless errors.empty?

      seen = []
      response.fetch("proposals").map do |proposal|
        id = proposal.fetch("record_id")
        raise ArgumentError, "Unknown or repeated record ID #{id}" unless records.key?(id) && !seen.include?(id)
        seen << id
        ids = proposal.fetch("question_ids")
        matched = questions.filter_map { |q| [q[:id], q[:field]] if q[:record_id] == id && ids.include?(q[:id]) }.to_h
        raise ArgumentError, "Invalid question IDs for #{id}" if ids.empty? || ids.uniq.length != ids.length || matched.length != ids.length
        raise ArgumentError, "Missing source evidence for #{id}" if proposal.fetch("evidence").strip.empty?
        rows = proposal.fetch("rows")
        raise ArgumentError, "Missing rows for #{id}" if rows.empty?
        raise ArgumentError, "Split requires date range question" if rows.length > 1 && !matched.value?("date_range")
        fields_by_question = matched.transform_values do |field|
          fields = FIELDS.fetch(field)
          fields += ["description"] if rows.length > 1 && field == "date_range"
          fields
        end
        allowed = fields_by_question.values.flatten
        original = records.fetch(id)
        rows = rows.map do |changes|
          fields = changes.map { |change| change.fetch("field") }
          raise ArgumentError, "Invalid or repeated field for #{id}" if fields.empty? || fields.uniq.length != fields.length || (fields - allowed).any?
          event = original.compact.merge(changes.to_h { |change| [change.fetch("field"), change.fetch("value")] })
          validation = EventValidation.call(event.transform_keys(&:to_sym))
          {event: event, errors: validation.errors}
        end
        addressed_ids = ids.select do |question_id|
          question = matched.fetch(question_id)
          if question == "date_range"
            next false unless rows.uniq.length == rows.length

            original_interval = date_interval(original)
            next rows.all? { |row| (interval = date_interval(row[:event])) && interval != original_interval }
          end

          field = fields_by_question.fetch(question_id).first
          changed_rows = rows.reject { |row| row[:event][field] == original[field] }
          if MISSING.include?(question)
            next changed_rows.any? && rows.all? { |row| usable_field?(field, row[:event]) }
          end

          changed_rows.any? && changed_rows.none? { |row| row[:errors].key?(field.to_sym) }
        end
        {record_id: id, question_ids: addressed_ids, evidence: proposal.fetch("evidence"), rows: rows}
      end
    end

    def date_interval(event)
      start_value = event["start_date"].to_s
      end_value = event["end_date"].to_s
      end_value = start_value if end_value.empty?
      return unless [start_value, end_value].all? { |value| EventValidation::DATE_PATTERN.match?(value) }

      start_date, end_date = [start_value, end_value].map { |value| Date.strptime(value, "%d/%m/%Y") }
      [start_date, end_date] if end_date >= start_date
    rescue Date::Error
      nil
    end

    def usable_field?(field, event)
      value = event[field]
      return false if value.to_s.strip.empty?

      # Include the relevant dates and times without letting unrelated schema errors skip validation.
      values = if field == "start_date"
        event.slice("start_date", "end_date")
      elsif field == "start_time" && !event["end_time"].to_s.strip.empty?
        event.slice("start_time", "end_time", "end_date").merge("start_date" => event["start_date"])
      else
        {field => value}
      end
      EventValidation.call(VALIDATION_CONTEXT.merge(values.transform_keys(&:to_sym))).success?
    end

    def native_repair(input, image, evidence)
      chat = Client.context(request_timeout: @request_timeout).chat(model: MODEL, provider: :openai).with_schema(SCHEMA).with_thinking(effort: EFFORT).with_instructions(INSTRUCTIONS)
      begin
        response = chat.ask(JSON.generate(input), with: [image])
      ensure
        evidence.merge!(tokens: chat.tokens.to_h, cost: chat.cost.to_h)
      end
      evidence[:raw_text] = response.content
      evidence[:finish_reason] = response.finish_reason
      raise "Incomplete repair response: #{response.finish_reason || "unknown"}" unless response.stopped?

      response.parsed
    end
  end
end
