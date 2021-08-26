# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "byebug"
require "getoptlong"

# See https://api.mangadex.org/docs.html#section/Rate-limits
MAX_REQUESTS_PER_SECOND = 5
REFRESH_INTERVAL_SECONDS = 1.1

API_BASE_URL = "https://api.mangadex.org"

# e.g. https://mangadex.org/title/4fd4f8c0-fab8-4ee5-ab9e-5907720afed9/verndio-surreal-sword-saga
MANGA_ID_URL_PATTERN = %r{\Ahttps://mangadex\.org/title/([^/]+)/([^/]+)}

JSON_TYPE_HEADER = { "Content-Type": "application/json;charset=utf-8" }
JSON_RESPONSE_HEADER = { "Accept" => "application/json" }

#### Mangadex Operations

# See https://api.mangadex.org/docs.html

def login(username:, password:)
  headers = JSON_TYPE_HEADER
  body = {
    username: username,
    password: password,
  }
  url = API_BASE_URL + "/auth/login"

  post(url: url, body: body, headers: headers)
end

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

def get_manga_volumes_and_chapters(manga_id:, token:)
  headers = JSON_TYPE_HEADER.merge({
    Authorization: "Bearer #{token}",
  })

  url = API_BASE_URL + "/manga/#{manga_id}/aggregate"

  get(url: url, headers: headers)
end

# TODO: Loop with limit, rate limit
# https://api.mangadex.org/docs.html#operation/get-author
def get_chapters_list(manga_id:, translated_language:)
  headers = JSON_TYPE_HEADER
  url = API_BASE_URL + "/chapter"
  params = {
    limit: 100,
    # offset: n,
    # order: { chapter: 'asc' } # we can manually sort for now
    manga: manga_id,
    "translatedLanguage[]" => translated_language,
  }

  get(url: url, headers: headers, query_params: params)
end

def get_read_markers(manga_id:, token:)
  headers = JSON_TYPE_HEADER.merge({
    Authorization: "Bearer #{token}",
  })

  url = API_BASE_URL + "/manga/#{manga_id}/read"

  get(url: url, headers: headers)
end

# Extra headers captured from using the web buttons to mark as read.
# May be unnecessary but it feels like they made things a bit more reliable. 🤷‍♀️
def mark_chapter_read(chapter_id:, token:)
  headers = JSON_TYPE_HEADER.merge({
    Authorization: "Bearer #{token}",
    # TE: "Trailers",
    # Origin: "https://mangadex.org",
    # Referer: "https://mangadex.org/",
    # Host: "api.mangadex.org",
    # "User-Agent" => "application/json;charset=utf-8",
    Origin: "https://mangadex.org",
    Connection: "keep-alive",
    "Sec-Fetch-Dest" => "empty",
    "Sec-Fetch-Mode" => "cors",
    "Sec-Fetch-Site" => "same-site",
    TE: "trailers",
  })

  url = API_BASE_URL + "/chapter/#{chapter_id}/read"

  post(url: url, body: {}, headers: headers)
end

#### HTTP Methods

def get(url:, headers:, query_params: nil)
  uri = URI.parse(url)
  uri.query = URI.encode_www_form(query_params) if query_params

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri.request_uri, headers)

  http.request(request)
end

def post(url:, body:, headers:, query_params: nil)
  uri = URI.parse(url)
  uri.query = URI.encode_www_form(query_params) if query_params

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri, headers)
  request.body = body.to_json if body

  http.request(request)
end

#### Logic

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

#### Main

opts = GetoptLong.new(
  ["--manga_id", "-m", GetoptLong::OPTIONAL_ARGUMENT],
  ["--username", "-u", GetoptLong::OPTIONAL_ARGUMENT],
  ["--password", "-p", GetoptLong::OPTIONAL_ARGUMENT],
  ["--url", "-l", GetoptLong::OPTIONAL_ARGUMENT],
  ["--token", "-t", GetoptLong::OPTIONAL_ARGUMENT],
  ["--print-token", "-d", GetoptLong::NO_ARGUMENT],
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
     "Read chapters size: #{read_chapters.size}."

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

puts "Done."

# TODO: This doesn't seem to mark the Eye as closed. What is the difference compared to clicking the button in the browser?
# Also, the results from read_chapters_Results are different than expected?
## Actually, it looks like the recent "desktop view" change made this behave properly.
