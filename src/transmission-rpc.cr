# A Crystal client for the Transmission BitTorrent RPC API.
#
# Targets the JSON-RPC 2.0 protocol introduced in Transmission 4.1.0
# (`snake_case` method names and fields). The entrypoint is
# {Transmission::RPC::Client}.
module Transmission::RPC
end

require "./transmission-rpc/version"
require "./transmission-rpc/models"
require "./transmission-rpc/session_transport"
require "./transmission-rpc/client"
