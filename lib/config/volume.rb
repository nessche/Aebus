require 'cron_parser'

module Aebus

  module Config

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

      attr_reader :last_backup_deadline, :next_backup_deadline, :id, :config

      def initialize(current_time_utc, volume_id, config, default_backups)

        @config = config
        @id = volume_id
        @backups = default_backups ? default_backups.dup : Hash.new
        if (config && config["backups"]) then
          @backups.merge(BackupSchedule.parse_backups_config(current_time_utc,config["backups"]))
        end
      end

      def backups_to_be_run(snapshots)

        result = Array.new

        @backups.each_pair do |k,v|

           result << k unless recent_backup?(k, snapshots, v.last_deadline)

        end
        result
      end

      def recent_backup?(label, snapshots, last_deadline)

        snapshots.each do |snapshot|

          if (snapshot.aebus_tags_include?(label) && (snapshot.start_time > last_deadline))
            return true
          end

        end
        false
      end


    end

  end

end