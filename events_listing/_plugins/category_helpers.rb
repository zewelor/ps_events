# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Music" => {"color" => "#F08080"},
      "Food" => {"color" => "#FFA07A"},
      "Art" => {"color" => "#40E0D0"},
      "Nature" => {"color" => "#20B2AA"},
      "Health & Wellness" => {"color" => "#98FB98"},
      "Sports" => {"color" => "#FF7F50"},
      "Learning & Workshops" => {"color" => "#ADD8E6"},
      "Community & Culture" => {"color" => "#DAA520"}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
