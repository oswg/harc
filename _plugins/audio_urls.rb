# frozen_string_literal: true

# Liquid filter to check if an MP3 exists in assets/audio/.
# Audio is hosted on S3 (harc-assets); assets/audio is excluded from the build.
# Layout builds the S3 URL from site.audio_base_url.

module Jekyll
  module AudioUrlsFilter
    def has_audio_file(slug)
      return false if slug.to_s.empty?
      path = File.join(Dir.pwd, "assets", "audio", "#{slug}.mp3")
      File.file?(path)
    end
  end
end

Liquid::Template.register_filter(Jekyll::AudioUrlsFilter)
