#!/usr/bin/env ruby

require 'rubygems'
require 'AWS'
require_relative 'config/config'
require_relative 'aebus/version'
require_relative 'aebus/logging'
require_relative 'ec2/zones'
require_relative 'ec2/snapshot'

module Aebus

  class Core

    include Logging

    AWS_NAME_TAG = "Name"
    AEBUS_TAG = "Aebus"

    def status(args, options)
      current_time_utc = Time.now.utc
      init_logger options
      logger.info("status check started at #{current_time_utc}")

      config = Config::Config.new(File.join(File.dirname("."), options.config), current_time_utc)
      @ec2 = AWS::EC2::Base.new(:access_key_id => config.defaults["access_key_id"],
                               :secret_access_key => config.defaults["secret_access_key"],
                               :server => EC2::zone_to_url(config.defaults["zone"]))



      to_backup = 0
      to_be_purged = 0
      max_delay = 0
      target_volumes = calculate_target_volumes(config, args)

      abort("Configuration contains invalid volumes") unless validate_target_volumes(target_volumes)

      snap_map = get_snapshots_map

      target_volumes.each do |target|
        volume = config.volumes[target]
        to_be_run = volume.backups_to_be_run(snap_map[target], current_time_utc)
        max_delay = [max_delay, to_be_run[0]].max
        tags = to_be_run[1]
        if (tags.count > 0) then
          to_backup += 1
          logger.info("Volume #{target} needs to be backed up. Tags: #{tags.join(',')}, max delay #{to_be_run[0]}")
        else
          logger.info("Volume #{target} does not need to be backed up")
        end

        purgeable_snapshots =volume.purgeable_snapshots(snap_map[target])
        logger.info("Volume #{target} has #{purgeable_snapshots.count} purgeable snapshot(s): #{purgeable_snapshots.inject([]){|x, snap| x << snap.id}.join(',')}")
        to_be_purged += purgeable_snapshots.count



      end

      message = "status check completed - #{to_backup} volume(s) to be backed up, max delay detected #{max_delay}s, #{to_be_purged} snapshots to be purged"
      logger.info message
      puts message



    end

    def backup(args, options)

      backed_up = 0
      current_time_utc = Time.now.utc
      config = Config::Config.new(File.join(File.dirname("."), options.config), current_time_utc)

      init_logger options
      logger.info("backup started at #{current_time_utc}")

      @ec2 = AWS::EC2::Base.new(:access_key_id => config.defaults["access_key_id"],
                               :secret_access_key => config.defaults["secret_access_key"],
                               :server => EC2::zone_to_url(config.defaults["zone"]))

      target_volumes = calculate_target_volumes(config, args)
      if (options.manual) then

        target_volumes.each do |volume|

          backup_volume(volume, current_time_utc, [EC2::AEBUS_MANUAL_TAG])
          backed_up += 1

        end

      else

        snap_map = get_snapshots_map

        purged = 0
        max_delay = 0
        target_volumes.each do |target|

          volume = config.volumes[target]
          to_be_run = volume.backups_to_be_run(snap_map[target], current_time_utc)
          max_delay = max(max_delay, to_be_run[0])
          tags = to_be_run[1]
          if (tags.count > 0) then
            tags << EC2::AEBUS_AUTO_TAG
            logger.info("Creating backup for volume #{target} with tags #{tags.join(',')}, max delay #{max_delay}")
            backup_volume(target, current_time_utc, tags)
            backed_up += 1
          else
            logger.info("Volume #{target} does not need to be backed up")
          end

        end

        snap_map = get_snapshots_map # we reload the map since we may have created more snapshots
        if (options.purge) then
          target_volumes.each do |target|
            volume = config.volumes[target]
            purgeable_snapshots = volume.purgeable_snapshots(snap_map[target])
            purgeable_snapshots.each do |snapshot|
              purge_snapshot(snapshot.id)
              purged += 1
            end
          end
        else
          logger.info("Skipping purging phase")
        end

      end

      message = "Backup Completed at #{Time.now}. Backed up #{backed_up} volume(s), max delay detected #{max_delay}, purged #{purged} snapshot(s)"
      logger.info(message)
      puts(message)

    end

    def calculate_target_volumes(config, args)

      result = config.volume_ids
      if (args && (args.count > 0)) then
        result &= args
      end

      result

    end

    def list_volumes
      response = @ec2.describe_volumes
      puts(response)
    end

    def init_logger(options)
      Logging.log_to_file(options.logfile) unless options.logfile.nil?
    end

    def backup_volume(volume_id, current_time_utc, tags)
      begin
        volume_info = @ec2.describe_volumes(:volume_id => volume_id)

      rescue AWS::Error => e
        logger.warning("Volume Id #{volume_id} not found")
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
        logger.error("Volume Id #{volume_id} could not be backed up")
        return false
      end

      begin

        @ec2.create_tags(:resource_id => create_response.snapshotId,
                         :tag => [{AWS_NAME_TAG => name_and_desc[0]}, {AEBUS_TAG => tags.join(',')}])
      rescue AWS::Error => e
        logger.error("[WARNING] Could not set tags to snapshot #{create_response.snapshotId}")
        return false
      end

      logger.info("Created snapshot #{create_response.snapshotId} for volume #{volume_id}");

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
      result

    end

    def purge_snapshot(snapshot_id)
      begin
        response = @ec2.delete_snapshot(:snapshot_id => snapshot_id)
        if (response["return"]) then
          logger.info("Purged snapshot #{snapshot_id}")
        end
      rescue AWS::Error => e
        logger.warn("Could not purge snapshot #{snapshot_id}")
      end

    end

    def validate_target_volumes(target_volumes)
      begin
        @ec2.describe_volumes(:volume_id => target_volumes)
        logger.info("Target volumes validated")
        true
      rescue AWS::Error => e
        logger.error("Target validation failed with message '#{e.message}' Check your configuration")
        false
      end

    end

  end

end
