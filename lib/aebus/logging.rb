require 'logger'

module Aebus

  module Logging

    def logger
      Logging.logger
    end

    def self.logger
      @logger ||= Logger.new(STDOUT)
    end

    def self.log_to_file(file)
      begin
        @logger = Logger.new(file, 'daily')
      rescue Errno::EACCES => e
        logger.warn("Could not create log file, '#{e.message}'. Defaulting to STDOUT")
      end
    end


  end


end