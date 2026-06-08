require "json"

module Transmission::RPC
  # Selects which RPC protocol dialect the {Client} speaks.
  #
  # Transmission has two on-the-wire dialects:
  #
  # - **Modern** — the JSON-RPC 2.0 envelope introduced in Transmission 4.1.0.
  #   Method names and fields use `snake_case`
  #   (`{"jsonrpc":"2.0","method":"torrent_get","params":{…},"id":1}`).
  # - **Classic** — the original Transmission envelope, the only dialect
  #   understood by 4.0.x and earlier
  #   (`{"method":"torrent-get","arguments":{…},"tag":1}`). Method names and
  #   keys are hyphenated/`camelCase` and responses are `camelCase`.
  #
  # 4.1.x understands both; 4.0.x understands only Classic, so Classic is the
  # universal fallback.
  enum Protocol
    # Probe the daemon on first use and pick {Modern} or {Classic}
    # automatically. The default.
    Auto

    # Force the JSON-RPC 2.0 dialect (Transmission 4.1.0+).
    Modern

    # Force the original Transmission dialect (works against every version).
    Classic
  end

  # Translates between the shard's internal `snake_case` representation and
  # Transmission's *classic* on-the-wire dialect (hyphenated/`camelCase` keys,
  # `camelCase` responses).
  #
  # The shard speaks `snake_case` everywhere internally (method names, argument
  # keys, the `fields` array, and the {Torrent}/etc. models). This module is
  # the single place that knows how to convert that to and from the classic
  # wire format, so the rest of the {Client} — and `models.cr` — stay
  # `snake_case` and protocol-agnostic.
  module ClassicCodec
    extend self

    # Argument keys whose classic spelling is `camelCase` rather than the
    # default `snake_case`→hyphen conversion. Drawn from the Transmission
    # 4.0.6 `rpc-spec.md` (`torrent-set`/`session-set` mutator tables): most
    # `torrent-set` keys are `camelCase`, while most `session-set` keys and the
    # `torrent-add`/`torrent-remove` keys are hyphenated. Anything not listed
    # here is converted `snake_case`→`hyphen-ated`.
    CLASSIC_KEY_EXCEPTIONS = {
      "bandwidth_priority"    => "bandwidthPriority",
      "download_limit"        => "downloadLimit",
      "download_limited"      => "downloadLimited",
      "honors_session_limits" => "honorsSessionLimits",
      "seed_idle_limit"       => "seedIdleLimit",
      "seed_idle_mode"        => "seedIdleMode",
      "seed_ratio_limit"      => "seedRatioLimit",
      "seed_ratio_mode"       => "seedRatioMode",
      "seed_ratio_limited"    => "seedRatioLimited",
      "upload_limit"          => "uploadLimit",
      "upload_limited"        => "uploadLimited",
      "queue_position"        => "queuePosition",
      "tracker_list"          => "trackerList",
      "tracker_add"           => "trackerAdd",
      "tracker_remove"        => "trackerRemove",
      "tracker_replace"       => "trackerReplace",
    }

    # Argument keys that pass through untouched (already protocol-neutral).
    PASSTHROUGH_KEYS = %w[ids fields labels location metainfo filename cookies paused format path name move group tag]

    # Converts an internal `snake_case` method name to its classic hyphenated
    # form: `torrent_get` → `torrent-get`.
    def method_name(name : String) : String
      name.tr("_", "-")
    end

    # Converts an internal `snake_case` argument key to its classic form.
    # Passthrough keys are returned unchanged, keys in
    # {CLASSIC_KEY_EXCEPTIONS} get their `camelCase` spelling, and everything
    # else is hyphenated (`download_dir` → `download-dir`).
    def argument_key(key : String) : String
      return key if PASSTHROUGH_KEYS.includes?(key)
      if mapped = CLASSIC_KEY_EXCEPTIONS[key]?
        mapped
      else
        key.tr("_", "-")
      end
    end

    # Converts a single `snake_case` `torrent-get` field name to the
    # `camelCase` form classic expects: `hash_string` → `hashString`,
    # `percent_done` → `percentDone`, `id` → `id`.
    def field_name(name : String) : String
      snake_to_camel(name)
    end

    # Converts a `snake_case` arguments hash into the classic key spelling,
    # also translating the few values that differ between dialects (the
    # `recently_active` `ids` selector).
    def arguments(arguments : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      built = Hash(String, JSON::Any).new
      arguments.each do |key, value|
        translated = case key
                     when "fields" then translate_fields(value)
                     when "ids"    then translate_ids(value)
                     else               value
                     end
        built[argument_key(key)] = translated
      end
      built
    end

    # Translates the `ids` value, mapping the modern `recently_active`
    # selector string to the classic `recently-active`.
    private def translate_ids(value : JSON::Any) : JSON::Any
      value.as_s? == "recently_active" ? JSON::Any.new("recently-active") : value
    end

    # Translates a `fields` value (an array of `snake_case` field names) into
    # the `camelCase` names classic expects.
    private def translate_fields(value : JSON::Any) : JSON::Any
      array = value.as_a?
      return value unless array
      JSON::Any.new(array.map { |entry| JSON::Any.new(field_name(entry.as_s)) })
    end

    # Recursively rewrites every object key in a classic (`camelCase`)
    # response value to `snake_case`, descending into nested objects and
    # arrays. This lets the `snake_case` {Torrent}/etc. models deserialize a
    # classic response unchanged.
    def snakecase_keys(value : JSON::Any) : JSON::Any
      if object = value.as_h?
        rewritten = Hash(String, JSON::Any).new
        object.each { |key, nested| rewritten[camel_to_snake(key)] = snakecase_keys(nested) }
        JSON::Any.new(rewritten)
      elsif array = value.as_a?
        JSON::Any.new(array.map { |entry| snakecase_keys(entry) })
      else
        value
      end
    end

    # `hash_string` → `hashString`. Leaves already-lowercase single words
    # untouched.
    def snake_to_camel(name : String) : String
      name.gsub(/_([a-z0-9])/) { $1.upcase }
    end

    # Normalizes a classic response key to `snake_case`: `hashString` →
    # `hash_string`, and `torrent-added` → `torrent_added` (a handful of
    # classic response keys are hyphenated rather than `camelCase`). Idempotent
    # for already-`snake_case` input.
    def camel_to_snake(name : String) : String
      name.tr("-", "_").gsub(/([A-Z])/) { "_#{$1.downcase}" }
    end
  end
end
