require "json"

module Transmission::RPC
  # The activity state of a torrent, as reported by the `status` field.
  enum Status
    Stopped      = 0
    CheckWait    = 1
    Check        = 2
    DownloadWait = 3
    Download     = 4
    SeedWait     = 5
    Seed         = 6
  end

  # A torrent as returned by `torrent_get`.
  #
  # Every field is nilable: `torrent_get` only populates the fields the caller
  # asked for, and unknown fields in the response are ignored. Request fields
  # with {Client#torrent_get}'s `fields:` argument. This struct covers the
  # commonly used fields; use {Client#torrent_get_raw} when you need others.
  struct Torrent
    include JSON::Serializable

    getter id : Int64?
    getter hash_string : String?
    getter name : String?
    getter status : Int32?
    getter total_size : Int64?
    getter size_when_done : Int64?
    getter left_until_done : Int64?
    getter percent_done : Float64?
    getter percent_complete : Float64?
    getter metadata_percent_complete : Float64?
    getter recheck_progress : Float64?
    getter rate_download : Int64?
    getter rate_upload : Int64?
    getter eta : Int64?
    getter upload_ratio : Float64?
    getter uploaded_ever : Int64?
    getter downloaded_ever : Int64?
    getter seed_ratio_limit : Float64?
    getter seed_ratio_mode : Int32?
    getter bandwidth_priority : Int32?
    getter queue_position : Int32?
    getter peers_connected : Int32?
    getter peers_getting_from_us : Int32?
    getter peers_sending_to_us : Int32?
    getter seconds_seeding : Int64?
    getter seconds_downloading : Int64?
    getter download_dir : String?
    getter is_finished : Bool?
    getter is_stalled : Bool?
    getter is_private : Bool?
    getter error : Int32?
    getter error_string : String?
    getter labels : Array(String)?
    getter added_date : Int64?
    getter done_date : Int64?
    getter start_date : Int64?
    getter activity_date : Int64?

    # The {Status} enum corresponding to the numeric `status` field, or `nil`
    # if `status` was not requested or is unrecognized.
    def state : Status?
      if value = status
        Status.from_value?(value)
      end
    end
  end

  # The result of `torrent_add`. On success Transmission returns the added
  # torrent; if the torrent was already present it returns the existing one
  # and sets {#duplicate?}.
  struct AddedTorrent
    include JSON::Serializable

    getter id : Int64?
    getter name : String?
    getter hash_string : String?

    @[JSON::Field(ignore: true)]
    property? duplicate : Bool = false
  end

  # Aggregate transfer counters, used for both the cumulative (all-time) and
  # current-session statistics in {SessionStats}.
  struct Stats
    include JSON::Serializable

    getter uploaded_bytes : Int64?
    getter downloaded_bytes : Int64?
    getter files_added : Int64?
    getter session_count : Int64?
    getter seconds_active : Int64?
  end

  # The result of `session_stats`.
  struct SessionStats
    include JSON::Serializable

    getter torrent_count : Int32?
    getter active_torrent_count : Int32?
    getter paused_torrent_count : Int32?
    getter download_speed : Int64?
    getter upload_speed : Int64?
    getter cumulative_stats : Stats?
    getter current_stats : Stats?
  end

  # The result of `free_space`.
  struct FreeSpace
    include JSON::Serializable

    getter path : String?
    getter size_bytes : Int64?
    getter total_size : Int64?
  end

  # The result of `port_test`.
  struct PortTest
    include JSON::Serializable

    getter? port_is_open : Bool = false
    getter ip_protocol : String?
  end
end
