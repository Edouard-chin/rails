# frozen_string_literal: true

require_relative "abstract_unit"

module ActiveSupport
  class BroadcastLoggerTest < TestCase
    attr_reader :logger, :log1, :log2

    setup do
      @log1 = FakeLogger.new
      @log2 = FakeLogger.new
      @logger = BroadcastLogger.new
      @logger.broadcast_to(@log1, @log2)
    end

    Logger::Severity.constants.each do |level_name|
      method = level_name.downcase
      level = Logger::Severity.const_get(level_name)

      test "##{method} adds the message to all loggers" do
        logger.public_send(method, "msg")

        assert_equal [level, "msg", nil], log1.adds.first
        assert_equal [level, "msg", nil], log2.adds.first
      end
    end

    test "#close broadcasts to all loggers" do
      logger.close

      assert log1.closed, "should be closed"
      assert log2.closed, "should be closed"
    end

    test "#<< shovels the value into all loggers" do
      logger << "foo"

      assert_equal %w{ foo }, log1.chevrons
      assert_equal %w{ foo }, log2.chevrons
    end

    test "#level= assigns the level to all loggers" do
      assert_equal ::Logger::DEBUG, log1.level
      logger.level = ::Logger::FATAL

      assert_equal ::Logger::FATAL, log1.level
      assert_equal ::Logger::FATAL, log2.level
    end

    test "#progname= assigns to all the loggers" do
      assert_nil logger.progname
      logger.progname = ::Logger::FATAL

      assert_equal ::Logger::FATAL, log1.progname
      assert_equal ::Logger::FATAL, log2.progname
    end

    test "#formatter= assigns to all the loggers" do
      logger.formatter = ::Logger::FATAL

      assert_equal ::Logger::FATAL, log1.formatter
      assert_equal ::Logger::FATAL, log2.formatter
    end

    test "#local_level= assigns the local_level to all loggers" do
      assert_equal ::Logger::DEBUG, log1.local_level
      logger.local_level = ::Logger::FATAL

      assert_equal ::Logger::FATAL, log1.local_level
      assert_equal ::Logger::FATAL, log2.local_level
    end

    test "severity methods get called on all loggers" do
      my_logger = Class.new(::Logger) do
        attr_reader :info_called

        def info(msg, &block)
          @info_called = true
        end
      end.new(StringIO.new)

      @logger.broadcast_to(my_logger)

      assert_changes(-> { my_logger.info_called }, from: nil, to: true) do
        @logger.info("message")
      end
    ensure
      @logger.stop_broadcasting_to(my_logger)
    end

    test "#silence does not break custom loggers" do
      new_logger = FakeLogger.new
      custom_logger = CustomLogger.new
      assert_respond_to new_logger, :silence
      assert_not_respond_to custom_logger, :silence

      logger = BroadcastLogger.new
      logger.broadcast_to(custom_logger, new_logger)

      logger.silence do
        logger.error "from error"
        logger.unknown "from unknown"
      end

      assert_equal [[::Logger::ERROR, "from error", nil], [::Logger::UNKNOWN, "from unknown", nil]], custom_logger.adds
      assert_equal [[::Logger::ERROR, "from error", nil], [::Logger::UNKNOWN, "from unknown", nil]], new_logger.adds
    end

    test "#silence silences all loggers below the default level of ERROR" do
      logger.silence do
        logger.debug "test"
      end

      assert_equal [], log1.adds
      assert_equal [], log2.adds
    end

    test "#silence does not silence at or above ERROR" do
      logger.silence do
        logger.error "from error"
        logger.unknown "from unknown"
      end

      assert_equal [[::Logger::ERROR, "from error", nil], [::Logger::UNKNOWN, "from unknown", nil]], log1.adds
      assert_equal [[::Logger::ERROR, "from error", nil], [::Logger::UNKNOWN, "from unknown", nil]], log2.adds
    end

    test "#silence allows you to override the silence level" do
      logger.silence(::Logger::FATAL) do
        logger.error "unseen"
        logger.fatal "seen"
      end

      assert_equal [[::Logger::FATAL, "seen", nil]], log1.adds
      assert_equal [[::Logger::FATAL, "seen", nil]], log2.adds
    end

    test "stop broadcasting to a logger" do
      @logger.stop_broadcasting_to(@log2)

      @logger.info("Hello")

      assert_equal([[1, "Hello", nil]], @log1.adds)
      assert_empty(@log2.adds)
    end

    test "can broadcast to another broadcast" do
      @log3 = FakeLogger.new
      @log4 = FakeLogger.new
      @broadcast2 = ActiveSupport::BroadcastLogger.new
      @broadcast2.broadcast_to(@log3, @log4)

      @logger.broadcast_to(@broadcast2)
      @logger.info("Hello")

      assert_equal([[1, "Hello", nil]], @log1.adds)
      assert_equal([[1, "Hello", nil]], @log2.adds)
      assert_equal([[1, "Hello", nil]], @log3.adds)
      assert_equal([[1, "Hello", nil]], @log4.adds)
    end

    class CustomLogger
      attr_reader :adds, :closed, :chevrons
      attr_accessor :level, :progname, :formatter, :local_level

      def initialize
        @adds        = []
        @closed      = false
        @chevrons    = []
        @level       = ::Logger::DEBUG
        @local_level = ::Logger::DEBUG
        @progname    = nil
        @formatter   = nil
      end

      def debug(message, &block)
        add(::Logger::DEBUG, message, &block)
      end

      def info(message, &block)
        add(::Logger::INFO, message, &block)
      end

      def warn(message, &block)
        add(::Logger::WARN, message, &block)
      end

      def error(message, &block)
        add(::Logger::ERROR, message, &block)
      end

      def fatal(message, &block)
        add(::Logger::FATAL, message, &block)
      end

      def unknown(message, &block)
        add(::Logger::UNKNOWN, message, &block)
      end

      def <<(x)
        @chevrons << x
      end

      def add(message_level, message = nil, progname = nil, &block)
        @adds << [message_level, message, progname] if message_level >= local_level
      end

      def close
        @closed = true
      end
    end

    class FakeLogger < CustomLogger
      include ActiveSupport::LoggerSilence

      # LoggerSilence includes LoggerThreadSafeLevel which defines these as
      # methods, so we need to redefine them
      attr_accessor :level, :local_level
    end
  end
end
