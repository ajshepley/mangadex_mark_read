# frozen_string_literal: true

require_relative "dex_http.rb"

# See https://api.mangadex.org/docs.html
module DexApi
  class Client
    include DexHttp

    API_BASE_URL = "https://api.mangadex.org"

    JSON_TYPE_HEADER = { "Content-Type": "application/json;charset=utf-8" }

    class << self
      def get
        @client ||= new
      end
    end

    def login(username:, password:)
      headers = JSON_TYPE_HEADER
      body = {
        username: username,
        password: password,
      }
      url = API_BASE_URL + "/auth/login"

      post(url: url, body: body, headers: headers)
    end

    def get_manga_volumes_and_chapters(manga_id:, token:)
      headers = JSON_TYPE_HEADER.merge({
        Authorization: "Bearer #{token}",
      })

      url = API_BASE_URL + "/manga/#{manga_id}/aggregate"

      get(url: url, headers: headers)
    end

    # https://api.mangadex.org/docs.html#operation/get-chapter
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
  end
end
