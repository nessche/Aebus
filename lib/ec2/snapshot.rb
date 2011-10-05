module Aebus

  module EC2

    class Snapshot

      attr_reader :start_time, :volume_id, :id, :tags

      def initialize(hash)

        raise(ArgumentError,"hash cannot be nil") unless hash
        @id = hash.snapshotId
        @start_time = Time.parse(hash.startTime)
        @volume_id = hash.volumeId
        @tags = Hash.new
        puts(hash)
        if (hash.tagSet) then
          tag_array = hash.tagSet.item
          tag_array.each do |tag|
            @tags.store(tag["key"],tag["value"])
          end
        end
      end

      def to_s
        "{snapshot_id => #{@id}, volume_id => #{@volume_id},  start_time => #{@start_time}, tags => #{@tags} "
      end

    end

  end

end