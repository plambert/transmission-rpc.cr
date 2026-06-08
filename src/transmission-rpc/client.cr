require "json"
require "json-rpc"
require "./session_transport"
require "./protocol"
require "./models"

module Transmission::RPC
  # A client for the Transmission BitTorrent RPC API.
  #
  # Speaks both Transmission dialects (see {Protocol}): the JSON-RPC 2.0
  # *modern* protocol of 4.1.0+ and the *classic* protocol understood by every
  # version (the only one 4.0.x speaks). The public API is `snake_case`
  # throughout regardless of dialect; classic translation happens internally
  # via {ClassicCodec}.
  #
  # By default the client auto-detects the daemon's dialect on its first call
  # (probing once and caching the result). Pass `protocol:` to force one.
  #
  # Built on [json-rpc](https://github.com/plambert/json-rpc.cr): a
  # {SessionTransport} handles the `X-Transmission-Session-Id` CSRF dance
  # (shared by both dialects), and a `JSON::RPC::Client` handles the modern
  # envelope.
  #
  # ```
  # client = Transmission::RPC::Client.new(
  #   "http://nas.local:9091/transmission/rpc",
  #   username: "admin", password: "secret")
  #
  # client.torrent_get.each do |torrent|
  #   puts "#{torrent.name}: #{torrent.state}"
  # end
  # ```
  class Client
    # The default RPC endpoint exposed by a stock Transmission daemon.
    DEFAULT_URL = "http://localhost:9091/transmission/rpc"

    # A sensible default set of fields to request from `torrent_get`. Covers
    # everything in the {Torrent} struct's commonly used attributes.
    DEFAULT_FIELDS = %w[
      id hashString name status totalSize sizeWhenDone leftUntilDone
      percentDone percentComplete metadataPercentComplete recheckProgress
      rateDownload rateUpload eta uploadRatio uploadedEver downloadedEver
      seedRatioLimit seedRatioMode bandwidthPriority queuePosition
      peersConnected downloadDir isFinished isStalled isPrivate error
      errorString labels addedDate doneDate startDate activityDate
    ].map { |field| field.gsub(/[A-Z]/) { |match| "_#{match.downcase}" } }

    # The underlying JSON-RPC client.
    getter rpc : JSON::RPC::Client

    # The configured protocol mode. {Protocol::Auto} resolves to {Protocol::Modern}
    # or {Protocol::Classic} on the first call.
    getter protocol : Protocol

    # The dialect resolved by auto-detection, or `nil` until the first call
    # under {Protocol::Auto}. When `protocol` is forced this mirrors it.
    getter resolved_protocol : Protocol?

    # A monotonic counter for the classic `tag` member.
    @tag_counter = Atomic(Int64).new(0)

    # Builds a client speaking to `url`, optionally with HTTP Basic auth.
    #
    # `protocol` selects the dialect; the default {Protocol::Auto} probes the
    # daemon on first use.
    def initialize(url : String | URI, *, username : String? = nil, password : String? = nil, @protocol : Protocol = Protocol::Auto)
      transport = SessionTransport.new(url)
      transport.basic_auth(username, password) if username && password
      @rpc = JSON::RPC::Client.new(transport)
      @resolved_protocol = @protocol unless @protocol.auto?
    end

    # Builds a client speaking to {DEFAULT_URL}, optionally with HTTP Basic
    # auth. (Separate from the `url` overload so the JSON-RPC-client injection
    # overload below stays unambiguous.)
    def self.new(*, username : String? = nil, password : String? = nil, protocol : Protocol = Protocol::Auto) : self
      new(DEFAULT_URL, username: username, password: password, protocol: protocol)
    end

    # Builds a client over an existing JSON-RPC client. Useful for injecting a
    # custom or stubbed transport.
    def initialize(@rpc : JSON::RPC::Client, *, @protocol : Protocol = Protocol::Auto)
      @resolved_protocol = @protocol unless @protocol.auto?
    end

    # --- Torrent actions -------------------------------------------------

    # Starts the given torrents (all torrents when `ids` is `nil`). With
    # `now: true`, bypasses the download queue (`torrent_start_now`).
    def torrent_start(ids = nil, *, now : Bool = false) : Nil
      call(now ? "torrent_start_now" : "torrent_start", ids_arguments(ids))
    end

    # Stops the given torrents (all torrents when `ids` is `nil`).
    def torrent_stop(ids = nil) : Nil
      call("torrent_stop", ids_arguments(ids))
    end

    # Verifies the local data of the given torrents.
    def torrent_verify(ids = nil) : Nil
      call("torrent_verify", ids_arguments(ids))
    end

    # Asks the given torrents to re-announce to their trackers immediately.
    def torrent_reannounce(ids = nil) : Nil
      call("torrent_reannounce", ids_arguments(ids))
    end

    # --- Torrent accessors / mutators ------------------------------------

    # Retrieves torrents, parsed into {Torrent} structs.
    #
    # - `ids`: a single id/hash, an array of them, or `nil` for all torrents.
    # - `fields`: the fields to fetch (defaults to {DEFAULT_FIELDS}).
    # - `recently_active: true`: fetch only recently active torrents.
    # - `table: true`: request the compact `"table"` response format (arrays
    #   instead of per-field objects) — a smaller payload for large result
    #   sets. The rows are reassembled into {Torrent}s transparently.
    def torrent_get(ids = nil, fields : Array(String) = DEFAULT_FIELDS, *, recently_active : Bool = false, table : Bool = false) : Array(Torrent)
      entries = torrent_get_raw(ids, fields, recently_active: recently_active, table: table)["torrents"].as_a
      table ? torrents_from_table(entries) : entries.map { |entry| Torrent.from_json(entry.to_json) }
    end

    # Like {#torrent_get} but returns the raw `JSON::Any` result, for fields
    # not covered by the {Torrent} struct. With `table: true` the `torrents`
    # member is in Transmission's table layout (a header row followed by value
    # rows).
    def torrent_get_raw(ids = nil, fields : Array(String) = DEFAULT_FIELDS, *, recently_active : Bool = false, table : Bool = false) : JSON::Any
      built = Hash(String, JSON::Any).new
      built["fields"] = JSON.parse(fields.to_json)
      built["format"] = JSON::Any.new("table") if table
      if recently_active
        built["ids"] = JSON::Any.new("recently_active")
      elsif wrapped = wrap_ids(ids)
        built["ids"] = JSON.parse(wrapped.to_json)
      end
      call("torrent_get", built)
    end

    # Reassembles a `"table"`-format `torrents` member (a header row of field
    # names followed by one array of values per torrent) into {Torrent}s.
    private def torrents_from_table(entries : Array(JSON::Any)) : Array(Torrent)
      return [] of Torrent if entries.empty?
      headers = entries.first.as_a.map(&.as_s)
      entries[1..].map do |row|
        values = row.as_a
        object = {} of String => JSON::Any
        headers.each_with_index { |name, index| object[name] = values[index]? || JSON::Any.new(nil) }
        Torrent.from_json(object.to_json)
      end
    end

    # Sets properties on the given torrents. Pass any mutable field as a
    # keyword argument, e.g.
    # `torrent_set(ids, labels: ["a"], upload_limit: 50, upload_limited: true)`.
    def torrent_set(ids, **fields) : Nil
      built = arguments(**fields)
      if wrapped = wrap_ids(ids)
        built["ids"] = JSON.parse(wrapped.to_json)
      end
      call("torrent_set", built)
    end

    # Adds a torrent from a `.torrent` file path/URL (`filename`) or from
    # base64-encoded torrent contents (`metainfo`). Exactly one is required.
    #
    # Returns the added (or, if already present, duplicate) torrent.
    def torrent_add(
      filename : String? = nil,
      metainfo : String? = nil,
      *,
      download_dir : String? = nil,
      paused : Bool? = nil,
      labels : Array(String)? = nil,
      peer_limit : Int32? = nil,
      bandwidth_priority : Int32? = nil,
      cookies : String? = nil,
      files_wanted : Array(Int32)? = nil,
      files_unwanted : Array(Int32)? = nil,
      priority_high : Array(Int32)? = nil,
      priority_normal : Array(Int32)? = nil,
      priority_low : Array(Int32)? = nil,
    ) : AddedTorrent
      raise ArgumentError.new("torrent_add requires either filename or metainfo") if filename.nil? && metainfo.nil?

      built = arguments(
        filename: filename, metainfo: metainfo, download_dir: download_dir,
        paused: paused, labels: labels, peer_limit: peer_limit,
        bandwidth_priority: bandwidth_priority, cookies: cookies,
        files_wanted: files_wanted, files_unwanted: files_unwanted,
        priority_high: priority_high, priority_normal: priority_normal,
        priority_low: priority_low,
      )
      result = call("torrent_add", built)

      if entry = result["torrent_duplicate"]?
        added = AddedTorrent.from_json(entry.to_json)
        added.duplicate = true
        added
      else
        AddedTorrent.from_json(result["torrent_added"].to_json)
      end
    end

    # Removes the given torrents, optionally deleting their downloaded data.
    def torrent_remove(ids, delete_local_data : Bool = false) : Nil
      built = ids_arguments(ids)
      built["delete_local_data"] = JSON::Any.new(delete_local_data)
      call("torrent_remove", built)
    end

    # Moves the given torrents' data to `location`. With `move: true` the
    # files are moved; with `move: false` Transmission searches `location` for
    # already-present files.
    def torrent_set_location(ids, location : String, move : Bool? = nil) : Nil
      built = ids_arguments(ids)
      built["location"] = JSON::Any.new(location)
      built["move"] = JSON::Any.new(move) unless move.nil?
      call("torrent_set_location", built)
    end

    # Renames a file or directory within a single torrent. `path` is the
    # current path within the torrent; `name` is the new name.
    def torrent_rename_path(ids, path : String, name : String) : JSON::Any
      built = ids_arguments(ids)
      built["path"] = JSON::Any.new(path)
      built["name"] = JSON::Any.new(name)
      call("torrent_rename_path", built)
    end

    # --- Queue movement --------------------------------------------------

    # Moves the given torrents to the top of the queue.
    def queue_move_top(ids) : Nil
      call("queue_move_top", ids_arguments(ids))
    end

    # Moves the given torrents up one position in the queue.
    def queue_move_up(ids) : Nil
      call("queue_move_up", ids_arguments(ids))
    end

    # Moves the given torrents down one position in the queue.
    def queue_move_down(ids) : Nil
      call("queue_move_down", ids_arguments(ids))
    end

    # Moves the given torrents to the bottom of the queue.
    def queue_move_bottom(ids) : Nil
      call("queue_move_bottom", ids_arguments(ids))
    end

    # --- Session ---------------------------------------------------------

    # Retrieves session settings. Pass `fields` to fetch a subset; omit for
    # all settings. Returned as raw `JSON::Any` given the large, evolving set
    # of session fields.
    def session_get(fields : Array(String)? = nil) : JSON::Any
      if fields
        call("session_get", {"fields" => JSON.parse(fields.to_json)})
      else
        call("session_get")
      end
    end

    # Updates session settings. Pass any mutable setting as a keyword
    # argument, e.g. `session_set(speed_limit_down: 100, speed_limit_down_enabled: true)`.
    def session_set(**fields) : Nil
      call("session_set", arguments(**fields))
    end

    # Retrieves session statistics.
    def session_stats : SessionStats
      SessionStats.from_json(call("session_stats").to_json)
    end

    # Asks the daemon to shut down.
    def session_close : Nil
      call("session_close")
    end

    # --- Server ----------------------------------------------------------

    # Updates the blocklist and returns the new blocklist size.
    def blocklist_update : Int64
      call("blocklist_update")["blocklist_size"].as_i64
    end

    # Tests whether the peer port is reachable. `ip_protocol` may be `"ipv4"`
    # or `"ipv6"`.
    def port_test(ip_protocol : String? = nil) : PortTest
      built = arguments(ip_protocol: ip_protocol)
      result = built.empty? ? call("port_test") : call("port_test", built)
      PortTest.from_json(result.to_json)
    end

    # Reports free and total space for the filesystem containing `path`.
    def free_space(path : String) : FreeSpace
      FreeSpace.from_json(call("free_space", {"path" => JSON::Any.new(path)}).to_json)
    end

    # --- Bandwidth groups ------------------------------------------------

    # Retrieves bandwidth group settings. Pass `name` (a string or array of
    # strings) to fetch specific groups; omit for all. Returned as raw
    # `JSON::Any`.
    def group_get(name = nil) : JSON::Any
      built = arguments(name: name)
      built.empty? ? call("group_get") : call("group_get", built)
    end

    # Updates a bandwidth group's settings, creating it if necessary.
    def group_set(name : String, **fields) : Nil
      built = arguments(**fields)
      built["name"] = JSON::Any.new(name)
      call("group_set", built)
    end

    # --- internals -------------------------------------------------------

    # Routes a call through the active dialect, returning the result as the
    # same `JSON::Any` shape the modern path produces (so callers parsing
    # `result["torrents"]` etc. work identically on both dialects).
    private def call(method : String, params = nil) : JSON::Any
      case resolve_protocol
      in Protocol::Classic
        classic_call(method, params)
      in Protocol::Modern
        @rpc.call(method, params)
      in Protocol::Auto
        # resolve_protocol never returns Auto, but the case must be exhaustive.
        @rpc.call(method, params)
      end
    end

    # Returns the dialect to use, probing and caching once under
    # {Protocol::Auto}.
    private def resolve_protocol : Protocol
      if resolved = @resolved_protocol
        return resolved
      end
      detected = detect_protocol
      @resolved_protocol = detected
      detected
    end

    # Probes the daemon to decide between {Protocol::Modern} and
    # {Protocol::Classic}.
    #
    # Issues a raw modern `session_get` and inspects the *raw* response at the
    # transport layer (bypassing the strict json-rpc parser, which a classic
    # reply would not satisfy). A classic daemon answers a modern method with
    # `{"arguments":{},"result":"method name not recognized"}` — no `jsonrpc`
    # member and a string `result` — so any response lacking a `jsonrpc`
    # member is treated as classic.
    private def detect_protocol : Protocol
      probe = {jsonrpc: "2.0", method: "session_get", params: {} of String => JSON::Any, id: 0}
      raw = @rpc.transport.call(probe.to_json)
      parsed = JSON.parse(raw)
      object = parsed.as_h?
      if object && object.has_key?("jsonrpc")
        Protocol::Modern
      else
        Protocol::Classic
      end
    rescue JSON::ParseException
      # An unparseable probe response is not a modern envelope; fall back.
      Protocol::Classic
    end

    # Performs a single classic-dialect call: builds the
    # `{"method":…,"arguments":…,"tag":…}` envelope, translates the method
    # name and argument keys, sends it through the session transport, checks
    # `result == "success"`, and rewrites the `camelCase` `arguments` object
    # to `snake_case` so it matches what the modern path returns.
    private def classic_call(method : String, params = nil) : JSON::Any
      arguments = classic_arguments(params)
      request = {
        "method"    => JSON::Any.new(ClassicCodec.method_name(method)),
        "arguments" => JSON::Any.new(arguments),
        "tag"       => JSON::Any.new(next_tag),
      }
      raw = @rpc.transport.call(request.to_json)
      response = JSON.parse(raw)

      result = response["result"]?.try(&.as_s?)
      raise JSON::RPC::Error.new(0, result || "malformed classic response") if result != "success"

      if returned = response["arguments"]?
        ClassicCodec.snakecase_keys(returned)
      else
        JSON::Any.new({} of String => JSON::Any)
      end
    end

    # Normalizes a modern `params` value into a `snake_case` arguments hash,
    # then translates it to classic key spelling.
    private def classic_arguments(params) : Hash(String, JSON::Any)
      snake = case params
              when Nil
                Hash(String, JSON::Any).new
              when Hash
                params.transform_values { |value| value.is_a?(JSON::Any) ? value : JSON.parse(value.to_json) }
              else
                JSON.parse(params.to_json).as_h
              end
      ClassicCodec.arguments(snake)
    end

    private def next_tag : Int64
      @tag_counter.add(1) + 1
    end

    # Builds an arguments object from keyword arguments, omitting any whose
    # value is `nil`.
    private def arguments(**options) : Hash(String, JSON::Any)
      built = Hash(String, JSON::Any).new
      options.each do |name, value|
        built[name.to_s] = JSON.parse(value.to_json) unless value.nil?
      end
      built
    end

    private def ids_arguments(ids) : Hash(String, JSON::Any)
      built = Hash(String, JSON::Any).new
      if wrapped = wrap_ids(ids)
        built["ids"] = JSON.parse(wrapped.to_json)
      end
      built
    end

    # Normalizes a torrent selector into the array form Transmission expects,
    # or `nil` to mean "all torrents". Scalars are wrapped in a single-element
    # array.
    private def wrap_ids(ids)
      case ids
      when Nil   then nil
      when Array then ids
      else            [ids]
      end
    end
  end
end
