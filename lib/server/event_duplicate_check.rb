require "digest"
require_relative "sheet_investigator"

# One live snapshot per ingestion request, updated only after confirmed appends.
class EventDuplicateCheck
  Unavailable = Class.new(StandardError)
  FIELD_COLUMNS = SheetInvestigator::SCHEMA_KEY_BY_COLUMN.invert.freeze
  REQUIRED_COLUMNS = [*FIELD_COLUMNS.values, "added_at", "submitted_by", "image"].freeze

  attr_reader :headers

  def initialize(sheets:, spreadsheet_id:, events_range:)
    @sheets = sheets
    @spreadsheet_id = spreadsheet_id
    target = @sheets.get_values(@spreadsheet_id, events_range)
    tab, first_column, first_row = coordinates(target.range)
    # The configured range may end at O; comparison also needs the link columns.
    last_column = column_name(column_number(first_column) + REQUIRED_COLUMNS.size - 1)
    target = @sheets.get_values(@spreadsheet_id, "#{tab}!#{first_column}#{first_row}:#{last_column}")
    @headers = target.values&.first
    @records = records(target)
    @records.concat(records(@sheets.get_values(@spreadsheet_id, "Approved!A:S"))) unless tab.delete("'") == "Approved"
  rescue => e
    raise Unavailable, "Cannot check existing events: #{e.message}"
  end

  def check(event, distinct_from: [])
    incoming = canonical(event)
    equivalent = @records.find { |record| record[:canonical] == incoming }
    return {status: "skipped", existing_row: equivalent[:reference]} if equivalent

    candidates = @records.filter_map do |record|
      stored = record[:canonical]
      same_day = incoming[:start_date] == stored[:start_date]
      overlapping = incoming[:start_date] <= stored[:end_date] && stored[:start_date] <= incoming[:end_date]
      same_place = incoming[:location] == stored[:location]
      candidate = same_day || (overlapping && same_place)
      next unless candidate

      fingerprint = Digest::SHA256.hexdigest(JSON.generate([incoming, stored, record[:reference]]))
      next if distinct_from.include?(fingerprint)

      {
        reference: record[:reference], fingerprint: fingerprint, event: record[:event],
        differences: FIELD_COLUMNS.keys.select { |field| incoming[field] != stored[field] }
      }
    end
    return if candidates.empty?

    {status: "conflict", event: event, candidates: candidates}
  end

  def record_added(event, reference)
    @records << {event: event, canonical: canonical(event), reference: reference}
  end

  private

  def records(response)
    headers, *rows = response.values
    missing = REQUIRED_COLUMNS - Array(headers)
    raise "Missing spreadsheet columns: #{missing.join(", ")}" if missing.any?
    raise "Duplicate spreadsheet headers" unless headers.uniq.size == headers.size

    tab, first_column, first_row = coordinates(response.range)
    last_column = column_name(column_number(first_column) + headers.size - 1)
    rows.each_with_index.filter_map do |row, index|
      next if row.all? { |value| value.to_s.strip.empty? }

      columns = headers.zip(row).to_h
      event = FIELD_COLUMNS.to_h { |field, column| [field, columns[column].to_s] }
      row_number = first_row + index + 1
      {event: event, canonical: canonical(event), reference: "#{tab}!#{first_column}#{row_number}:#{last_column}#{row_number}"}
    end
  end

  def canonical(event)
    FIELD_COLUMNS.to_h do |field, _|
      value = event[field].to_s
      value = event[:start_date].to_s if field == :end_date && value.strip.empty?
      normalized = if %i[start_date end_date].include?(field)
        raise "Invalid stored date: #{value.inspect}" unless EventValidation::DATE_PATTERN.match?(value)

        Date.strptime(value, "%d/%m/%Y").iso8601
      elsif field.to_s.start_with?("event_link")
        value.strip # URL paths are case-sensitive.
      else
        value.unicode_normalize(:nfc).strip.gsub(/[[:space:]]+/, " ").downcase
      end
      [field, normalized]
    end
  end

  def coordinates(range)
    tab, _, cells = range.to_s.rpartition("!")
    match = /\A([A-Z]+)([1-9]\d*)(?::|\z)/.match(cells)
    raise "Cannot resolve spreadsheet range #{range.inspect}" if tab.empty? || !match

    [tab, match[1], match[2].to_i]
  end

  def column_number(column)
    column.each_byte.reduce(0) { |number, character| number * 26 + character - "A".ord + 1 }
  end

  def column_name(number)
    name = ""
    while number.positive?
      number, remainder = (number - 1).divmod(26)
      name.prepend(("A".ord + remainder).chr)
    end
    name
  end
end
