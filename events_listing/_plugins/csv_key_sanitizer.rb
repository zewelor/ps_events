# Monkey patch to duplicate CSV keys with underscored versions
Jekyll::Hooks.register :site, :post_read do |site|
  records = site.data['events']
  next unless records.is_a?(Array)

  records.each do |record|
    next unless record.is_a?(Hash)

    record.keys.each do |key|
      sanitized = key.to_s.downcase.gsub(/\s+/, '_')
      record[sanitized] = record[key] unless record.key?(sanitized)
    end
  end
end
