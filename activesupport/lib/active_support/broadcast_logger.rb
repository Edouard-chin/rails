# frozen_string_literal: true

module ActiveSupport
  # The Broadcast logger is a logger used to write messages to multiple IO. It is commonly used
  # in development to display messages on STDOUT and also write them to a file (development.log).
  # With the Broadcast logger, you can broadcast your logs to a unlimited number of sinks.
  #
  # The BroadcastLogger acts as a standard logger and all methods you are used to are available.
  # However, all the methods on this logger will propagate and be delegated to the other loggers
  # that are part of the broadcast.
  #
  # Broadcasting your logs.
  #
  #   stdout_logger = Logger.new(STDOUT)
  #   file_logger   = Logger.new("development.log")
  #   broadcast = BroadcastLogger.new
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #
  #   broadcast.info("Hello world!") # Writes the log to STDOUT and the development.log file.
  #
  # Modifying the log level to all broadcasted loggers.
  #
  #   stdout_logger = Logger.new(STDOUT)
  #   file_logger   = Logger.new("development.log")
  #   broadcast = BroadcastLogger.new
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #
  #   broadcast.level = Logger::FATAL # Modify the log level for the whole broadcast.
  #
  # Stop broadcasting log to a sink.
  #
  #   stdout_logger = Logger.new(STDOUT)
  #   file_logger   = Logger.new("development.log")
  #   broadcast = BroadcastLogger.new
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #   broadcast.info("Hello world!") # Writes the log to STDOUT and the development.log file.
  #
  #   broadcast.stop_broadcasting_to(file_logger)
  #   broadcast.info("Hello world!") # Writes the log *only* to STDOUT.
  #
  # At least one sink has to be part of the broadcast. Otherwise, your logs will not
  # be written anywhere. For instance:
  #
  #   broadcast = BroadcastLogger.new
  #   broadcast.info("Hello world") # The log message will appear nowhere.
  #
  # ====== A note on tagging logs while using the Broadcast logger
  #
  # It is quite frequent to tag logs using the `ActiveSupport::TaggedLogging` module
  # while also broadcasting them (the default Rails.logger in development is
  # configured in such a way).
  # Tagging your logs can be done for the whole broadcast or for each sink independently.
  #
  # Tagging logs for the whole broadcast
  #
  #   broadcast = BroadcastLogger.new.extend(ActiveSupport::TaggedLogging)
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #   broadcast.tagged("BMX") { broadcast.info("Hello world!") }
  #
  #   Outputs: "[BMX] Hello world!" is written on both STDOUT and in the file.
  #
  # Tagging logs for a single logger
  #
  #   stdout_logger.extend(ActiveSupport::TaggedLogging)
  #   stdout_logger.push_tags("BMX")
  #   broadcast = BroadcastLogger.new
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #   broadcast.info("Hello world!")
  #
  #   Outputs: "[BMX] Hello world!" is written on STDOUT
  #   Outputs: "Hello world!"       is written in the file
  #
  # Adding tags for the whole broadcast and adding extra tags on a specific logger
  #
  #   stdout_logger.extend(ActiveSupport::TaggedLogging)
  #   stdout_logger.push_tags("BMX")
  #   broadcast = BroadcastLogger.new.extend(ActiveSupport::TaggedLogging)
  #   broadcast.broadcast_to(stdout_logger, file_logger)
  #   broadcast.tagged("APP") { broadcast.info("Hello world!") }
  #
  #   Outputs: "[APP][BMX] Hello world!" is written on STDOUT
  #   Outputs: "[APP] Hello world!"      is written in the file
  class BroadcastLogger < Logger
    # @return [Array<Logger>] All the logger that are part of this broadcast.
    attr_reader :broadcasts

    def initialize(logdev = File::NULL, *args, **kwargs)
      @broadcasts = []

      super(logdev, *args, **kwargs)
    end

    # Add logger(s) to the broadcast.
    #
    # @param loggers [Logger] Loggers that will be part of this broadcast.
    #
    # @example Broadcast yours logs to STDOUT and STDERR
    #   broadcast.broadcast_to(Logger.new(STDOUT), Logger.new(STDERR))
    def broadcast_to(*loggers)
      @broadcasts.concat(loggers)
    end

    # Remove a logger from the broadcast. When a logger is removed, messages sent to
    # the broadcast will no longer be written to its sink.
    #
    # @param logger [Logger]
    def stop_broadcasting_to(logger)
      @broadcasts.delete(logger)
    end

    def <<(message)
      dispatch { |logger| logger.<<(message) }
    end

    def add(*args, &block)
      dispatch_with_processors do |logger|
        logger.add(*args, &block)
      end
    end

    def debug(*args, &block)
      dispatch_with_processors do |logger|
        logger.debug(*args, &block)
      end
    end

    def info(*args, &block)
      dispatch_with_processors do |logger|
        logger.info(*args, &block)
      end
    end

    def warn(*args, &block)
      dispatch_with_processors do |logger|
        logger.warn(*args, &block)
      end
    end

    def error(*args, &block)
      dispatch_with_processors do |logger|
        logger.error(*args, &block)
      end
    end

    def fatal(*args, &block)
      dispatch_with_processors do |logger|
        logger.fatal(*args, &block)
      end
    end

    def unknown(*args, &block)
      dispatch_with_processors do |logger|
        logger.unknown(*args, &block)
      end
    end

    def formatter=(formatter)
      dispatch { |logger| logger.formatter = formatter }
    end

    def progname=(progname)
      dispatch { |logger| logger.progname = progname }
    end

    def level=(level)
      dispatch { |logger| logger.level = level }
    end

    def local_level=(level)
      dispatch do |logger|
        logger.local_level = level if logger.respond_to?(:local_level=)
      end
    end

    def close
      dispatch { |logger| logger.close }
    end

    private
      def dispatch(&block)
        @broadcasts.each { |logger| block.call(logger) }
      end

      def dispatch_with_processors(&block)
        @broadcasts.each do |logger|
          logger.extend(LogProcessor) unless logger.is_a?(LogProcessor)
          logger.processors.unshift(processors)

          block.call(logger)
        ensure
          logger.processors.shift(processors.count)
        end
      end
  end
end
