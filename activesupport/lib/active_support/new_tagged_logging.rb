# frozen_string_literal: true

require "active_support/logger"

module ActiveSupport
  module NewTaggedLogging
    attr_accessor :tag_processor
    delegate :push_tags, :pop_tags, :clear_tags!, to: :tag_processor

    def self.extended(base)
      base.tag_processor = TagProcessor.new
      base.extend(ActiveSupport::LogProcessor)

      base.processors << base.tag_processor
    end

    def initialize_clone(other)
      other.tag_processor = TagProcessor.new

      other.processors = [other.tag_processor]
    end

    def tagged(*tags)
      tag_processor.tagged(*tags) { yield(self) }
    end

    def flush
      clear_tags!

      super if defined?(super)
    end

    class TagProcessor
      attr_accessor :tags

      def initialize(*tags)
        self.tags = tags
      end

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
  end
end
