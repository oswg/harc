#!/usr/bin/env ruby
# frozen_string_literal: true

# Find orphan MP3s (in assets/audio/ without a matching post).
# For each: transcribe, create a post with title: TBD and transcript in body.
# Used by the transcribe-missing-audio GitHub Action.
#
# Usage:
#   OPENAI_API_KEY=xxx ruby scripts/transcribe_missing_audio.rb
#   OPENAI_API_KEY=xxx ruby scripts/transcribe_missing_audio.rb --dry-run
#
# Env:
#   OPENAI_API_KEY   (required)

require "openai"

POSTS_DIR = "_posts"
ASSETS_AUDIO = "assets/audio"

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
    client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"], timeout: 600)
    response = client.audio.transcriptions.create(
      file: File.open(mp3_path, "rb"),
      model: "whisper-1",
      prompt: CHANNELING_PROMPT
    )
    response.text
  end
end

def orphan_mp3s
  return [] unless Dir.exist?(ASSETS_AUDIO)
  existing_posts = Dir["#{POSTS_DIR}/*.md"].map { |p| File.basename(p, ".md") }
  Dir["#{ASSETS_AUDIO}/*.mp3"].map do |mp3_path|
    basename = File.basename(mp3_path, ".mp3")
    basename if !existing_posts.include?(basename)
  end.compact.sort
end

def create_post(post_filename, transcript)
  content = <<~MD
    ---
    title: TBD
    group_question: TBD
    introduction: TBD
    categories:
    - TBD
    ---

    #{transcript}
  MD
  File.write(File.join(POSTS_DIR, post_filename), content)
end

def main
  dry_run = ARGV.delete("--dry-run")

  abort "Set OPENAI_API_KEY" if ENV["OPENAI_API_KEY"].to_s.strip.empty?

  orphans = orphan_mp3s
  if orphans.empty?
    puts "No orphan MP3s."
    return
  end

  puts "Found #{orphans.size} orphan MP3(s)"
  puts "(dry-run)" if dry_run

  created = 0
  orphans.each do |mp3_basename|
    local_mp3 = File.join(ASSETS_AUDIO, "#{mp3_basename}.mp3")
    post_filename = "#{mp3_basename}.md"

    print "  #{mp3_basename}.mp3 ... "
    if dry_run
      puts "OK (dry-run)"
      next
    end

    print "transcribe ... "
    transcript = Transcriber.call(local_mp3)
    puts "OK (#{transcript.length} chars)"

    create_post(post_filename, transcript)
    puts "         created #{POSTS_DIR}/#{post_filename}"
    created += 1
  end

  puts "\nCreated #{created} post(s)" unless dry_run
end

main
