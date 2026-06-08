require "../spec_helper"

Spectator.describe Transmission::RPC::ClassicCodec do
  describe ".method_name" do
    it "hyphenates snake_case method names" do
      expect(Transmission::RPC::ClassicCodec.method_name("torrent_get")).to eq "torrent-get"
      expect(Transmission::RPC::ClassicCodec.method_name("torrent_start_now")).to eq "torrent-start-now"
    end
  end

  describe ".field_name" do
    it "camelCases snake_case field names" do
      expect(Transmission::RPC::ClassicCodec.field_name("hash_string")).to eq "hashString"
      expect(Transmission::RPC::ClassicCodec.field_name("percent_done")).to eq "percentDone"
      expect(Transmission::RPC::ClassicCodec.field_name("added_date")).to eq "addedDate"
      expect(Transmission::RPC::ClassicCodec.field_name("id")).to eq "id"
    end
  end

  describe ".argument_key" do
    it "hyphenates the common case" do
      expect(Transmission::RPC::ClassicCodec.argument_key("download_dir")).to eq "download-dir"
      expect(Transmission::RPC::ClassicCodec.argument_key("peer_limit")).to eq "peer-limit"
      expect(Transmission::RPC::ClassicCodec.argument_key("files_wanted")).to eq "files-wanted"
      expect(Transmission::RPC::ClassicCodec.argument_key("priority_high")).to eq "priority-high"
      expect(Transmission::RPC::ClassicCodec.argument_key("delete_local_data")).to eq "delete-local-data"
    end

    it "uses the camelCase exceptions where the spec demands them" do
      expect(Transmission::RPC::ClassicCodec.argument_key("bandwidth_priority")).to eq "bandwidthPriority"
      expect(Transmission::RPC::ClassicCodec.argument_key("upload_limit")).to eq "uploadLimit"
      expect(Transmission::RPC::ClassicCodec.argument_key("seed_ratio_limit")).to eq "seedRatioLimit"
      expect(Transmission::RPC::ClassicCodec.argument_key("queue_position")).to eq "queuePosition"
      expect(Transmission::RPC::ClassicCodec.argument_key("tracker_list")).to eq "trackerList"
    end

    it "passes protocol-neutral keys through unchanged" do
      %w[ids fields labels location metainfo filename cookies paused].each do |key|
        expect(Transmission::RPC::ClassicCodec.argument_key(key)).to eq key
      end
    end
  end

  describe ".snakecase_keys" do
    it "recursively rewrites camelCase and hyphenated keys, descending arrays and objects" do
      input = JSON.parse(%({"torrents":[{"hashString":"abc","percentDone":0.5,"peersSendingToUs":3}],"torrent-added":{"id":1}}))
      output = Transmission::RPC::ClassicCodec.snakecase_keys(input)
      expect(output["torrents"][0]["hash_string"].as_s).to eq "abc"
      expect(output["torrents"][0]["percent_done"].as_f).to eq 0.5
      expect(output["torrents"][0]["peers_sending_to_us"].as_i).to eq 3
      expect(output["torrent_added"]["id"].as_i).to eq 1
    end
  end
end

