require 'yaml'

module Aebus

  module Config

    class Config

      DEFAULT_STRING = 'default'

      attr_reader :defaults, :volumes

      def initialize(options = {})

        yaml_root = YAML::load(File.open(options[:filename]))
        raise "Cannot find configuration file" unless yaml_root

        puts(yaml_root)
        @volumes = Hash.new
        yaml_root.each_pair do |k, v|
          puts "#{k}"
          if k.eql?(DEFAULT_STRING) then
            @defaults = v
          else
            @volumes[k] = v
          end
        end

      end

      def volume_ids

        result = Array.new
        @volumes.each_key do |k|
          result << k
        end

        return result

      end

      def get_value_for_volume(volume_id, key)
        result = nil
        if (@volumes.include? volume_id) then
          if (@volumes[volume_id].include? key) then
            result = @volumes[volume_id][key]
          else
            result = @defaults[key]
          end
        end
        return result
      end


    end

  end

end