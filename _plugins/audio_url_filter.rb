# frozen_string_literal: true

module Jekyll
  module AudioUrlFilter
    include Jekyll::Filters::URLFilters

    # Resolved URL safe for audio src / download href: absolute when using audio_base_url,
    # otherwise site-relative via relative_url.
    def post_audio_href(post)
      override_url = fetch_post_attr(post, "audio") || fetch_post_attr(post, "media") 
      return override_url if override_url

      site = @context.registers[:site]
      audio_base = site.config["audio_base_url"].to_s.strip
      path = fetch_post_attr(post, "path").to_s
      stem = path.split("/").last.split(".").first
      raise "no audio stem for #{path} (#{stem})" if stem.empty?
      
      [audio_base, "#{stem}.mp3"].compact.join("/")
    end

    private

    def fetch_post_attr(post, key)
      k = key.to_s
      if post.respond_to?(:[])
        v = post[k]
        return v unless v.nil?
      end
      if post.respond_to?(:data) && post.data.is_a?(Hash)
        v = post.data[k]
        return v unless v.nil?
      end

      nil
    end
  end
end

Liquid::Template.register_filter(Jekyll::AudioUrlFilter)
