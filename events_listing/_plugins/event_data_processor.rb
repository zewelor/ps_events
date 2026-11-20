EVENTS_DATA_NAME = "events"

# Monkey patch to duplicate CSV keys with underscored versions
Jekyll::Hooks.register :site, :post_read do |site|
  records = site.data[EVENTS_DATA_NAME]
  next unless records.is_a?(Array)

  event_pages = site.config.fetch("page_gen").find { |page| page["data"] == EVENTS_DATA_NAME }
  raise KeyError, "Missing page_gen configuration for events" unless event_pages

  events_dir = event_pages.fetch("dir")
  used_slugs = {}

  records.each do |record|
    next unless record.is_a?(Hash)

    start_date = record.fetch("start_date")
    name = record.fetch("name")
    record["image"] = "/assets/images/#{record["image"]}.webp" if record["image"] && record["image"] != ""
    base_slug = Class.new.extend(Jekyll::Sanitizer).sanitize_filename(start_date.tr("/", "-") + "-" + name).delete_prefix(".").delete_suffix(".")
    page_slug = base_slug
    suffix = 1

    while used_slugs.key?(page_slug)
      suffix += 1
      page_slug = "#{base_slug}-#{suffix}"
    end

    used_slugs[page_slug] = true
    record["page_slug"] = page_slug
    record["canonical_url"] = File.join(site.config.fetch("url"), events_dir, record["page_slug"])
  end
end
