module Aebus

  module EC2

    AEBUS_TAG = 'Aebus'
    AEBUS_MANUAL_TAG = 'manual'
    AEBUS_KEEP_TAG = 'keep'
    AEBUS_AUTO_TAG = 'auto'

    class Snapshot



      attr_reader :start_time, :volume_id, :id, :tags

      def initialize(hash)

        raise(ArgumentError, 'hash cannot be nil') unless hash
        @keep
        @id = hash.snapshot_id
        @start_time = hash.start_time
        @volume_id = hash.volume_id
        @tags = Hash.new
        if hash.tags
          tag_array = hash.tags
          tag_array.each do |tag|
            @tags.store(tag.key,tag.value)
          end
        end
      end

      def to_s
        "{snapshot_id => #{@id}, volume_id => #{@volume_id},  start_time => #{@start_time}, tags => #{@tags} "
      end

      def aebus_tags_include?(label)
        if aebus_snapshot?
          return aebus_tags.include? label
        end
        false
      end

      def aebus_snapshot?
        @tags.include?(AEBUS_TAG)
      end

      def aebus_removable_snapshot?
        return false unless aebus_snapshot?
        (aebus_tags & [AEBUS_MANUAL_TAG, AEBUS_KEEP_TAG]).count == 0
      end

      def aebus_tags
        @tags[AEBUS_TAG].split(',')
      end

      def keep= value
        @keep = value
      end

      def keep?
        @keep
      end

    end

  end

end