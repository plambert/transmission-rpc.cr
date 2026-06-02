require "../spec_helper"
require "http/server"

Spectator.describe Transmission::RPC::SessionTransport do
  # Spins up a throwaway HTTP server that mimics Transmission's CSRF behavior:
  # the first request without the session header gets a 409 plus the token;
  # subsequent requests carrying the token succeed.
  def with_server(& : String ->) : Nil
    token = "test-session-token"
    requests = [] of HTTP::Request
    server = HTTP::Server.new do |context|
      requests << context.request
      if context.request.headers["X-Transmission-Session-Id"]? == token
        context.response.status = HTTP::Status::OK
        context.response.print %({"jsonrpc":"2.0","result":{"ok":true},"id":1})
      else
        context.response.status = HTTP::Status::CONFLICT
        context.response.headers["X-Transmission-Session-Id"] = token
        context.response.print "CSRF token required"
      end
    end

    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      yield "http://#{address}/transmission/rpc"
    ensure
      server.close
    end
  end

  it "negotiates the session id on 409 and retries transparently" do
    with_server do |url|
      transport = Transmission::RPC::SessionTransport.new(url)
      body = transport.call(%({"jsonrpc":"2.0","method":"session_stats","id":1}))
      expect(JSON.parse(body)["result"]["ok"].as_bool).to be_true
      expect(transport.session_id).to eq "test-session-token"
    end
  end

  it "drives a full client call through the negotiation" do
    with_server do |url|
      client = Transmission::RPC::Client.new(url)
      stats = client.session_stats
      expect(stats).to be_a(Transmission::RPC::SessionStats)
    end
  end
end
