require "spectator"
require "../src/transmission-rpc"

# A JSON-RPC transport that records every request body and replies with a
# canned response, so client methods can be tested without a live daemon.
class RecordingTransport < JSON::RPC::Transport
  getter bodies = [] of String
  property response : String

  def initialize(@response : String = %({"jsonrpc":"2.0","result":{},"id":1}))
  end

  def call(body : String) : String
    @bodies << body
    @response
  end

  # The most recently sent request body, parsed as JSON.
  def last : JSON::Any
    JSON.parse(@bodies.last? || raise "no request has been sent")
  end

  # The `method` member of the most recent request.
  def last_method : String
    last["method"].as_s
  end

  # The `params` member of the most recent request.
  def last_params : JSON::Any
    last["params"]
  end
end

# Builds a Transmission client wired to a {RecordingTransport}.
def client_with(transport : RecordingTransport) : Transmission::RPC::Client
  Transmission::RPC::Client.new(JSON::RPC::Client.new(transport))
end
