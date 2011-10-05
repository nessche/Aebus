require 'yaml'
require 'cron_parser'
require_relative 'volume'

module Aebus

  module Config

    class Config

      DEFAULT_STRING = 'default'

      attr_reader :defaults, :volumes

      def initialize(filename, current_time_utc)

        yaml_root = YAML::load(File.open(filename))
        raise "Cannot find configuration file" unless yaml_root

        @defaults = yaml_root.delete(DEFAULT_STRING)
        default_backups =  BackupSchedule.parse_backups_config(current_time_utc, @defaults["backups"])

        @volumes = Hash.new
        yaml_root.each_pair do |k, v|
          @volumes[k] = Volume.new(current_time_utc, k, v, default_backups)
        end

      end

      def volume_ids

        result = Array.new
        @volumes.each_key do |k|
          result << k
        end

        result

      end

      def get_value_for_volume(volume_id, key)
        result = nil
        if (@volumes.include? volume_id) then
          if (@volumes[volume_id].config.include? key) then
            result = @volumes[volume_id].config[key]
          else
            result = @defaults[key]
          end
        end
       result
      end




    end

  end

end