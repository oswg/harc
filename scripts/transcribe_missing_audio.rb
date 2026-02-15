#!/usr/bin/env ruby
# frozen_string_literal: true

# Find posts without an audio key, infer S3 path from filename, download, transcribe, update post.
# Used by the transcribe-missing-audio GitHub Action.
#
# Usage:
#   OPENAI_API_KEY=xxx HARC_S3_BUCKET=my-bucket ruby scripts/transcribe_missing_audio.rb
#   OPENAI_API_KEY=xxx HARC_S3_BUCKET=my-bucket ruby scripts/transcribe_missing_audio.rb --dry-run
#
# Env:
#   OPENAI_API_KEY   (required)
#   HARC_S3_BUCKET   (required)
#   HARC_S3_PREFIX   (default: audio)
#   HARC_S3_REGION   (default: us-east-1)

require "openai"

POSTS_DIR = "_posts"

# Reuse transcription logic from transcribe.rb
module Transcriber
  CHANNELING_PROMPT = <<~TEXT.freeze
    You are an editor of information received from entities in the
    Confederation of Planets in Service to the One Infinite Creator. Please
    review material from High Altitude Receiving Center, and format the sentence
    and paragraph structure like theirs. In addition, pay attention to the name
    of the contact and ensure it's one of these: Q'uo, Hatonn, Laitos, Monka,
    Oorkas, Auxhall. Pay attention also to when the speaker changes if you can
    and make a small note. Finally, break things up into cogent paragraphs that
    improve readability.
  TEXT

  def self.call(mp3_path)
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"], request_timeout: 600)
    response = client.audio.transcribe(
      parameters: {
        model: "whisper-1",
        file: File.open(mp3_path, "rb"),
        prompt: CHANNELING_PROMPT
      }
    )
    response["text"]
  end
end

def posts_without_audio
  Dir["#{POSTS_DIR}/*.md"].sort.select do |path|
    content = File.read(path)
    next false unless content =~ /\A---\s*\n(.*?)---\s*\n(.*)/m
    fm = Regexp.last_match(1)
    !fm.match?(/^audio:\s/m)
  end
end

def infer_s3_key(post_path)
  basename = File.basename(post_path, ".md")
  prefix = (ENV["HARC_S3_PREFIX"] || "audio").strip.chomp("/")
  prefix.empty? ? "#{basename}.mp3" : "#{prefix}/#{basename}.mp3"
end

def s3_url(s3_key)
  bucket = ENV["HARC_S3_BUCKET"]
  region = ENV["HARC_S3_REGION"] || ENV["AWS_REGION"] || "us-east-1"
  "https://#{bucket}.s3.#{region}.amazonaws.com/#{s3_key}"
end

def download_from_s3(s3_key, local_path)
  bucket = ENV["HARC_S3_BUCKET"]
  region = ENV["HARC_S3_REGION"] || ENV["AWS_REGION"] || "us-east-1"
  region_arg = region == "us-east-1" ? "" : " --region #{region}"
  system("aws s3 cp s3://#{bucket}/#{s3_key} #{local_path}#{region_arg}")
end

def update_post(post_path, audio_url, transcript)
  content = File.read(post_path)
  return false unless content =~ /\A---\n(.*?)---\n(.*)/m

  fm = Regexp.last_match(1)
  new_fm = fm.rstrip + "\naudio: \"#{audio_url}\"\n"
  new_content = "---\n#{new_fm}---\n\n#{transcript}\n"
  File.write(post_path, new_content)
  true
end

def main
  dry_run = ARGV.delete("--dry-run")

  abort "Set OPENAI_API_KEY" if ENV["OPENAI_API_KEY"].to_s.strip.empty?
  abort "Set HARC_S3_BUCKET" if ENV["HARC_S3_BUCKET"].to_s.strip.empty?

  posts = posts_without_audio
  if posts.empty?
    puts "No posts missing audio."
    return
  end

  puts "Found #{posts.size} post(s) without audio"
  puts "(dry-run)" if dry_run

  updated = 0
  posts.each do |post_path|
    s3_key = infer_s3_key(post_path)
    mp3_basename = File.basename(s3_key)
    local_mp3 = File.join(Dir.tmpdir, mp3_basename)
    audio_url = s3_url(s3_key)

    print "  #{File.basename(post_path)}: fetch #{s3_key} ... "
    unless download_from_s3(s3_key, local_mp3)
      puts "SKIP (not found or download failed)"
      next
    end
    puts "OK"

    next if dry_run

    print "         transcribe ... "
    transcript = Transcriber.call(local_mp3)
    puts "OK (#{transcript.length} chars)"
    File.unlink(local_mp3) if File.exist?(local_mp3)

    if update_post(post_path, audio_url, transcript)
      puts "         updated #{post_path}"
      updated += 1
    else
      puts "         FAILED to update"
    end
  end

  puts "\nUpdated #{updated} post(s)" unless dry_run
end

main
