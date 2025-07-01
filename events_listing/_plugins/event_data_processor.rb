EVENTS_DATA_NAME = "events"

# Monkey patch to duplicate CSV keys with underscored versions
Jekyll::Hooks.register :site, :post_read do |site|
  records = site.data[EVENTS_DATA_NAME]
  next unless records.is_a?(Array)

  events_dir = site.config["page_gen"].find { |pg| pg["data"] == EVENTS_DATA_NAME }&.dig("dir")
  records.each do |record|
    next unless record.is_a?(Hash)

    record["image"] = "/assets/images/#{record["image"]}.webp" if record["image"] && record["image"] != ""
    record["page_slug"] = Class.new.extend(Jekyll::Sanitizer).sanitize_filename(record["start_date"].tr("/", "-") + "-" + record["name"])
    record["canonical_url"] = File.join(site.config.fetch("url"), events_dir, record["page_slug"])
  end
end
