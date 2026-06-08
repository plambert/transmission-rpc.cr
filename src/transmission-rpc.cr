# A Crystal client for the Transmission BitTorrent RPC API.
#
# Speaks both Transmission dialects: the JSON-RPC 2.0 *modern* protocol of
# 4.1.0+ (`snake_case` method names and fields) and the original *classic*
# protocol understood by every version (and the only one 4.0.x speaks). The
# dialect is auto-detected by default; see {Protocol}. The entrypoint is
# {Transmission::RPC::Client}.
module Transmission::RPC
end

require "./transmission-rpc/version"
require "./transmission-rpc/protocol"
require "./transmission-rpc/models"
require "./transmission-rpc/session_transport"
require "./transmission-rpc/client"
