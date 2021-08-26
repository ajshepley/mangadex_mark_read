# frozen_string_literal: true

require "net/http"
require "uri"

# Just a couple of simple http operations.
module DexHttp
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

  # TODO: Maybe support redirects, etc. Need a reason before bothering to do so.
end
