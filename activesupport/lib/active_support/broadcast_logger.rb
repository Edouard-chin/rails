# frozen_string_literal: true

module ActiveSupport
  class BroadcastLogger < NewLogger
    def initialize(...)
      @broadcasts = []

      super(...)
    end

    def broadcast_to(other_logger)
      other_logger.extend(TaggedLogging)

      @broadcasts << other_logger
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
