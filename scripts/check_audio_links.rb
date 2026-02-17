#!/usr/bin/env ruby
# frozen_string_literal: true

# Check that every post with an expected audio player has a valid MP3 in repo.
# Verifies: (1) MP3 exists at assets/audio/{post_basename}.mp3
#           (2) MP3 is a valid audio file (via ffprobe if available)
# MP3s are synced to S3 (harc-assets) on deploy; site links point to S3.
#
# Usage: ruby scripts/check_audio_links.rb
#        ruby scripts/check_audio_links.rb --verbose

POSTS_DIR = "_posts"
ASSETS_AUDIO = "assets/audio"

def find_posts
  Dir.glob("#{POSTS_DIR}/**/*.md").sort
end

def audio_slug_for_post(post_path)
  File.basename(post_path, ".md")
end

def expected_mp3_path(slug)
  File.join(ASSETS_AUDIO, "#{slug}.mp3")
end

def valid_audio?(mp3_path)
  return false unless File.file?(mp3_path)
  return false if File.size(mp3_path) < 100 # suspiciously small
  # Use ffprobe to validate the file is playable (exit 0 = valid)
  return true if system("ffprobe", "-v", "error", "-i", mp3_path, out: File::NULL, err: File::NULL)
  # Fallback when ffprobe unavailable: check MP3 magic bytes
  mag = File.binread(mp3_path, 3)
  mag == "ID3" || (mag.bytes[0] == 0xff && (mag.bytes[1] & 0xe0) == 0xe0)
rescue
  false
end

def main
  verbose = ARGV.delete("--verbose") || ARGV.delete("-v")
  posts = find_posts

  if posts.empty?
    puts "No posts found in #{POSTS_DIR}/"
    return
  end

  ok = []
  missing = []
  invalid = []

  posts.each do |post_path|
    slug = audio_slug_for_post(post_path)
    mp3_path = expected_mp3_path(slug)

    unless File.exist?(mp3_path)
      missing << { post: post_path, slug: slug }
      next
    end

    if valid_audio?(mp3_path)
      ok << { post: post_path, slug: slug }
    else
      invalid << { post: post_path, slug: slug, path: mp3_path }
    end
  end

  # Report
  puts "Audio link check: #{posts.size} post(s)"
  puts

  if missing.any?
    puts "MISSING MP3 (#{missing.size}):"
    missing.each do |h|
      puts "  #{h[:post]}"
      puts "    expected: #{expected_mp3_path(h[:slug])}" if verbose
    end
    puts
  end

  if invalid.any?
    puts "INVALID/CORRUPT MP3 (#{invalid.size}):"
    invalid.each do |h|
      puts "  #{h[:post]}"
      puts "    #{h[:path]}" if verbose
    end
    puts
  end

  puts "OK: #{ok.size} post(s) with valid audio"
  ok.each { |h| puts "  #{h[:post]}" } if verbose && ok.any?

  exit 1 if missing.any? || invalid.any?
end

main
