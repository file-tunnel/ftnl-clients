# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module FtnlClient
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(status, body)
      @status = status
      @body = body
      super("File Tunnel API returned HTTP #{status}: #{body}")
    end
  end

  class Client
    def initialize(base_url:, token: nil, open_timeout: 10, read_timeout: 30)
      @base_url = base_url.sub(%r{/+\z}, "")
      @token = token
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def request(method, path, body: nil)
      uri = URI("#{@base_url}/#{path.sub(%r{\A/+}, "")}")
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@token}" if @token
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(request) }
      raise ApiError.new(response.code.to_i, response.body.to_s) unless response.is_a?(Net::HTTPSuccess)
      response.body.to_s.empty? ? nil : JSON.parse(response.body)
    end

    def health
      request(:get, "/health")
    end
  end
end
