#!/usr/bin/env ruby

require 'rubygems'
require 'aws-sdk'
require_relative 'config/config'
require_relative 'aebus/version'
require_relative 'aebus/logging'
require_relative 'aebus/volume_status'
require_relative 'ec2/snapshot'

module Aebus

  class Core

    include Logging

    AWS_NAME_TAG = 'Name'
    AEBUS_TAG = 'Aebus'



    def status(args, options)
      @current_time_utc = Time.now.utc
      init_logger options
      logger.info("status check started at #{@current_time_utc}")

      @config = Config::Config.new(File.join(File.dirname("."), options.config), @current_time_utc)

      @ec2 = Aws::EC2::Client.new(
         region: @config.defaults['region'],
         credentials: {
           access_key_id: @config.defaults['access_key_id'],
           secret_access_key: @config.defaults['secret_access_key']
         })



      target_volumes = target_volumes(args)

      abort('Configuration contains invalid volumes') unless validate_target_volumes(target_volumes)

      status = check_status(target_volumes)

      message = "status check completed - #{status[:total]} volume(s) checked,  #{status[:to_backup]} to be backed up, max delay detected #{status[:delay]}s, #{status[:to_purge]} snapshots to be purged"
      logger.info message
      puts message



    end

    def check_status(target_volumes)
      result = {}
      result[:timestamp] = @current_time_utc
      snap_map = get_snapshots_map
      result[:volumes] = Array.new
      to_backup = 0
      to_purge = 0
      target_volumes.each do |target|
        vs = VolumeStatus.new(target)
        volume = @config.volumes[target]
        vs.last_backup = volume.last_backup
        vs.next_backup = volume.next_backup
        to_be_run = volume.backups_to_be_run(snap_map[target], @current_time_utc)

        vs.delay = to_be_run[0]
        vs.tags = to_be_run[1]

        if vs.needs_backup?
          logger.info("Volume #{target} needs to be backed up. Tags: #{vs.tags.join(',')}, max delay #{vs.delay}")
          to_backup += 1
        else
          logger.info("Volume #{target} does not need to be backed up")
        end

        vs.purgeable_snapshot_ids = volume.purgeable_snapshot_ids(snap_map[target])
        to_purge += vs.purgeable_snapshot_ids.count  if vs.purgeable_snapshot_ids
        logger.info("Volume #{target} has #{vs.purgeable_snapshot_ids.count} purgeable snapshot(s): #{vs.purgeable_snapshot_ids.join(',')}")

        result[:volumes] << vs

      end
      result[:to_backup] = to_backup
      result[:to_purge] = to_purge
      result[:delay] = result[:volumes].inject([0]) {|acc, vs| acc << vs.delay}.max
      result[:total] = result[:volumes].count
      result

    end



    def backup(args, options)


      backed_up = 0
      max_delay = 0
      purged = 0
      to_purge = 0
      to_backup = 0
      @current_time_utc = Time.now.utc
      @config = Config::Config.new(File.join(File.dirname("."), options.config), @current_time_utc)

      init_logger options
      logger.info("backup started at #{@current_time_utc}")

      @ec2 = Aws::EC2::Client.new(
          region: @config.defaults['region'],
          credentials: Aws::Credentials.new(@config.defaults['access_key_id'], @config.defaults['secret_access_key'])
      )

      target_volumes = target_volumes(args)

      abort('Configuration contains invalid volumes') unless validate_target_volumes(target_volumes)

      if options.manual

        target_volumes.each do |volume|
          to_backup += 1
          break unless backup_volume(volume, [EC2::AEBUS_MANUAL_TAG], @config.get_value_for_volume(volume.id, 'custom_tags'))
          backed_up += 1

        end

      else

        snap_map = get_snapshots_map

        target_volumes.each do |target|

          volume = @config.volumes[target]
          to_be_run = volume.backups_to_be_run(snap_map[target], @current_time_utc)
          max_delay = [max_delay, to_be_run[0]].max
          tags = to_be_run[1]
          if tags.count > 0
            tags << EC2::AEBUS_AUTO_TAG
            logger.info("Creating backup for volume #{target} with tags #{tags.join(',')}, max delay #{max_delay}")
            to_backup +=1
            break unless backup_volume(target, tags, @config.get_value_for_volume(volume.id, 'custom_tags'))
            backed_up += 1
          else
            logger.info("Volume #{target} does not need to be backed up")
          end

        end

        snap_map = get_snapshots_map # we reload the map since we may have created more snapshots
        if options.purge
          target_volumes.each do |target|
            volume = @config.volumes[target]
            purgeable_snapshot_ids = volume.purgeable_snapshot_ids(snap_map[target])
            purgeable_snapshot_ids.each do |snapshot_id|
              to_purge += 1
              purged += 1 if purge_snapshot(snapshot_id)

            end
          end
        else
          logger.info('Skipping purging phase')
        end

      end

      message = "Backup Completed at #{Time.now}. Checked #{target_volumes.count} volume(s), #{to_backup} to be backed up, #{backed_up} actually backed up, max delay detected #{max_delay}s,  #{to_purge} purgeable snapshot(s), #{purged} purged"
      logger.info(message)
      puts(message)
      if to_backup > 0 or to_purge > 0
        send_report message
      end
    end

    def target_volumes(args)

      result = @config.volume_ids
      if args && (args.count > 0)
        result &= args
      end

      result

    end

    def init_logger(options)
      Logging.log_to_file(options.logfile) unless options.logfile.nil?
    end

