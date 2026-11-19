require "active_support/core_ext/object/blank"
require_relative "../event_ocr_service"
require_relative "../llm_schema"
require_relative "places"

module Ocr
  module Schemas
    REVIEW_REASONS = %w[
      none
      missing_start_date
      missing_location
      missing_required_fields
      conflicting_inset
      conflicting_main_text
      ambiguous_venue_policy
      insufficient_information
    ].freeze

    module_function

    def reader_schema(panel_ids, additional_text: nil)
      candidate_schema = build_candidate_schema
      if additional_text.blank?
        %w[location_source date_source time_source price_source].each do |source|
          candidate_schema.fetch("properties").fetch(source).fetch("enum").delete("additional_text")
        end
      end
      panel_schema = {
        "type" => "object",
        "properties" => {
          "panel_id" => {"type" => "integer", "enum" => panel_ids},
          "panel_review_reason" => {"type" => "string", "enum" => %w[none illegible_panel conflicting_main_text insufficient_information]},
          "panel_review_detail" => {"type" => %w[string null]},
          "candidates" => {"type" => "array", "items" => candidate_schema}
        },
        "required" => %w[panel_id panel_review_reason panel_review_detail candidates],
        "additionalProperties" => false
      }
      {
        "type" => "object",
        "properties" => {
          "panels" => {
            "type" => "array",
            "items" => panel_schema,
            "minItems" => panel_ids.length,
            "maxItems" => panel_ids.length
          }
        },
        "required" => ["panels"],
        "additionalProperties" => false
      }
    end

    def build_candidate_schema
      base_item = Marshal.load(Marshal.dump(EventOcrService.build_schema.dig("properties", "events", "items")))
      properties = base_item.fetch("properties")
      properties.delete("responsibility_agreement")

      properties.each_value do |property|
        property["type"] = Array(property["type"]).uniq
        property["type"] << "null" unless property["type"].include?("null")
        if property.key?("enum") && !property["enum"].include?(nil)
          property["enum"] << nil
        end
      end

      properties["location"] = {
        "type" => %w[string null],
        "pattern" => Places::LOCATION_PATTERN_SOURCE,
        "maxLength" => 100,
        "description" => "Venue supported by this panel, containing at least three visible Latin letters. Prefer a matching known venue name, but a completely new venue is allowed. Null when missing."
      }
      properties["location_evidence"] = {
        "type" => %w[string null],
        "pattern" => Places::EVIDENCE_PATTERN_SOURCE,
        "description" => "Exact visible words in THIS panel supporting the venue or its catalogue alias, or null. Organizer, booking or sponsor attribution alone does not prove the venue."
      }
      properties["location_source"] = {
        "type" => "string",
        "enum" => %w[main_text banner additional_text organizer_only booking_only sponsor_only inset none]
      }
      properties["date_source"] = {
        "type" => "string",
        "enum" => %w[main_text banner additional_text inset none]
      }
      properties["time_source"] = {
        "type" => "string",
        "enum" => %w[main_text banner additional_text inset none]
      }
      properties["price_source"] = {
        "type" => "string",
        "enum" => %w[main_text banner additional_text service_fee_only none]
      }
      properties["review_reason"] = {
        "type" => "string",
        "enum" => REVIEW_REASONS
      }
      properties["review_detail"] = {
        "type" => %w[string null],
        "description" => "Short explanation of the review reason, or null when none."
      }
      base_item["required"] = properties.keys
      base_item["additionalProperties"] = false
      LLMSchema.sanitize(base_item)
    end
  end
end
