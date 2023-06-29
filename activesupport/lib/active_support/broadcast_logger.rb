# frozen_string_literal: true

module ActiveSupport
  class BroadcastLogger < NewLogger
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
    def initialize(...)
      @broadcasts = []

      super(...)
    end

    def broadcast_to(other_logger)
      # Should extend from LogProcessor instead. Though the best would be to not extend
      # from anything. But if a vanilla logger gets added to the broadcast, processors
      # added to the broadcast wouldn't apply.
      other_logger.extend(TaggedLogging)

      @broadcasts << other_logger
    end

    # Add a test for this
    def stop_broadcasting_to(other_logger)
      @broadcasts.delete(other_logger)
    end

    def <<(...)
      dispatch { |logger| logger.<<(...) }
    end

    def add(...)
      dispatch do |logger|
        logger.processors.unshift(processors)

        logger.add(...)
      ensure
        logger.processors.shift(processors.count)
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
  end
end
