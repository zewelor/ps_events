# Monkey patch to duplicate CSV keys with underscored versions
Jekyll::Hooks.register :site, :post_read do |site|
  records = site.data["events"]
  next unless records.is_a?(Array)

  records.each do |record|
    next unless record.is_a?(Hash)

    record.keys.each do |key|
      sanitized = key.to_s.downcase.gsub(/\s+/, "_")
      record[sanitized] ||= record[key]
      record.delete(key)
    end

    record["image"] = "/assets/images/#{record["image"]}.webp" if record["image"] && record["image"] != ""
    record["page_slug"] = Class.new.extend(Jekyll::Sanitizer).sanitize_filename(record["start_date"].tr("/", "-") + "-" + record["name"])
  end
end
