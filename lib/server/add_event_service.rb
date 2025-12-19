require "active_support/time"

class AddEventService
  def initialize(google_sheets:, spreadsheet_id:, events_range:)
    @google_sheets = google_sheets
    @spreadsheet_id = spreadsheet_id
    @events_range = events_range
  end

  def add_event(event, submitter_email:, image_path: "")
    row = build_row(event, submitter_email, image_path)
    log_event(row)

    unless @google_sheets
      puts "⚠️ Google Sheets service is nil - row NOT appended (APP_ENV=test?)"
      return nil
    end

    result = @google_sheets.append_row(@spreadsheet_id, @events_range, row)
    puts "✅ Row appended to sheet: #{result.updates.updated_range}" if result&.updates
    result
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
