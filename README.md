# transmission-rpc

A Crystal client for the [Transmission](https://transmissionbt.com/) BitTorrent daemon's
[RPC API](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md).

It targets the **JSON-RPC 2.0** protocol introduced in Transmission 4.1.0, where method names and
fields use `snake_case`. It is built on [json-rpc](https://github.com/plambert/json-rpc.cr): a
custom transport handles Transmission's `X-Transmission-Session-Id` CSRF dance, and the JSON-RPC
client handles the envelope.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  transmission-rpc:
    github: plambert/transmission-rpc.cr
```

Then run `shards install`.

## Usage

```crystal
require "transmission-rpc"

client = Transmission::RPC::Client.new(
  "http://nas.local:9091/transmission/rpc",
  username: "admin", password: "secret")

# List torrents (parsed into Transmission::RPC::Torrent structs).
client.torrent_get.each do |torrent|
  puts "#{torrent.name} — #{torrent.state} — #{torrent.percent_done.try { |done| (done * 100).round(1) }}%"
end

# Add a torrent by magnet link, then start it.
added = client.torrent_add(filename: "magnet:?xt=urn:btih:...")
client.torrent_start([added.id])

# Throttle and label a torrent.
client.torrent_set([added.id], upload_limited: true, upload_limit: 50, labels: ["linux"])

# Session-wide stats and settings.
stats = client.session_stats
puts "#{stats.torrent_count} torrents, #{stats.download_speed} B/s down"
client.session_set(speed_limit_down: 1000, speed_limit_down_enabled: true)
```

The default endpoint is `http://localhost:9091/transmission/rpc`, so `Transmission::RPC::Client.new`
with no arguments talks to a local daemon.

## Selecting torrents

Methods that act on torrents accept an `ids` argument that may be:

- a single id (`Int`) or info hash (`String`) — wrapped into an array automatically,
- an array of ids/hashes,
- `nil` — meaning **all** torrents,
- or, for `torrent_get`, `recently_active: true` to fetch only recently active torrents.

## Implemented methods

| Category | Methods |
|---|---|
| Torrent actions | `torrent_start` (with `now:`), `torrent_stop`, `torrent_verify`, `torrent_reannounce` |
| Torrent data | `torrent_get`, `torrent_get_raw`, `torrent_set`, `torrent_add`, `torrent_remove`, `torrent_set_location`, `torrent_rename_path` |
| Queue | `queue_move_top`, `queue_move_up`, `queue_move_down`, `queue_move_bottom` |
| Session | `session_get`, `session_set`, `session_stats`, `session_close` |
| Server | `blocklist_update`, `port_test`, `free_space` |
| Bandwidth groups | `group_get`, `group_set` |

`torrent_get` returns `Array(Torrent)` for the common fields; use `torrent_get_raw` (returning
`JSON::Any`) for any field not on the struct. `session_get` and `group_get` return `JSON::Any`
because their field sets are large and version-dependent.

## Errors

- A JSON-RPC error from the daemon raises `JSON::RPC::Error` (`#code`, `#message`, `#data`).
- A transport failure (auth, connectivity, unexpected HTTP status) raises
  `JSON::RPC::TransportError`.

## Development

```bash
shards install
crystal spec -v --error-trace
crystal tool format
ameba
```

The specs use a recording transport for the client and a throwaway local HTTP server to exercise
the CSRF session-id negotiation — no live Transmission daemon required.

## License

MIT
