module Aebus

  module EC2

    AEBUS_TAG = "Aebus"
    AEBUS_MANUAL_TAG = "manual"
    AEBUS_KEEP_TAG = "keep"
    AEBUS_AUTO_TAG = "auto"

    class Snapshot



      attr_reader :start_time, :volume_id, :id, :tags

      def initialize(hash)

        raise(ArgumentError,"hash cannot be nil") unless hash
        @id = hash.snapshotId
        @start_time = Time.parse(hash.startTime)
        @volume_id = hash.volumeId
        @tags = Hash.new
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

      def aebus_tags_include?(label)

        if (@tags.include? AEBUS_TAG) then
          aebus_tags = @tags[AEBUS_TAG].split(',')
          return aebus_tags.include? label
        end
        false
      end

    end

  end

end