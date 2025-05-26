# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Música" => {"color" => "#3f7182"},
      "Comida" => {"color" => "#c26e5e"},
      "Arte" => {"color" => "#7abdc5"},
      "Natureza" => {"color" => "#7b5a50"},
      "Saúde & Bem-Estar" => {"color" => "#75c8e2"},
      "Desporto" => {"color" => "#d0a670"},
      "Aprendizagem & Workshops" => {"color" => "#2f2d2f"},
      "Comunidade & Cultura" => {"color" => "#99aab8"}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