# backs up a given volume using the given time as part of the name and setting the given tags to the snapshot
# @param volume_id [String] the id of the volume to be backed up
# @param aebus_tags [Array] an array of String to be used as tags for the snapshot
# @param custom_tags [Hash] a Hash containing custom tags to be added to the snapshot
# @return [boolean] true if the backup was successful, false otherwise
    def backup_volume(volume_id, aebus_tags, custom_tags = {})
      begin
        volume_info = @ec2.describe_volumes(volume_ids: [volume_id])

      rescue Aws::EC2::Errors::ServiceError => e
        logger.error("Volume Id #{volume_id} not found. Underlying message #{e.message}")
        return false
      end

      begin

        volume_tags = volume_info.volumes[0].tags

        name_and_desc = Core.name_and_desc(volume_id, volume_tags, @current_time_utc)
        create_response = @ec2.create_snapshot({volume_id: volume_id, description: name_and_desc[1]})

      rescue Aws::EC2::Errors::ServiceError => e
        logger.error("Volume Id #{volume_id} could not be backed up. Underlying message #{e.message}")
        return false
      end

      begin

        tags = [
            {
                key: AWS_NAME_TAG,
                value: name_and_desc[0]
            },
            {
                key: AEBUS_TAG,
                value: aebus_tags.join(',')
            }
        ]

        if custom_tags
          custom_tags.each_pair { |k, v| tags << {key: k, value: v} }
        end

        puts custom_tags

        @ec2.create_tags(resources: [create_response.snapshot_id], tags: tags)
      rescue Aws::EC2::Errors::ServiceError => e
        logger.error("[WARNING] Could not set tags to snapshot #{create_response.snapshot_id}. Underlying message #{e.message}")
        return false
      end

      logger.info("Created snapshot #{create_response.snapshot_id} for volume #{volume_id}")

      true

    end

# calculates the name and the description to be set to a snapshot
# @param volume_id [String] the id of the volume whose snapshot we are creating
# @param tags [Array] the tags currently associated with the Volume
# @param utc_time [Time] the UTC time at which the backup process started (used to generate the correct name)
# @return [Array] an array in the form of [name, description]]
    def self.name_and_desc(volume_id, tags, utc_time)

      name = "backup_#{utc_time.strftime('%Y%m%d')}_#{volume_id}"
      volume_name = volume_id
      tags.each do |tag|
        if tag['key'].eql?(AWS_NAME_TAG)
          volume_name = tag['value']
          break
        end
      end

      description = "Backup for volume #{volume_name} taken at #{utc_time.strftime('%Y-%m-%d %H:%M:%S')}"

      return [name, description]

    end

    def get_snapshots_map

      response = @ec2.describe_snapshots(owner_ids: ['self'])
      return Hash.new unless response.snapshots
      snap_array = response.snapshots
      result = Hash.new
      snap_array.each do |snap|
        snapshot = EC2::Snapshot.new(snap)
        if result.include?(snapshot.volume_id)
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
        @ec2.delete_snapshot(:snapshot_id => snapshot_id)
        logger.info("Purged snapshot #{snapshot_id}")
      rescue Aws::EC2::Errors::ServiceError => e
        logger.warn("Could not purge snapshot #{snapshot_id}; underlying message #{e.message}")
        false
      end

    end

    def validate_target_volumes(target_volumes)
      logger.info(target_volumes)
      begin
        @ec2.describe_volumes({volume_ids: target_volumes})
        logger.info('Target volumes validated')
        true
      rescue Aws::EC2::Errors::ServiceError => e
        logger.error("Target validation failed with message '#{e.message}' Check your configuration")
        false
      end

    end

    def send_report(message)
      if message.nil?
        logger.warn('Tried to send a message, but no message was specified')
        return
      end
      to_address = @config.defaults['to_address']
      if to_address.instance_of? String
        to_address = [to_address]
      end
      from_address = @config.defaults['from_address']
      if to_address.nil? or from_address.nil?
        logger.warn('Tried to send a message but either to or from address where missing from configuration')
        return
      end
      ses = Aws::SES::Client.new(
        region: @config.defaults['region'],
        credentials: Aws::Credentials.new(@config.defaults['access_key_id'], @config.defaults['secret_access_key'])
      )
      logger.info("Sending report to #{to_address} from account #{from_address}")
      ses.send_email({
        destination: {
          to_addresses: to_address
        },
        source: from_address,
        message: {
          subject: {
            charset: 'UTF-8',
            data: 'Aebus Report'
          },
          body: {
            text: {
                charset: 'UTF-8',
                data: message
            }
          }
        }
      })


    end

  end

end
