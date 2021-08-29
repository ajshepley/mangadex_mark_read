# frozen_string_literal: true

require "json"
require "getoptlong"
require_relative "lib/dex_api.rb"

# See https://api.mangadex.org/docs.html#section/Rate-limits
MAX_REQUESTS_PER_SECOND = 5
API_REFRESH_INTERVAL_SECONDS = 1.1

# I'm not sure if the reason behind the inconsistency is cache weirdness, API weirdness, or DB issues.
# Might as well give them time for any DB operations to complete.
DEFAULT_DELAY_BETWEEN_LOOPS_SECONDS = 30
MAX_LOOP_REPEATS = 4

# e.g. https://mangadex.org/title/4fd4f8c0-fab8-4ee5-ab9e-5907720afed9/verndio-surreal-sword-saga
# Best effort stripping the ?page query param.
MANGA_ID_URL_PATTERN = %r{\Ahttps://mangadex\.org/title/([^/]+)/([^/]+)}

@dex_api = DexApi::Client.get

def get_login_session_token(username:, password:)
  unless username && !username.empty? && password && !password.empty?
    puts "A valid username and password are needed. Aborting."
    exit(1)
  end

  login_result = @dex_api.login(username: username, password: password)
  result_body = login_result.body

  unless login_result.code_type == Net::HTTPOK && result_body
    puts "Failed to login. Code: " + login_result.code + " Response body: " + result_body
    exit(1)
  end

  JSON.parse(result_body).dig("token", "session")
end

def parse_chapter_ids_to_mark(total_chapter_list:, read_chapters:)
  total_chapter_list
    .reject { |chapter| read_chapters.include?(chapter.dig("data", "id")) }
    .map { |chapter| chapter.dig("data", "id") }
end

# TODO: Check for the X-Ratelimit headers and act accordingly.
def mark_as_read(chapter_ids:, max_requests_per_second:, refresh_interval_seconds:, token:)
  chapter_ids.each_with_index do |chapter_id, index|
    sleep_and_log(sleep_time_seconds: refresh_interval_seconds) if (index + 1) % max_requests_per_second == 0

    puts "Marking chapter #{chapter_id}, index #{index} as read."
    result = @dex_api.mark_chapter_read(chapter_id: chapter_id, token: token)

    puts "Result for chapter #{chapter_id} at index #{index} is #{result}"
  end
end

def sleep_and_log(sleep_time_seconds: 1)
  puts "Sleeping for #{sleep_time_seconds} seconds to refresh API usage."
  animated_sleep(sleep_time_seconds: sleep_time_seconds)
end

def animated_sleep(sleep_time_seconds:)
  print("Sleeping")
  sleep_time_seconds.to_i.times do
    print(".")
    sleep(1)
  end
  puts "\n"
end

def parse_manga_id(manga_url:)
  unless manga_url
    puts "A valid manga url is required if no manga_id is provided."
    return
  end

  if (match_info = MANGA_ID_URL_PATTERN.match(manga_url))
    # Match [0] is the source string.
    manga_id = match_info[1]
    manga_name = match_info[2]
  end

  unless manga_id
    puts "Failed to parse manga id from url: #{manga_url}."
    exit(1)
  end

  name = manga_name&.split("-")&.map(&:capitalize)&.join(" ")
  puts "Parsed manga id #{manga_id}, for manga: '#{name}'"

  manga_id
end

def loop_and_mark_read(max_attempts:, manga_id:, session_token:, chapters_list_result:, retry_delay:, language:)
  attempt = 0

  while attempt < max_attempts
    read_chapters_result = @dex_api.get_read_markers(manga_id: manga_id, token: session_token)

    read_chapters = JSON.parse(read_chapters_result.body).dig("data")
    chapter_list = JSON.parse(chapters_list_result.body).dig("results")

    chapter_ids_to_mark = parse_chapter_ids_to_mark(total_chapter_list: chapter_list, read_chapters: read_chapters)
    all_chapters_marked = chapter_ids_to_mark.none?

    time_to_sleep = API_REFRESH_INTERVAL_SECONDS
    if attempt > 0
      time_to_sleep = retry_delay
      puts "Detected #{chapter_ids_to_mark.size} chapters still not marked read."
      puts "Sleeping #{time_to_sleep} seconds before marking all as read for retry attempt #{attempt}."
    end

    # Let API quota refresh a bit.
    animated_sleep(sleep_time_seconds: time_to_sleep) unless all_chapters_marked

    puts "Marking #{chapter_ids_to_mark.size} chapters as read out of #{chapter_list.size} (#{language}) chapters."
    puts "User's total read chapters size (all languages): #{read_chapters.size}. Attempt: #{attempt + 1}."

    # FIXME: Mangadex will sometimes return 200 but fail to mark some chapters as read.
    mark_as_read(
      chapter_ids: chapter_ids_to_mark,
      max_requests_per_second: MAX_REQUESTS_PER_SECOND,
      refresh_interval_seconds: API_REFRESH_INTERVAL_SECONDS,
      token: session_token,
    ) unless all_chapters_marked

    attempt = all_chapters_marked ? attempt = max_attempts : attempt += 1
  end
end

def help_message
  <<~HELP
    mark_read.rb [OPTIONS]
      -h, --help:
        Show this help message
      -m, --mange_id [id]:
        The manga id to mark read. Must provide this or an explicit --url.
      -u, --username [name]:
        The username to login and retrieve a token with. Must also have a --password.
      -p, --password [password]:
        The password to login and retrieve a token with. Must also have a --username.
      -r, --url [url]:
        The URL of the manga to mark as read. Must provide either this or an explicit --manga_id.
      -l, --language [language_code]:
        The language to use when filtering chapter lookups. Defaults to 'en' if not provided.
      -t, --token [token]:
        The (bearer) session token to use. --username and --password are ignored if a token is provided.
      -d, --print-token:
        Before performing the requests, print out the session token being used. Can be provided as --token for subsequent invocations.
      -f, --force [delay between loops in seconds, optional]:
        Force the chapters to be marked as read, looping until the API says all chapters are read. Max limit: 5 loops.
  HELP
end

def parse_options
  # TODO: Convert to OptionParser and delete print_help
  opts = GetoptLong.new(
    ["--manga_id", "-m", GetoptLong::REQUIRED_ARGUMENT],
    ["--username", "-u", GetoptLong::REQUIRED_ARGUMENT],
    ["--password", "-p", GetoptLong::REQUIRED_ARGUMENT],
    ["--url", "-r", GetoptLong::REQUIRED_ARGUMENT],
    ["--token", "-t", GetoptLong::REQUIRED_ARGUMENT],
    ["--print-token", "-d", GetoptLong::NO_ARGUMENT],
    ["--force", "-f", GetoptLong::OPTIONAL_ARGUMENT],
    ["--language", "-l", GetoptLong::OPTIONAL_ARGUMENT],
    ["--help", "-h", GetoptLong::NO_ARGUMENT],
  )

  options = {
    translated_language: "en",
  }

  opts.each do |opt, arg|
    case opt
    when "--username"
      options[:username] = arg
    when "--password"
      options[:password] = arg
    when "--manga_id"
      options[:manga_id] = arg
    when "--url"
      options[:manga_url] = arg
    when "--token"
      options[:session_token] = arg if arg && !arg.strip.empty?
    when "--print-token"
      options[:print_token] = true
    when "--force"
      options[:force_delay] = arg if arg && !arg.strip.empty?
      options[:force_delay] ||= DEFAULT_DELAY_BETWEEN_LOOPS_SECONDS
    when "--language"
      options[:translated_language] = arg if arg && !arg.strip.empty?
    when "--help"
      puts help_message
      exit(0)
    end
  end

  unless options.size > 1
    puts "No arguments provided."
    puts help_message
    exit(1)
  end

  options
end

def main
  options = parse_options
  manga_id = options[:manga_id] || parse_manga_id(manga_url: options[:manga_url])

  unless manga_id
    puts "No --manga_id provided. Aborting."
    exit(1)
  end

  session_token = options[:session_token] || get_login_session_token(
    username: options[:username],
    password: options[:password],
  )

  unless session_token
    puts "Failed to get session token. Response body: #{result_body}"
    exit(1)
  end

  puts "Token is: #{session_token}" if options[:print_token]

  language = options[:translated_language]
  chapters_list_result = @dex_api.get_chapters_list(manga_id: manga_id, translated_language: language)

  # Loop up to MAX_LOOP_REPEATS, only sleep when necessary.
  max_attempts = options[:force_delay] ? MAX_LOOP_REPEATS + 1 : 1

  loop_and_mark_read(
    max_attempts: max_attempts,
    manga_id: manga_id,
    session_token: session_token,
    chapters_list_result: chapters_list_result,
    retry_delay: options[:force_delay],
    language: language,
  )
end

main

puts "Done."
