# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Music" => {"color" => "#3f7182"},
      "Food" => {"color" => "#c26e5e"},
      "Art" => {"color" => "#7abdc5"},
      "Nature" => {"color" => "#7b55a50"},
      "Health & Wellness" => {"color" => "#75c8e2"},
      "Sports" => {"color" => "#d0a670"},
      "Learning & Workshops" => {"color" => "#2f2d2f"},
      "Community & Culture" => {"color" => "#99aab8"}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
