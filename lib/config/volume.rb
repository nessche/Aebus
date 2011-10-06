require 'cron_parser'

module Aebus

  module Config

    KEEP_ALL = "all"

    class BackupSchedule

      attr_reader :label, :last_deadline, :next_deadline, :keep

      def initialize (current_time_utc, label, backup_config)
        @label = label
        if (backup_config["enabled"]) then
          calculate_deadlines(current_time_utc, backup_config["when"])
        end
        @keep = backup_config["keep"]

      end

      def calculate_deadlines(current_time_utc, when_string)
        raise(ArgumentError, "when field cannot be empty if the backup is enabled") unless when_string

        parser = CronParser.new (when_string)
        @last_deadline = parser.last(current_time_utc)
        @next_deadline = parser.next(current_time_utc)

      end

      def to_s
        "Backup Schedule:  label => #{@label}  last_deadline => #{@last_deadline} next_deadline => #{@next_deadline}  keep => #{@keep}"
      end

      def self.parse_backups_config(current_time_utc, backups_config)

        return nil unless backups_config

        result = Hash.new

        backups_config.each_pair do |key,value|
           result.store(key, BackupSchedule.new(current_time_utc, key, value))
        end

        result

      end

    end

    class Volume

      attr_reader :id, :config

      def initialize(current_time_utc, volume_id, config, default_backups)

        @config = config
        @id = volume_id
        @backups = default_backups ? default_backups.dup : Hash.new
        if (config && config["backups"]) then
          @backups.merge(BackupSchedule.parse_backups_config(current_time_utc,config["backups"]))
        end
      end

      def backups_to_be_run(snapshots,current_time_utc)

        result = Array.new
        max_delay = 0
        @backups.each_pair do |k,v|

           unless recent_backup?(k, snapshots, v.last_deadline)
             result << k
             max_delay = [max_delay, current_time_utc.to_i - v.last_deadline.to_i].max
           end

        end
        [max_delay, result]
      end

      def recent_backup?(label, snapshots, last_deadline)
        return false unless snapshots
        snapshots.each do |snapshot|

          if (snapshot.aebus_tags_include?(label) && (snapshot.start_time > last_deadline))
            return true
          end

        end
        false
      end


      def purgeable_snapshots(snapshots)
        return [] unless snapshots
        removables = snapshots.select{|snapshot| snapshot.aebus_removable_snapshot?}
        available_backups = @backups.each_with_object({}) { | (k, v) , h | h[k] = v.keep}
        removables.each do |snapshot|
          snapshot.aebus_tags.each do |tag|
            if (available_backups.include? tag) then
              if (KEEP_ALL.eql?(available_backups[tag])) then
                snapshot.keep = true
              elsif (available_backups[tag] > 0)  then
                snapshot.keep = true
                available_backups[tag] -= 1
              end
            end
          end
        end

        removables.select{|snapshot| !snapshot.keep? }

      end

    end

  end

end