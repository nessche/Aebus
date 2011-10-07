module Aebus

  class VolumeStatus

    attr_accessor :id, :last_backup, :next_backup, :delay, :purgeable_snapshot_ids, :tags

    def initialize(volume_id)
       @id = volume_id
    end

    def needs_backup?
      (!@tags.nil? && (@tags.count > 0))
    end

    def to_s
      "Volume: id => #{id}, :last_backup => #{last_backup}, next_backup=> #{next_backup}, needs_backup? => #{needs_backup?}, delay => #{delay}, tags => #{tags}, purgeable_snapshot => #{purgeable_snapshots}"


    end

  end

end