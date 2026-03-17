#!/usr/bin/env ruby
# Convert bold speaker lines in HARC posts to the new rubric:
# - **I am Q'uo**. / **We are Q'uo**. / **We are those of Q'uo**. -> <span class="speaker" speaker="Entity" via="Instrument">...</span>
# - **Max** : or **Name**: -> <span class="speaker question" speaker="Name">Name</span>:
# Tracks instrument from preceding <p class="instrument-change">Name channeling</p>

POSTS_DIR = File.join(__dir__, "..", "_posts")

def process_file(filepath)
  content = File.read(filepath)
  instrument = nil
  out = []
  content.each_line do |line|
    # Track instrument from instrument-change line
    if line =~ %r{<p class="instrument-change">([A-Za-z]+) channeling</p>}
      instrument = $1
      out << line
      next
    end

    # Questioner: **Name** : or **Name**: (with or without space before colon)
    line = line.gsub(/\*\*([A-Za-z]+)\*\*:\s*/) do
      name = $1
      %Q(<span class="speaker question" speaker="#{name}">#{name}</span>: )
    end
    line = line.gsub(/\*\*([A-Za-z]+)\*\*\s*:\s*/) do
      name = $1
      %Q(<span class="speaker question" speaker="#{name}">#{name}</span>: )
    end

    # Entity greetings: **I am Entity**. **We are Entity**. **We are those of Entity**.
    line = line.gsub(/\*\*(I am [^.]+?)\.\*\*\./) do
      full = $1
      entity = full.sub(/\AI am /, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>.)
    end
    line = line.gsub(/\*\*(We are those of [^.]+?)\.\*\*\.?/) do
      full = $1
      entity = full.sub(/\AWe are those of /, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>.)
    end
    line = line.gsub(/\*\*(We are (?:those of )?[^.]+?)\.\*\*\.?/) do
      full = $1
      entity = full.sub(/\AWe are (?:those of )?/, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>.)
    end

    # Mid-sentence **We are those of Q'uo** (no trailing period on bold)
    line = line.gsub(/\*\*(We are those of [^*]+?)\*\*/) do
      full = $1
      entity = full.sub(/\AWe are those of /, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>)
    end
    line = line.gsub(/\*\*(I am [^*]+?)\*\*/) do
      full = $1
      entity = full.sub(/\AI am /, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>)
    end
    line = line.gsub(/\*\*(We are [^*]+?)\*\*/) do
      full = $1
      entity = full.sub(/\AWe are (?:those of )?/, "").strip
      via = instrument ? " via=\"#{instrument}\"" : ""
      %Q(<span class="speaker" speaker="#{entity}"#{via}>#{full}</span>)
    end

    out << line
  end
  File.write(filepath, out.join)
end

Dir.glob(File.join(POSTS_DIR, "*.md")).each do |filepath|
  process_file(filepath)
  puts "Processed #{File.basename(filepath)}"
end
