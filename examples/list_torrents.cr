# A tiny example: connect to a Transmission daemon and print its torrents.
#
# Usage:
#   crystal run examples/list_torrents.cr -- [URL] [USERNAME] [PASSWORD]
#
# URL defaults to http://localhost:9091/transmission/rpc.

require "../src/transmission-rpc"

url = ARGV[0]? || Transmission::RPC::Client::DEFAULT_URL
username = ARGV[1]?
password = ARGV[2]?

client = Transmission::RPC::Client.new(url, username: username, password: password)

stats = client.session_stats
puts "#{stats.torrent_count} torrents — #{stats.download_speed} B/s down, #{stats.upload_speed} B/s up"
puts

client.torrent_get.each do |torrent|
  percent = torrent.percent_done.try { |done| (done * 100).round(1) } || 0.0
  printf "%6s  %-6s %5.1f%%  %s\n", torrent.id, torrent.state, percent, torrent.name
end
