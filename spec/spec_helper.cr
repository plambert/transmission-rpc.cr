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

  # The `arguments` member of the most recent request (classic envelope).
  def last_arguments : JSON::Any
    last["arguments"]
  end

  # The `tag` member of the most recent request (classic envelope).
  def last_tag : Int64
    last["tag"].as_i64
  end
end

# A recording transport whose response can change between calls, so a probe
# response and the subsequent real response can be distinguished. Returns the
# next queued response, repeating the last one once the queue is drained.
class SequencedTransport < JSON::RPC::Transport
  getter bodies = [] of String

  def initialize(@responses : Array(String))
  end

  def call(body : String) : String
    @bodies << body
    index = @bodies.size - 1
    @responses[index]? || @responses.last
  end

  def last : JSON::Any
    JSON.parse(@bodies.last? || raise "no request has been sent")
  end

  def request(index : Int32) : JSON::Any
    JSON.parse(@bodies[index])
  end
end

# Builds a Transmission client wired to a {RecordingTransport}, forcing the
# modern dialect by default (the historical behavior of these specs).
def client_with(transport : RecordingTransport, protocol : Transmission::RPC::Protocol = Transmission::RPC::Protocol::Modern) : Transmission::RPC::Client
  Transmission::RPC::Client.new(JSON::RPC::Client.new(transport), protocol: protocol)
end

# Builds a Transmission client forced into the classic dialect, wired to a
# {RecordingTransport}.
def classic_client_with(transport : RecordingTransport) : Transmission::RPC::Client
  Transmission::RPC::Client.new(JSON::RPC::Client.new(transport), protocol: Transmission::RPC::Protocol::Classic)
end
