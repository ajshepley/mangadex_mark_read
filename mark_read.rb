# frozen_string_literal: true

require "json"
require "getoptlong"
require_relative "lib/dex_http.rb"
require_relative "lib/dex_api.rb"

include DexHttp
include DexApi

# See https://api.mangadex.org/docs.html#section/Rate-limits
MAX_REQUESTS_PER_SECOND = 5
REFRESH_INTERVAL_SECONDS = 1.1

# e.g. https://mangadex.org/title/4fd4f8c0-fab8-4ee5-ab9e-5907720afed9/verndio-surreal-sword-saga
MANGA_ID_URL_PATTERN = %r{\Ahttps://mangadex\.org/title/([^/]+)/([^/]+)}

def get_login_session_token(username:, password:)
  unless username && !username.empty? && password && !password.empty?
    puts "A valid username and password are needed. Aborting."
    exit(1)
  end

  login_result = login(username: username, password: password)
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
    result = mark_chapter_read(chapter_id: chapter_id, token: token)

    puts "Result for chapter #{chapter_id} at index #{index} is #{result}"
  end
end

def sleep_and_log(sleep_time_seconds: 1)
  puts "Sleeping for #{sleep_time_seconds} to refresh API usage."
  sleep(sleep_time_seconds)
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
  HELP
end

def main
  # TODO: Convert to OptionParser and delete print_help
  opts = GetoptLong.new(
    ["--manga_id", "-m", GetoptLong::REQUIRED_ARGUMENT],
    ["--username", "-u", GetoptLong::REQUIRED_ARGUMENT],
    ["--password", "-p", GetoptLong::REQUIRED_ARGUMENT],
    ["--url", "-r", GetoptLong::REQUIRED_ARGUMENT],
    ["--token", "-t", GetoptLong::REQUIRED_ARGUMENT],
    ["--print-token", "-d", GetoptLong::NO_ARGUMENT],
    ["--language", "-l", GetoptLong::OPTIONAL_ARGUMENT],
    ["--help", "-h", GetoptLong::NO_ARGUMENT],
  )

  username = nil
  password = nil
  translated_language = "en"
  manga_id = nil
  manga_url = nil
  session_token = nil
  print_token = false

  opts.each do |opt, arg|
    case opt
    when "--username"
      username = arg
    when "--password"
      password = arg
    when "--manga_id"
      manga_id = arg
    when "--url"
      manga_url = arg
    when "--token"
      session_token = arg
    when "--print-token"
      print_token = true
    when "--language"
      translated_language = arg if arg
    when "--help"
      puts help_message
      exit(0)
    end
  end

  manga_id ||= parse_manga_id(manga_url: manga_url)

  unless manga_id
    puts "No --manga_id provided. Aborting."
    exit(1)
  end

  session_token ||= get_login_session_token(username: username, password: password)

  unless session_token
    puts "Failed to get session token. Response body: #{result_body}"
    exit(1)
  end

  puts "Token is: #{session_token}" if print_token

  # manga = get_manga_volumes_and_chapters(manga_id: manga_id, session_token: session_token)
  chapters_list_result = get_chapters_list(manga_id: manga_id, translated_language: translated_language)
  read_chapters_result = get_read_markers(manga_id: manga_id, token: session_token)

  chapter_list = JSON.parse(chapters_list_result.body).dig("results")
  read_chapters = JSON.parse(read_chapters_result.body).dig("data")

  # Let API quota refresh a bit.
  sleep(REFRESH_INTERVAL_SECONDS)

  chapter_ids_to_mark = parse_chapter_ids_to_mark(total_chapter_list: chapter_list, read_chapters: read_chapters)

  puts "Marking #{chapter_ids_to_mark.size} chapters as read out of #{chapter_list.size} chapters. "\
      "User's total read chapters size (all languages): #{read_chapters.size}."

  # TODO: Mangadex will sometimes return 200 but fail to mark some chapters as read.
  mark_as_read(
    chapter_ids: chapter_ids_to_mark,
    max_requests_per_second: MAX_REQUESTS_PER_SECOND,
    refresh_interval_seconds: REFRESH_INTERVAL_SECONDS,
    token: session_token,
  )

  # TODO: use result of get_chapters_list with /chapter/id/read
  ## Has extra rate limits (300 per 10 minutes on top of 5 per second max.)
  ## Exclude read chapters
  # TODO: This doesn't seem to mark the Eye as closed. What is the difference compared to clicking the button in the browser?
  # Also, the results from read_chapters_Results are different than expected?
  ## Actually, it looks like the recent "desktop view" change made this behave properly.
end

main

puts "Done."
