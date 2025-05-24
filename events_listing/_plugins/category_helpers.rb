# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Music" => {"color" => "#1e3a8a"},
      "Food" => {"color" => "#c26e5e"},
      "Art" => {"color" => "#f97316"},
      "Nature" => {"color" => "#fdba74"},
      "Health & Wellness" => {"color" => "#10b981"},
      "Sports" => {"color" => "#75c8e2"},
      "Learning & Workshops" => {"color" => "#d0a670"},
      "Community & Culture" => {"color" => "#7abdcd"}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
