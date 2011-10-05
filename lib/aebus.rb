#!/usr/bin/env ruby

require 'rubygems'
require 'AWS'
require_relative 'config/config'
require_relative 'aebus_zones'
require_relative 'ec2/snapshot'

module Aebus

  VERSION = '0.0.1'

  class Aebus

    AWS_NAME_TAG = "Name"
    AEBUS_TAG = "Aebus"

    ACCESS_KEY_ID = 'AKIAJFRMUGR5CKQAI3PA'
    SECRET_ACCESS_KEY = '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'
    SERVER_URL = 'eu-west-1.ec2.amazonaws.com'

    def status(args, options)
      puts("yes")
    end

    def backup(args, options)
      current_time_utc = Time.now.utc
      config = AebusConfig.new(:filename => File.join(File.dirname("."), options.config))
      @ec2 = AWS::EC2::Base.new(:access_key_id => config.defaults["access_key_id"],
                               :secret_access_key => config.defaults["secret_access_key"],
                               :server => zone_to_url(config.defaults["zone"]))

      target_volumes = calculate_target_volumes(config, args)
      if (options.manual) then

        target_volumes.each do |volume|

          backup_volume(volume, current_time_utc, ["manual"])

        end

      else

        snap_map = get_snapshots_map
        puts(config.defaults)
        puts(config.defaults["backup_time"])
    #    puts(Time.parse(config.defaults["backup_time"]))

        time_to_backup?(config, current_time_utc)

        #TODO: add the logic to check whether or not a backup is needed

      end

    end


    def self.execute(args)
      config =  AebusConfig.new(:filename => File.join(File.dirname("."), DEFAULT_CONFIG_NAME))
      puts "----- defaults -----"
      puts(config.defaults)
      puts("----- volumes -----")
      puts(config.volumes)
    #  ec2 = AWS::EC2::Base.new(:access_key_id => ACCESS_KEY_ID, :secret_access_key => SECRET_ACCESS_KEY, :server => SERVER_URL)

      puts "----- listing images owned by 'amazon' -----"
      response = ec2.describe_images(:owner_id => 'self')
      response.imagesSet.item.each do |image|
        # OpenStruct objects have members!
        puts(image)
        image.each_pair do |k,v|
          puts "#{k} => #{v}"
        end

      end


    end

    def calculate_target_volumes(config, args)

      result = config.volume_ids
      if (args && (args.count > 0)) then
        result &= args
      end

      puts ("intersection is")
      puts result
      return result

    end

    def list_volumes
      response = @ec2.describe_volumes
      puts(response)
    end


    def zone_to_url(zone)
      ZONES[zone]
    end

    def backup_volume(volume_id, current_time_utc, tags)
      begin
        volume_info = @ec2.describe_volumes(:volume_id => volume_id)

      rescue AWS::Error => e
        puts("[WARNING] Volume Id #{volume_id} not found")
        return false
      end

      begin
        puts(volume_info)
        volume_tags = volume_info.volumeSet.item[0].tagSet.item
        puts(volume_tags)

        name_and_desc = Aebus.calculate_name_and_desc(volume_id, volume_tags, current_time_utc)
        puts(name_and_desc)
        create_response = @ec2.create_snapshot(:volume_id => volume_id, :description => name_and_desc[1])
        puts(create_response)

      rescue AWS::Error => e
        puts("[ERROR] Volume Id #{volume_id} could not be backed up")
        return false
      end

      begin

        @ec2.create_tags(:resource_id => create_response.snapshotId,
                         :tag => [{AWS_NAME_TAG => name_and_desc[0]}, {AEBUS_TAG => tags.join(',')}])
      rescue AWS::Error => e
        puts("[WARNING] Could not set tags to snapshot #{create_response.snapshotId}")
        return false
      end

      puts("[INFO] Created snapshot #{create_response.snapshotId} for volume #{volume_id}");

      return true

    end


    def self.calculate_name_and_desc(volume_id, tags, utc_time)

      name = "backup_#{utc_time.strftime("%Y%m%d")}_#{volume_id}"
      volume_name = volume_id
      tags.each do |tag|
        if tag["key"].eql?(AWS_NAME_TAG) then
          volume_name = tag["value"]
          break
        end
      end

      description = "Backup for volume #{volume_name} taken at #{utc_time.strftime("%Y-%m-%d %H:%M:%S")}"

      return [name, description]

    end

    def get_snapshots_map

      response = @ec2.describe_snapshots(:owner => 'self')
      snap_array = response.snapshotSet.item
      result = Hash.new
      snap_array.each do |snap|
        snapshot = EC2::Snapshot.new(snap)
        if (result.include?(snapshot.volume_id)) then
          vol_array = result[snapshot.volume_id]
          index = vol_array.index{ |s| snapshot.start_time > s.start_time}
          index ||= vol_array.count
          vol_array.insert(index, snapshot)
        else
          vol_array = Array.new
          vol_array << snapshot
          result.store(snapshot.volume_id, vol_array)
        end
      end
      return result

    end

    def time_to_backup?(snapshots, config, current_time_utc)

      last_midnight = Time.utc(current_time_utc.year, current_time_utc.month, current_time_utc.day)
      last_backup_chance = last_midnight + config.defaults["backup_time"]
      if (current_time_utc < last_backup_chance) then
        last_backup_chance -= 86400
      end




    end

  end

end
