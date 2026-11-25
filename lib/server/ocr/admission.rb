require "active_support/core_ext/enumerable"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/object/blank"
require_relative "../event_validation"
require_relative "places"

module Ocr
  class WorkflowError < StandardError
    attr_reader :stage, :panel_id, :details

    def initialize(message, stage: nil, panel_id: nil, details: nil)
      super(message)
      @stage = stage
      @panel_id = panel_id
      @details = details
    end
  end

  module Admission
    EVENT_KEYS = (EventValidation::SCHEMA.fetch("properties").keys - ["responsibility_agreement"]).freeze
    REQUIRED_FIELDS = (EventValidation::SCHEMA.fetch("required") - ["responsibility_agreement"]).map(&:to_sym).freeze
    NON_VENUE_SOURCES = %w[organizer_only booking_only sponsor_only inset none].freeze
    VALID_PANEL_REVIEW_REASONS = %w[none illegible_panel conflicting_main_text insufficient_information].freeze

    module_function

    def evaluate(panels_data, panel_ids:, additional_text: nil)
      validate_panel_coverage!(panels_data, panel_ids)

      events = []
      review_items = []
      uncertain_fields_by_index = {}
      panel_summaries = []

      panels_data.each do |panel|
        panel_id = panel.fetch("panel_id")
        panel_reason = panel.fetch("panel_review_reason")
        panel_detail = Places.clean_visible_text(panel["panel_review_detail"])
        candidates = panel.fetch("candidates")

        panel_ready = 0
        panel_reviewed = 0

        candidates.each_with_index do |raw_candidate, idx|
          outcome = evaluate_candidate(
            raw_candidate,
            panel_id: panel_id,
            candidate_index: idx + 1,
            panel_reason: panel_reason,
            panel_detail: panel_detail,
            additional_text: additional_text
          )
          if outcome[:type] == :event
            uncertain_fields = outcome.fetch(:uncertain_fields)
            uncertain_fields_by_index[events.length] = uncertain_fields unless uncertain_fields.empty?
            events << outcome[:event]
            panel_ready += 1
          else
            review_items << outcome[:review_item]
            panel_reviewed += 1
          end
        end

        if candidates.empty? && panel_reason != "none"
          review_items << {
            stage: "admission",
            group_id: panel_id,
            reason: panel_reason,
            message: panel_detail,
            candidate: nil,
            trace: {
              verified: false
            }
          }
          panel_reviewed += 1
        end

        panel_summaries << {
          panel_id: panel_id,
          ready_count: panel_ready,
          review_count: panel_reviewed,
          panel_review_reason: panel_reason
        }
      end

      {events: events, review_items: review_items, uncertain_fields_by_index: uncertain_fields_by_index, panels: panel_summaries}
    end

    def validate_panel_coverage!(panels_data, panel_ids)
      unless panels_data.is_a?(Array)
        raise WorkflowError.new("Formato de resposta OCR inválido: panels deve ser uma lista", stage: :reader)
      end

      expected_ids = panel_ids.sort
      actual_ids = panels_data.map do |panel|
        unless panel.is_a?(Hash) && panel["candidates"].is_a?(Array) && VALID_PANEL_REVIEW_REASONS.include?(panel["panel_review_reason"])
          raise WorkflowError.new("Formato de resposta OCR inválido num painel", stage: :reader, details: panel)
        end

        panel["panel_id"]
      end

      return if actual_ids.sort == expected_ids && actual_ids.uniq.length == expected_ids.length

      raise WorkflowError.new(
        "Cobertura de painéis incompleta ou duplicada: esperado #{expected_ids.inspect}, obtido #{actual_ids.inspect}",
        stage: :reader
      )
    end

    def evaluate_candidate(raw, panel_id:, candidate_index:, panel_reason:, panel_detail:, additional_text:)
      unless raw.is_a?(Hash)
        raise WorkflowError.new("Candidato inválido no painel #{panel_id}", stage: :reader, panel_id: panel_id)
      end

      candidate = normalize_candidate_fields(raw)
      location_evidence = Places.clean_visible_text(raw["location_evidence"])
      sources = {
        location_source: raw["location_source"].to_s,
        date_source: raw["date_source"].to_s,
        time_source: raw["time_source"].to_s,
        price_source: raw["price_source"].to_s
      }
      review_reason = raw["review_reason"].to_s
      review_detail = Places.clean_visible_text(raw["review_detail"])

      location_source = sources.fetch(:location_source)
      venue_only_review = %w[missing_location ambiguous_venue_policy].include?(review_reason)
      missing_location = location_evidence.nil? || NON_VENUE_SOURCES.include?(location_source) ||
        (location_source == "additional_text" && additional_text.blank?)
      original_location = candidate[:location]
      location = Places.canonical_location(original_location) unless missing_location
      conflicting_location = conflicting_venue_evidence?(location, location_evidence)
      candidate[:location] = (venue_only_review || conflicting_location) ? nil : location
      uncertain_fields = {}
      uncertain_fields[:location] = {candidate: original_location, evidence: location_evidence} if conflicting_location

      block_reason = determine_block_reason(
        candidate: candidate,
        sources: sources,
        review_reason: venue_only_review ? "none" : review_reason,
        panel_reason: panel_reason,
        additional_text: additional_text
      )

      unless block_reason
        validation = EventValidation.call(candidate.compact_blank.merge(responsibility_agreement: "on"))
        return {type: :event, event: validation.to_h, uncertain_fields: uncertain_fields} if validation.success?

        block_reason = "invalid_event_fields"
        review_detail = "Alguns dados do evento são inválidos."
      end

      if sources[:date_source] == "none"
        # The correction form leaves the start date empty for this reason.
        candidate[:start_date] = nil unless block_reason == "missing_start_date"
        candidate[:end_date] = nil
      end

      review_item = {
        stage: "admission",
        group_id: panel_id,
        candidate_index: candidate_index,
        reason: block_reason,
        message: [review_detail, panel_detail].compact.uniq.join(" | ").presence,
        candidate: candidate,
        trace: {
          location_evidence: location_evidence,
          **sources,
          panel_review_reason: panel_reason,
          panel_review_detail: panel_detail,
          verified: false
        }
      }
      review_item[:validation_errors] = validation.errors if validation
      {type: :review, review_item: review_item}
    end

    def normalize_candidate_fields(raw)
      candidate = EVENT_KEYS.each_with_object({}) do |key, acc|
        acc[key.to_sym] = Places.clean_visible_text(raw[key])
      end
      if raw["time_source"] == "none"
        candidate[:start_time] = nil
        candidate[:end_time] = nil
      end
      if %w[service_fee_only none].include?(raw["price_source"].to_s) || candidate[:price_type].nil?
        candidate[:price_type] = "Desconhecido"
      end
      candidate
    end

    def conflicting_venue_evidence?(location, location_evidence)
      return false if location.nil?

      location_match = Places.alias_map_folded[Places.folded_key(location)]
      evidence_match = Places.alias_map_folded[Places.folded_key(location_evidence)]
      location_match.present? && evidence_match.present? && location_match != evidence_match
    end

    def determine_block_reason(candidate:, sources:, review_reason:, panel_reason:, additional_text:)
      return "unavailable_additional_text" if additional_text.blank? && sources.value?("additional_text")
      return review_reason if review_reason != "none" && !review_reason.empty?
      return "conflicting_inset" if sources[:date_source] == "inset" || sources[:time_source] == "inset"

      return "missing_start_date" if candidate[:start_date].nil? || sources[:date_source] == "none"
      missing_required = REQUIRED_FIELDS.any? { |field| candidate[field].nil? }
      return "missing_required_fields" if missing_required
      return panel_reason if panel_reason && panel_reason != "none"

      nil
    end
  end
end
