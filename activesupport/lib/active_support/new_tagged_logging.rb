# frozen_string_literal: true

require "active_support/core_ext/module/delegation"
require "active_support/core_ext/object/blank"
require "logger"
require "active_support/logger"

module ActiveSupport
  # = Active Support Tagged Logging
  #
  # Wraps any standard Logger object to provide tagging capabilities.
  #
  # May be called with a block:
  #
  #   logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
  #   logger.tagged('BCX') { logger.info 'Stuff' }                                  # Logs "[BCX] Stuff"
  #   logger.tagged('BCX', "Jason") { |tagged_logger| tagged_logger.info 'Stuff' }  # Logs "[BCX] [Jason] Stuff"
  #   logger.tagged('BCX') { logger.tagged('Jason') { logger.info 'Stuff' } }       # Logs "[BCX] [Jason] Stuff"
  #
  # If called without a block, a new logger will be returned with applied tags:
  #
  #   logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
  #   logger.tagged("BCX").info "Stuff"                 # Logs "[BCX] Stuff"
  #   logger.tagged("BCX", "Jason").info "Stuff"        # Logs "[BCX] [Jason] Stuff"
  #   logger.tagged("BCX").tagged("Jason").info "Stuff" # Logs "[BCX] [Jason] Stuff"
  #
  # This is used by the default Rails.logger as configured by Railties to make
  # it easy to stamp log lines with subdomains, request ids, and anything else
  # to aid debugging of multi-user production applications.
  module TaggedLogging
    class TagProcessor
      def tagged(*tags)
        pushed_count = push_tags(tags).size
        yield self
      ensure
        pop_tags(pushed_count)
      end

      def call(msg)
        tag_stack.format_message(msg)
      end

      def push_tags(*tags)
        tag_stack.push_tags(tags)
      end

      def pop_tags(count = 1)
        tag_stack.pop_tags(count)
      end

      def clear_tags!
        tag_stack.clear
      end

      def tag_stack
        # We use our object ID here to avoid conflicting with other instances
        @thread_key ||= "activesupport_tagged_logging_tags:#{object_id}"
        IsolatedExecutionState[@thread_key] ||= TagStack.new
      end

      def current_tags
        tag_stack.tags
      end

      def tags_text
        tag_stack.format_message("")
      end
    end

    class TagStack # :nodoc:
      attr_reader :tags

      def initialize
        @tags = []
        @tags_string = nil
      end

      def push_tags(tags)
        @tags_string = nil
        tags.flatten!
        tags.reject!(&:blank?)
        @tags.concat(tags)
        tags
      end

      def pop_tags(count)
        @tags_string = nil
        @tags.pop(count)
      end

      def clear
        @tags_string = nil
        @tags.clear
      end

      def format_message(message)
        if @tags.empty?
          message
        elsif @tags.size == 1
          "[#{@tags[0]}] #{message}"
        else
          @tags_string ||= "[#{@tags.join("] [")}] "
          "#{@tags_string}#{message}"
        end
      end
    end

    module LocalTagStorage # :nodoc:
      attr_accessor :tag_stack

      def self.extended(base)
        base.tag_stack = TagStack.new
      end
    end

    attr_accessor :tag_processor
    delegate :push_tags, :pop_tags, :clear_tags!, to: :tag_processor

    def self.extended(base)
      base.tag_processor = TagProcessor.new
      base.extend(ActiveSupport::LogProcessor)

      base.processors << base.tag_processor
    end

    def self.new(logger)
      if logger.is_a?(TaggedLogging)
        # ActiveSupport.deprecator.warn(<<~EOM)
        #   `ActiveSupport::TaggedLogging.new` is deprecated.
        #    To create a new logger from an existing logger, use `logger#clone` instead.

        #    Before: `new_tagged_logger = ActiveSupport::TaggedLogging.new(existing_logger)`
        #    Now:    `new_tagged_logger = existing_logger.clone`
        # EOM

        logger.clone
      else
        # ActiveSupport.deprecator.warn(<<~EOM)
        #   To create a new Logger instance with Tagging functionalities, extend
        #   the `ActiveSupport::TaggedLogging` module.

        #   Example: `my_logger.extend(ActiveSupport::TaggedLogging)`
        # EOM

        logger.extend(TaggedLogging)
      end
    end

    # Cloning creates an issue for logger that used to be part of a broadcast.
    # If I clone a logger, should that logger be also part of the broadcast?
    def initialize_clone(_)
      self.tag_processor = TagProcessor.new
      self.processors = [tag_processor]

      super
    end

    def add(...)
      # if formatter.nil?
      #   ActiveSupport.deprecator.warn(<<~EOM)
      #     ActiveSupport::TaggedLogging will no longer set a default formatter on your logger.
      #     To keep your logs unchanged in the future, use the `ActiveSupport::Logger` class or
      #     set the `ActiveSupport::Logger::SimpleFormatter` formatter explicitely on the logger.

      #     Example:

      #     logger = Rails::Logger.new
      #     logger.extend(ActiveSupport::TaggedLogging)

      #     Example:

      #     custom_logger = CustomLogger.new(formatter: ActiveSupport::Logger::SimpleFormatter)
      #     custom_logger.extend(ActiveSupport::TaggedLogging)
      #   EOM

        self.formatter ||= Logger::SimpleFormatter.new
      # end

      super(...)
    end

    def tagged(*tags)
      if block_given?
        tag_processor.tagged(*tags) { yield(self) }
      else
        # Problem if the previous logger was part of a broadcast. See comment on #initialize_clone.
        logger = clone
        logger.tag_processor.extend(LocalTagStorage)
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