Spectator.describe Transmission::RPC::Client do
  describe "classic request envelope" do
    it "sends a hyphenated method, an arguments object, and a tag" do
      transport = RecordingTransport.new(%({"arguments":{"torrents":[]},"result":"success","tag":1}))
      classic_client_with(transport).torrent_get([1])

      expect(transport.last["method"].as_s).to eq "torrent-get"
      expect(transport.last.as_h.has_key?("arguments")).to be_true
      expect(transport.last.as_h.has_key?("tag")).to be_true
      expect(transport.last.as_h.has_key?("jsonrpc")).to be_false
      expect(transport.last_arguments["ids"].as_a.map(&.as_i)).to eq [1]
    end

    it "camelCases the fields array" do
      transport = RecordingTransport.new(%({"arguments":{"torrents":[]},"result":"success","tag":1}))
      classic_client_with(transport).torrent_get([1], fields: ["id", "hash_string", "percent_done", "added_date"])

      fields = transport.last_arguments["fields"].as_a.map(&.as_s)
      expect(fields).to eq ["id", "hashString", "percentDone", "addedDate"]
    end

    it "maps the recently_active selector to recently-active" do
      transport = RecordingTransport.new(%({"arguments":{"torrents":[]},"result":"success","tag":1}))
      classic_client_with(transport).torrent_get(recently_active: true)
      expect(transport.last_arguments["ids"].as_s).to eq "recently-active"
    end
  end

  describe "classic argument key translation" do
    it "translates torrent_set keys (hyphenated and camelCase)" do
      transport = RecordingTransport.new(%({"arguments":{},"result":"success","tag":1}))
      classic_client_with(transport).torrent_set([3],
        download_dir: "/data", upload_limit: 50, bandwidth_priority: 1, files_wanted: [0, 1])

      arguments = transport.last_arguments.as_h
      expect(arguments["download-dir"].as_s).to eq "/data"
      expect(arguments["uploadLimit"].as_i).to eq 50
      expect(arguments["bandwidthPriority"].as_i).to eq 1
      expect(arguments["files-wanted"].as_a.map(&.as_i)).to eq [0, 1]
      expect(arguments["ids"].as_a.map(&.as_i)).to eq [3]
    end

    it "translates torrent_remove's delete-local-data key" do
      transport = RecordingTransport.new(%({"arguments":{},"result":"success","tag":1}))
      classic_client_with(transport).torrent_remove([1], delete_local_data: true)
      expect(transport.last["method"].as_s).to eq "torrent-remove"
      expect(transport.last_arguments["delete-local-data"].as_bool).to be_true
    end
  end

  describe "classic response parsing" do
    it "parses a camelCase torrents response into snake_case Torrent structs" do
      transport = RecordingTransport.new(
        %({"arguments":{"torrents":[{"id":1,"name":"Ubuntu","status":4,"hashString":"deadbeef","percentDone":0.5,"uploadRatio":1.2,"peersSendingToUs":7,"addedDate":1700000000,"isPrivate":true}]},"result":"success","tag":1}))
      torrents = classic_client_with(transport).torrent_get([1])

      expect(torrents.size).to eq 1
      torrent = torrents.first
      expect(torrent.name).to eq "Ubuntu"
      expect(torrent.hash_string).to eq "deadbeef"
      expect(torrent.percent_done).to eq 0.5
      expect(torrent.upload_ratio).to eq 1.2
      expect(torrent.peers_sending_to_us).to eq 7
      expect(torrent.added_date).to eq 1700000000
      expect(torrent.is_private).to be_true
      expect(torrent.state).to eq Transmission::RPC::Status::Download
    end

    it "parses a classic torrent-added result" do
      transport = RecordingTransport.new(
        %({"arguments":{"torrent-added":{"id":9,"name":"foo","hashString":"abc"}},"result":"success","tag":1}))
      added = classic_client_with(transport).torrent_add(filename: "magnet:?xt=...")
      expect(added.id).to eq 9
      expect(added.name).to eq "foo"
      expect(added.hash_string).to eq "abc"
      expect(added.duplicate?).to be_false
    end

    it "flags a classic torrent-duplicate result" do
      transport = RecordingTransport.new(
        %({"arguments":{"torrent-duplicate":{"id":9,"name":"foo","hashString":"abc"}},"result":"success","tag":1}))
      added = classic_client_with(transport).torrent_add(metainfo: "base64data")
      expect(added.duplicate?).to be_true
      expect(added.name).to eq "foo"
    end

    it "parses session_stats from a camelCase response" do
      transport = RecordingTransport.new(
        %({"arguments":{"torrentCount":5,"downloadSpeed":1000,"cumulative-stats":{"uploadedBytes":42}},"result":"success","tag":1}))
      stats = classic_client_with(transport).session_stats
      expect(transport.last["method"].as_s).to eq "session-stats"
      expect(stats.torrent_count).to eq 5
      expect(stats.download_speed).to eq 1000
      expect(stats.cumulative_stats.try(&.uploaded_bytes)).to eq 42
    end
  end

  describe "classic error handling" do
    it "raises when result is not success" do
      transport = RecordingTransport.new(%({"arguments":{},"result":"method name not recognized","tag":1}))
      expect { classic_client_with(transport).session_stats }.to raise_error(JSON::RPC::Error, /method name not recognized/)
    end
  end

  describe "auto-detection" do
    it "selects Classic when the probe returns a classic not-recognized envelope" do
      transport = SequencedTransport.new([
        %({"arguments":{},"result":"method name not recognized"}),
        %({"arguments":{"torrents":[]},"result":"success","tag":2}),
      ])
      client = Transmission::RPC::Client.new(JSON::RPC::Client.new(transport))
      client.torrent_get

      expect(client.resolved_protocol).to eq Transmission::RPC::Protocol::Classic
      # First request is the modern-shaped probe...
      expect(transport.request(0)["jsonrpc"].as_s).to eq "2.0"
      expect(transport.request(0)["method"].as_s).to eq "session_get"
      # ...the real call goes out as classic.
      expect(transport.request(1)["method"].as_s).to eq "torrent-get"
    end

    it "selects Modern when the probe returns a JSON-RPC 2.0 envelope" do
      transport = SequencedTransport.new([
        %({"jsonrpc":"2.0","result":{},"id":0}),
        %({"jsonrpc":"2.0","result":{"torrents":[]},"id":1}),
      ])
      client = Transmission::RPC::Client.new(JSON::RPC::Client.new(transport))
      client.torrent_get

      expect(client.resolved_protocol).to eq Transmission::RPC::Protocol::Modern
      expect(transport.request(1)["method"].as_s).to eq "torrent_get"
      expect(transport.request(1).as_h.has_key?("params")).to be_true
    end

    it "probes only once and caches the result" do
      transport = SequencedTransport.new([
        %({"arguments":{},"result":"method name not recognized"}),
        %({"arguments":{"torrents":[]},"result":"success","tag":2}),
        %({"arguments":{"torrents":[]},"result":"success","tag":3}),
      ])
      client = Transmission::RPC::Client.new(JSON::RPC::Client.new(transport))
      client.torrent_get
      client.torrent_get

      # One probe + two real calls == three requests total.
      expect(transport.bodies.size).to eq 3
    end
  end
end
