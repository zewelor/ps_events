require "active_support/time"
require_relative "event_validation"
require_relative "event_validation_error"
require_relative "event_duplicate_check"

class AddEventService
  def initialize(google_sheets:, spreadsheet_id:, events_range:)
    @google_sheets = google_sheets
    @spreadsheet_id = spreadsheet_id
    @events_range = events_range
  end

  def add_event(event, submitter_email:, image_path: "", distinct_from: [])
    validation = EventValidation.call(event)
    if validation.failure?
      raise EventValidationError.new("Invalid event", validation_errors: validation.errors)
    end

    @duplicates ||= EventDuplicateCheck.new(sheets: @google_sheets, spreadsheet_id: @spreadsheet_id, events_range: @events_range)
    decision = @duplicates.check(event, distinct_from: distinct_from)
    return decision if decision

    yield if block_given? # Publish a supplied image only when a row will be added.
    row = build_row(event, submitter_email, image_path)
    log_event(row)
    # Keep the existing formatting and metadata, but write in the live header order.
    column_names = %w[added_at submitted_by name start_date start_time end_date end_time location description category organizer email phone price image link_1 link_2 link_3 link_4]
    columns = column_names.zip(row).to_h

    result = @google_sheets.append_row(@spreadsheet_id, @events_range, @duplicates.headers.map { |header| columns.fetch(header) })
    range = result&.updates&.updated_range
    raise "Append outcome is unknown; read the live sheet before retrying" if range.to_s.empty?

    @duplicates.record_added(event, range)
    puts "✅ Row appended to sheet: #{range}"
    {status: "added", range: range}
  rescue
    @duplicates = nil # A lost append response must be checked against live data.
    raise
  end

  private

  def build_row(event, submitter_email, image_path)
    # Set timezone to Lisbon/Portugal time
    Time.zone = "Europe/Lisbon"

    [
      Time.zone.now.strftime("%d/%m/%Y %H:%M"),
      submitter_email,
      event[:name].to_s.strip,
      event[:start_date].to_s.strip,
      event[:start_time].to_s.strip,
      event[:end_date].to_s.strip,
      event[:end_time].to_s.strip,
      event[:location].to_s.strip,
      event[:description].to_s.strip,
      event[:category].to_s.strip,
      event[:organizer].to_s.strip,
      event[:contact_email]&.strip&.downcase,
      event[:contact_tel]&.strip || "",
      event[:price_type]&.strip || "",
      image_path.to_s.empty? ? "" : File.basename(image_path, ".*"),
      event[:event_link1]&.strip || "",
      event[:event_link2]&.strip || "",
      event[:event_link3]&.strip || "",
      event[:event_link4]&.strip || ""
    ]
  end

  def log_event(row)
    masked = row.dup
    masked[1] = "#{masked[1].split("@").first}@***" if masked[1]&.include?("@")
    masked[11] = "#{masked[11].split("@").first}@***" if masked[11]&.include?("@")
    puts "✅ Adding event: #{masked[2]} by #{masked[10]} on #{masked[3]} #{masked[4]} (submitted by #{masked[1]}, contact: #{masked[11]})"
  end
end
