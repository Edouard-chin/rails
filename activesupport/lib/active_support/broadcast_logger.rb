# frozen_string_literal: true

module ActiveSupport
  class BroadcastLogger < Logger
    # BroadcastLogger is a regular logger. Main reason is to keep the contract untouched and
    # let users call any methods that they are used to.
    #
    # But the BroadcastLogger by itself doesn't log anything. It delegates everything
    # to the logger its broadcasting to.
    #
    # The previous implementation was different and a Logger could "transform" into
    # a broadcast, responsible for both logging/formatting its own messages as well
    # as passing the message along logger it broadcasts to.
    #
    # Main disadventage:
    # - If a user wants to remove the logger from the broadcast it's not possible.
    # - Changes made to the logger changes all logger. No way to modify only the logger.
    #   I.e. calling `level=` where I want only the main logger to be changed. Fixable with
    #   creating `broadcast_*=` methods but it doesn't feel great.
    def initialize(logdev = File::NULL, *args, **kwargs)
      @broadcasts = []

      super(logdev, *args, **kwargs)
    end

    def broadcast_to(*other_loggers)
      # Should extend from LogProcessor instead. Though the best would be to not extend
      # from anything. But if a vanilla logger gets added to the broadcast, processors
      # added to the broadcast wouldn't apply.
      other_loggers.each do |logger|
        logger.extend(TaggedLogging)
      end

      @broadcasts.concat(other_loggers)
    end

    # Add a test for this
    def stop_broadcasting_to(other_logger)
      @broadcasts.delete(other_logger)
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

    def progname=(progname)
      dispatch { |logger| logger.progname = progname }
    end

    # Remove and override `level=`. See comment on top of file. The contract on the BroadcastLevel
    # is to delegate everything to the broadcasts.
    def broadcast_level=(level)
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

    def dispatch
      @broadcasts.each { |logger| yield(logger) }
    end

    def dispatch_with_processors
      @broadcasts.each do |logger|
        logger.processors.unshift(processors)

        yield(logger)
      ensure
        logger.processors.shift(processors.count)
      end
    end
  end
end
