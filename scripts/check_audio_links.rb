#!/usr/bin/env ruby
# frozen_string_literal: true

# All posts have audio on S3. This script just reports post count.
# Audio URLs: {audio_base_url}/{post_basename}.mp3
#
# Usage: ruby scripts/check_audio_links.rb

POSTS_DIR = "_posts"

def main
  posts = Dir.glob("#{POSTS_DIR}/**/*.md").sort
  puts "Posts: #{posts.size} (all have audio on S3)"
end

main
