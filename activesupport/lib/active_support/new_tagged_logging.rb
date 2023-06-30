# frozen_string_literal: true

require "active_support/core_ext/module/delegation"
require "active_support/core_ext/object/blank"
require "active_support/tagged_logging"
require "logger"
require "active_support/logger"

module ActiveSupport
  # = Active Support Tagged Logging
  #
  # Wraps any standard Logger object to provide tagging capabilities.
  #
  # May be called with a block:
  #
  #   logger = Logger.new(STDOUT).extend(ActiveSupport::TaggedLogging)
  #   logger.tagged('BCX') { logger.info 'Stuff' }                                  # Logs "[BCX] Stuff"
  #   logger.tagged('BCX', "Jason") { |tagged_logger| tagged_logger.info 'Stuff' }  # Logs "[BCX] [Jason] Stuff"
  #   logger.tagged('BCX') { logger.tagged('Jason') { logger.info 'Stuff' } }       # Logs "[BCX] [Jason] Stuff"
  #
  # If called without a block, a new logger will be returned with applied tags:
  #
  #   logger = Logger.new(STDOUT).extend(ActiveSupport::TaggedLogging)
  #   logger.tagged("BCX").info "Stuff"                 # Logs "[BCX] Stuff"
  #   logger.tagged("BCX", "Jason").info "Stuff"        # Logs "[BCX] [Jason] Stuff"
  #   logger.tagged("BCX").tagged("Jason").info "Stuff" # Logs "[BCX] [Jason] Stuff"
  #
  # This is used by the default Rails.logger as configured by Railties to make
  # it easy to stamp log lines with subdomains, request ids, and anything else
  # to aid debugging of multi-user production applications.
  module TaggedLogging
    class TagProcessor
      include OldTaggedLogging::Formatter

      def call(msg, logger)
        if logger.formatter.nil?
          ActiveSupport.deprecator.warn(<<~EOM)
            ActiveSupport::TaggedLogging will no longer set a default formatter on your logger.
            To keep your logs unchanged in the future, use the `ActiveSupport::Logger` class or
            set the `ActiveSupport::Logger::SimpleFormatter` formatter explicitly on the logger.

            Example:
              logger = Rails::Logger.new
              logger.extend(ActiveSupport::TaggedLogging)

            Example:
              custom_logger = CustomLogger.new(formatter: ActiveSupport::Logger::SimpleFormatter)
              custom_logger.extend(ActiveSupport::TaggedLogging)
          EOM

          logger.formatter ||= Logger::SimpleFormatter.new
        end

        tag_stack.format_message(msg)
      end
    end

    attr_accessor :tag_processor
    delegate :push_tags, :current_tags, :pop_tags, :clear_tags!, to: :tag_processor

    def self.extended(base) # :nodoc:
      base.tag_processor = TagProcessor.new
      base.extend(ActiveSupport::LogProcessor)

      base.processors << base.tag_processor
    end

    def self.new(logger) # :nodoc:
      if logger.is_a?(TaggedLogging)
        ActiveSupport.deprecator.warn(<<~EOM)
          `ActiveSupport::TaggedLogging.new` is deprecated.
           To create a new logger from an existing logger, use `logger#clone` instead.

           Before: `new_tagged_logger = ActiveSupport::TaggedLogging.new(existing_logger)`
           Now:    `new_tagged_logger = existing_logger.clone`
        EOM

        logger.clone
      else
        ActiveSupport.deprecator.warn(<<~EOM)
          To create a new Logger instance with tagging functionalities, extend
          the `ActiveSupport::TaggedLogging` module.

          Example: `my_logger.extend(ActiveSupport::TaggedLogging)`
        EOM

        logger.extend(TaggedLogging)
      end
    end

    def initialize_clone(_) # :nodoc:
      self.tag_processor = TagProcessor.new
      self.processors = [tag_processor]

      super
    end

    # Add +tags+ to your logs. This method can be used with or a without a block.
    #
    # With a block:
    #   All logs will be tagged with +tags+ for the duration of the block.
    #
    # Without a block:
    #   A *new* logger instance will be returned. Logs written with this new logger will be tagged
    #   using the +tags+ and any other tags from the previous logger. For example:
    #
    #   logger1 = Logger.new(STDOUT).extend(ActiveSupport::TaggedLogging)
    #   logger2 = logger1.tagged("BMX")
    #
    #   logger1.info("Hello world!") # Outputs: Hello world!
    #   logger2.info("Hello world!") # Outputs: [BMX] Hello world!
    #
    #   logger3 = logger2.tagged("APP")
    #   logger3.info("Hello world!") # Output: [BMX][APP] Hello world!
    #
    # If you want to permanently add tags to a logger, without creating a new logger instance,
    # use `logger#push_tags` instead.
    #
    # @param tags [Array<String>] Tags to be added to the log messages.
    def tagged(*tags)
      if block_given?
        tag_processor.tagged(*tags) { yield(self) }
      else
        logger = clone
        logger.tag_processor.extend(OldTaggedLogging::LocalTagStorage)
        logger.tag_processor.push_tags(*tag_processor.current_tags, *tags)

        logger
      end
    end

    def flush
      clear_tags!
      super if defined?(super)
    end
  end
end
