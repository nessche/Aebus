require 'parse-cron'

module Aebus

  module Config

    class BackupSchedule

      attr_reader :label, :last_deadline, :next_deadline, :keep

      def initialize (current_time_utc, label, backup_config)
        @label = label
        if (backup_config["enabled"]) then
          calculate_deadlines(current_time_utc, backup_config["when"])
        end

      end

      def calculate_deadlines(current_time_utc, when_string)
        raise (ArgumentError, "when field cannot be empty if the backup is enabled") unless when_string

        parser = CronParser.new (when_string)
        @last_deadline = parser.last(current_time_utc)
        @next_deadline = parser.next(current_time_utc)

      end

    end

    class BackupDeadline

      attr_accessor :tags, :time

      def initialize(tags, time)
        @tags = tags
        @time = time
      end

    end

    class Volume

      attr_reader :last_backup_deadline, :next_backup_deadline, :id

      def initialize(current_time_utc, defaults, volume_id, config)
        @id = volume_id
        calculate_deadlines(current_time_utc, defaults, config)

      end

      def calculate_deadlines(current_time_utc, defaults, config)


      end


    end

  end

end