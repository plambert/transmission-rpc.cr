require "../spec_helper"

Spectator.describe Transmission::RPC::Client do
  describe "#torrent_get" do
    it "requests fields and parses torrents into structs" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"torrents":[{"id":1,"name":"Ubuntu ISO","status":4}]},"id":1}))
      torrents = client_with(transport).torrent_get([1])

      expect(transport.last_method).to eq "torrent_get"
      expect(transport.last_params["ids"].as_a.map(&.as_i)).to eq [1]
      expect(transport.last_params["fields"].as_a).not_to be_empty

      expect(torrents.size).to eq 1
      expect(torrents.first.name).to eq "Ubuntu ISO"
      expect(torrents.first.state).to eq Transmission::RPC::Status::Download
    end

    it "wraps a scalar id into an array" do
      transport = RecordingTransport.new(%({"jsonrpc":"2.0","result":{"torrents":[]},"id":1}))
      client_with(transport).torrent_get(7)
      expect(transport.last_params["ids"].as_a.map(&.as_i)).to eq [7]
    end

    it "omits ids when none are given (all torrents)" do
      transport = RecordingTransport.new(%({"jsonrpc":"2.0","result":{"torrents":[]},"id":1}))
      client_with(transport).torrent_get
      expect(transport.last_params.as_h.has_key?("ids")).to be_false
    end

    it "sends the recently_active selector" do
      transport = RecordingTransport.new(%({"jsonrpc":"2.0","result":{"torrents":[]},"id":1}))
      client_with(transport).torrent_get(recently_active: true)
      expect(transport.last_params["ids"].as_s).to eq "recently_active"
    end
  end

  describe "#torrent_get table format" do
    it "requests format table and reassembles rows into torrents" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"torrents":[["id","name","status"],[1,"Ubuntu",4],[2,"Debian",6]]},"id":1}))
      torrents = client_with(transport).torrent_get(fields: ["id", "name", "status"], table: true)

      expect(transport.last_params["format"].as_s).to eq "table"
      expect(torrents.size).to eq 2
      expect(torrents.first.id).to eq 1
      expect(torrents.first.name).to eq "Ubuntu"
      expect(torrents[1].status).to eq 6
    end
  end

  describe "#torrent_start" do
    it "uses torrent_start by default" do
      transport = RecordingTransport.new
      client_with(transport).torrent_start([1, 2])
      expect(transport.last_method).to eq "torrent_start"
      expect(transport.last_params["ids"].as_a.map(&.as_i)).to eq [1, 2]
    end

    it "uses torrent_start_now when now: true" do
      transport = RecordingTransport.new
      client_with(transport).torrent_start([1], now: true)
      expect(transport.last_method).to eq "torrent_start_now"
    end
  end

  describe "#torrent_set" do
    it "passes mutable fields alongside ids" do
      transport = RecordingTransport.new
      client_with(transport).torrent_set([3], labels: ["linux"], upload_limited: true, upload_limit: 50)
      expect(transport.last_method).to eq "torrent_set"
      expect(transport.last_params["ids"].as_a.map(&.as_i)).to eq [3]
      expect(transport.last_params["labels"].as_a.map(&.as_s)).to eq ["linux"]
      expect(transport.last_params["upload_limited"].as_bool).to be_true
      expect(transport.last_params["upload_limit"].as_i).to eq 50
    end
  end

  describe "#torrent_add" do
    it "requires filename or metainfo" do
      transport = RecordingTransport.new
      expect { client_with(transport).torrent_add }.to raise_error(ArgumentError, /filename or metainfo/)
    end

    it "parses a torrent_added result" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"torrent_added":{"id":9,"name":"foo","hash_string":"abc"}},"id":1}))
      added = client_with(transport).torrent_add(filename: "magnet:?xt=...")
      expect(transport.last_params["filename"].as_s).to start_with("magnet:")
      expect(added.id).to eq 9
      expect(added.duplicate?).to be_false
    end

    it "flags a duplicate result" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"torrent_duplicate":{"id":9,"name":"foo","hash_string":"abc"}},"id":1}))
      added = client_with(transport).torrent_add(metainfo: "base64data")
      expect(added.duplicate?).to be_true
      expect(added.name).to eq "foo"
    end
  end

  describe "#torrent_remove" do
    it "passes delete_local_data" do
      transport = RecordingTransport.new
      client_with(transport).torrent_remove([1], delete_local_data: true)
      expect(transport.last_method).to eq "torrent_remove"
      expect(transport.last_params["delete_local_data"].as_bool).to be_true
    end
  end

  describe "#torrent_set_location" do
    it "sends location and move" do
      transport = RecordingTransport.new
      client_with(transport).torrent_set_location([1], "/data/done", move: true)
      expect(transport.last_params["location"].as_s).to eq "/data/done"
      expect(transport.last_params["move"].as_bool).to be_true
    end
  end

  describe "#session_stats" do
    it "parses statistics" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"torrent_count":5,"download_speed":1000,"cumulative_stats":{"uploaded_bytes":42}},"id":1}))
      stats = client_with(transport).session_stats
      expect(transport.last_method).to eq "session_stats"
      expect(stats.torrent_count).to eq 5
      expect(stats.download_speed).to eq 1000
      expect(stats.cumulative_stats.try(&.uploaded_bytes)).to eq 42
    end
  end

  describe "#free_space" do
    it "parses free and total space" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"path":"/data","size_bytes":100,"total_size":500},"id":1}))
      space = client_with(transport).free_space("/data")
      expect(transport.last_params["path"].as_s).to eq "/data"
      expect(space.size_bytes).to eq 100
      expect(space.total_size).to eq 500
    end
  end

  describe "#port_test" do
    it "parses the open state" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","result":{"port_is_open":true,"ip_protocol":"ipv4"},"id":1}))
      result = client_with(transport).port_test("ipv4")
      expect(result.port_is_open?).to be_true
      expect(result.ip_protocol).to eq "ipv4"
    end
  end

  describe "#blocklist_update" do
    it "returns the new blocklist size" do
      transport = RecordingTransport.new(%({"jsonrpc":"2.0","result":{"blocklist_size":1234},"id":1}))
      expect(client_with(transport).blocklist_update).to eq 1234
    end
  end

  describe "#session_set" do
    it "passes settings through" do
      transport = RecordingTransport.new
      client_with(transport).session_set(speed_limit_down: 100, speed_limit_down_enabled: true)
      expect(transport.last_method).to eq "session_set"
      expect(transport.last_params["speed_limit_down"].as_i).to eq 100
      expect(transport.last_params["speed_limit_down_enabled"].as_bool).to be_true
    end
  end

  describe "#queue_move_top" do
    it "sends the queue method with ids" do
      transport = RecordingTransport.new
      client_with(transport).queue_move_top([4])
      expect(transport.last_method).to eq "queue_move_top"
      expect(transport.last_params["ids"].as_a.map(&.as_i)).to eq [4]
    end
  end

  describe "error handling" do
    it "raises JSON::RPC::Error on a JSON-RPC error" do
      transport = RecordingTransport.new(
        %({"jsonrpc":"2.0","error":{"code":-32601,"message":"no such method"},"id":1}))
      expect { client_with(transport).session_stats }.to raise_error(JSON::RPC::Error, /no such method/)
    end
  end
end
