# frozen_string_literal: true

require "logger"
require "active_support/logger_silence"

module ActiveSupport
  module LogProcessor
    attr_accessor :processors

    def self.extended(base)
      base.processors = []
    end

    def initialize(*)
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

  class NewLogger < ::Logger
    include LoggerSilence
    include LogProcessor

    def self.logger_outputs_to?(...)
      Logger.logger_outputs_to?(...)
    end

    def initialize(...)
      super(...)

      @formatter ||= Logger::SimpleFormatter.new
    end
  end
end
