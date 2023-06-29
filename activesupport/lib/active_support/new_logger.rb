# frozen_string_literal: true

require "logger"
require "active_support/logger_silence"

module ActiveSupport
  module LogProcessor
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
        msg = processor.call(msg)
      end

      super(severity, datetime, progname, msg)
    end
  end

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
