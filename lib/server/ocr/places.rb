require "digest"
require "json"

module Ocr
  module Places
    CATALOGUE_PATH = File.expand_path("../../known_places.json", __dir__)
    LOCATION_PATTERN_SOURCE = '^(?:[^\r\n]*[A-Za-zÀ-ÖØ-öø-ÿ]){3}[^\r\n]*$'
    EVIDENCE_PATTERN_SOURCE = '^[^\r\n]*[A-Za-zÀ-ÖØ-öø-ÿ0-9][^\r\n]*$'
    LOCATION_REGEX = /\A(?:[^\r\n]*[A-Za-zÀ-ÖØ-öø-ÿ]){3}[^\r\n]*\z/
    EVIDENCE_REGEX = /\A[^\r\n]*[A-Za-zÀ-ÖØ-öø-ÿ0-9][^\r\n]*\z/

    PLACEHOLDERS = [
      "nao indicado",
      "nao indicada",
      "nao especificado",
      "nao especificada",
      "desconhecido",
      "desconhecida",
      "a confirmar",
      "por confirmar",
      "por definir",
      "sem local",
      "local a definir",
      "na",
      "n a",
      "null",
      "none"
    ].freeze

    GENERIC_ISLAND_NAMES = [
      "porto santo",
      "ilha do porto santo",
      "ilha de porto santo"
    ].freeze

    module_function

    def catalogue
      @catalogue ||= JSON.parse(File.read(CATALOGUE_PATH))
    end

    def catalogue_sha256
      @catalogue_sha256 ||= Digest::SHA256.file(CATALOGUE_PATH).hexdigest
    end

    def prompt_catalogue
      catalogue
    end

    def clean_visible_text(value)
      return nil if value.nil?

      cleaned = value.to_s.unicode_normalize(:nfc).gsub(/\p{Cf}/, "").gsub(/[\p{Z}\s]+/, " ").strip
      cleaned.empty? ? nil : cleaned
    end

    def folded_key(value)
      cleaned = clean_visible_text(value)
      return "" if cleaned.nil?

      cleaned.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def canonical_location(value)
      cleaned = clean_visible_text(value)
      return nil if cleaned.nil? || !LOCATION_REGEX.match?(cleaned)

      key = folded_key(cleaned)
      return nil if PLACEHOLDERS.include?(key) || GENERIC_ISLAND_NAMES.include?(key)

      alias_map[cleaned.downcase] || alias_map_folded[key] || cleaned
    end

    def alias_map
      @alias_map ||= build_alias_map { |entry| entry.downcase }
    end

    def alias_map_folded
      @alias_map_folded ||= build_alias_map { |entry| folded_key(entry) }
    end

    def build_alias_map
      catalogue.each_with_object({}) do |(canonical, aliases), map|
        ([canonical] + aliases).each do |entry|
          map[yield(entry)] = canonical
        end
      end
    end
  end
end
