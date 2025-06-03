module Jekyll
  class CacheBustTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
    end

    def render(context)
      commit_sha = ENV["COMMIT_SHA"]

      if commit_sha && !commit_sha.empty?
        commit_sha
      else
        site = context.registers[:site]
        site.time.to_i.to_s
      end
    end
  end
end

Liquid::Template.register_tag("cache_bust_param", Jekyll::CacheBustTag)
