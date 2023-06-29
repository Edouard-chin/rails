# frozen_string_literal: true

module ActiveSupport
  class BroadcastLogger < NewLogger
    def initialize(...)
      @broadcasts = []

      super(...)
    end

    def broadcast_to(other_logger)
      if other_logger.respond_to?(:processors)
        other_logger.processors << processors
      end

      @broadcasts << other_logger
    end

    def <<(...)
      dispatch { |logger| logger.<<(...) }
    end

    def add(...)
      dispatch { |logger| logger.add(...) }
    end

    def debug(...)
      dispatch { |logger| logger.debug(...) }
    end

    def info(...)
      dispatch { |logger| logger.info(...) }
    end

    def warn(...)
      dispatch { |logger| logger.warn(...) }
    end

    def error(...)
      dispatch { |logger| logger.error(...) }
    end

    def fatal(...)
      dispatch { |logger| logger.fatal(...) }
    end

    def unknown(...)
      dispatch { |logger| logger.unknown(...) }
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
