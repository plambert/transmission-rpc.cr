require "json-rpc"

module Transmission::RPC
  # The HTTP transport for Transmission's RPC endpoint.
  #
  # Transmission guards its RPC endpoint with a CSRF token. The first request
  # (and any request after the token rotates) is answered with `409 Conflict`
  # and the correct token in the `X-Transmission-Session-Id` header. This
  # transport captures that token and transparently replays the request, so
  # callers never see the 409.
  class SessionTransport < JSON::RPC::HTTPTransport
    # The header Transmission uses to carry its CSRF token.
    SESSION_HEADER = "X-Transmission-Session-Id"

    # The most recently negotiated session token, if any.
    getter session_id : String?

    def call(body : String) : String
      response = post(body)

      if response.status_code == 409 && (token = response.headers[SESSION_HEADER]?)
        @session_id = token
        @headers[SESSION_HEADER] = token
        response = post(body)
      end

      unless response.success?
        raise JSON::RPC::TransportError.new(
          "Transmission RPC returned HTTP #{response.status_code} #{response.status.description}",
          response.status_code,
        )
      end

      response.body
    end
  end
end
