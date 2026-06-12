require "../spec_helper"

Spectator.describe Transmission::RPC::Torrent do
  it "deserializes the trackers array" do
    json = <<-JSON
      {
        "id": 1,
        "trackers": [
          {"announce": "https://tracker.example.com:443/announce", "tier": 0, "id": 5, "scrape": "https://tracker.example.com:443/scrape", "sitename": "example"},
          {"announce": "udp://open.demonii.com:1337/announce", "tier": 1, "id": 6}
        ]
      }
      JSON
    torrent = Transmission::RPC::Torrent.from_json(json)
    trackers = torrent.trackers || raise "expected trackers"
    expect(trackers.size).to eq 2
    expect(trackers[0].announce).to eq "https://tracker.example.com:443/announce"
    expect(trackers[0].sitename).to eq "example"
    expect(trackers[1].tier).to eq 1
  end

  it "is nil when trackers were not requested" do
    expect(Transmission::RPC::Torrent.from_json(%({"id": 1})).trackers).to be_nil
  end

  it "deserializes the tracker_stats array" do
    json = <<-JSON
      {
        "id": 1,
        "tracker_stats": [
          {"announce": "https://tracker.example.com:443/announce", "host": "tracker.example.com",
           "seeder_count": 4, "leecher_count": 2, "download_count": -1,
           "last_scrape_time": 1765000000, "last_scrape_succeeded": true}
        ]
      }
      JSON
    stats = Transmission::RPC::Torrent.from_json(json).tracker_stats || raise "expected tracker_stats"
    expect(stats.size).to eq 1
    expect(stats[0].seeder_count).to eq 4
    expect(stats[0].leecher_count).to eq 2
    expect(stats[0].download_count).to eq -1
    expect(stats[0].last_scrape_time).to eq 1_765_000_000_i64
    expect(stats[0].last_scrape_succeeded).to be_true
  end

  it "leaves tracker_stats nil when not requested" do
    expect(Transmission::RPC::Torrent.from_json(%({"id": 1})).tracker_stats).to be_nil
  end
end

Spectator.describe Transmission::RPC::Tracker do
  it "extracts the host from the announce URL" do
    tracker = Transmission::RPC::Tracker.from_json(%({"announce": "https://tracker.example.com:443/announce"}))
    expect(tracker.host).to eq "tracker.example.com"
  end

  it "handles a udp announce URL" do
    tracker = Transmission::RPC::Tracker.from_json(%({"announce": "udp://open.demonii.com:1337/announce"}))
    expect(tracker.host).to eq "open.demonii.com"
  end

  it "returns nil when there is no announce" do
    expect(Transmission::RPC::Tracker.from_json(%({"tier": 0})).host).to be_nil
  end
end
