# frozen_string_literal: true

require "logger"
require "active_support/logger_silence"

module ActiveSupport
  module LogProcessor # :nodoc: ?
    attr_accessor :processors

    def self.extended(base)
      base.processors = []
    end

    def initialize(*args, **kwargs)
      super

      self.processors = []
    end

    private
      def format_message(severity, datetime, progname, msg)
        processors.flatten.reverse_each do |processor|
          msg = processor.call(msg, self)
        end

        super(severity, datetime, progname, msg)
      end
  end

  # The ActiveSupport logger is a logger with couple enhanced functionalities.
  #
  # === Default formatter
  #
  # The formatter by default will just output the log message with no timestamp or PID.
  #
  # Using a vanilla Ruby Logger
  #   logger.info("hello")        Outputs: "I, [2023-06-30T02:36:57.164173 #85447]  INFO -- : hello"
  #
  # Using the ActiveSupport::Logger
  #   logger.info("hello")        Outputs: "hello"
  #
  # === Silence
  #
  # The ActiveSupport Logger allows to silence logs up to a given severity. This is useful
  # to silence DEBUG or INFO logs temporarily but keep more important logs at the ERROR or FATAL level.
  #
  # Silencing logs up to the ERROR severity
  #
  #   logger.silence(Logger::ERROR) { logger.info("Hello") }    Doesn't output anything
  #   logger.silence(Logger::ERROR) { logger.error("Hello") }   Outputs: "Hello"
  class Logger < ::Logger
    SimpleFormatter = OldLogger::SimpleFormatter

    include LoggerSilence
    include LogProcessor

    def self.logger_outputs_to?(logger, *sources)
      OldLogger.logger_outputs_to?(logger, *sources)
    end

    def initialize(*args, **kwargs)
      super

      @formatter ||= Logger::SimpleFormatter.new
    end
  end
end
