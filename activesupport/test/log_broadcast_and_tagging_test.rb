# frozen_string_literal: true

require_relative "abstract_unit"

class LogBroadcastAndTaggingTest < ActiveSupport::TestCase
  setup do
    @sink1 = StringIO.new
    @sink2 = StringIO.new
    @logger1 = Logger.new(@sink1, formatter: ActiveSupport::Logger::SimpleFormatter.new)
    @logger2 = Logger.new(@sink2, formatter: ActiveSupport::Logger::SimpleFormatter.new)

    @broadcast = ActiveSupport::BroadcastLogger.new(@logger1, @logger2)
  end

  test "tag logs for the whole broadcast with a block" do
    @broadcast.extend(ActiveSupport::TaggedLogging)

    @broadcast.tagged("BMX") { @broadcast.info("Hello") }

    assert_equal("[BMX] Hello\n", @sink1.string)
    assert_equal("[BMX] Hello\n", @sink2.string)
  end

  test "tag logs for the whole broadcast without a block" do
    @broadcast.extend(ActiveSupport::TaggedLogging)

    @broadcast.tagged("BMX").info("Hello")

    assert_equal("[BMX] Hello\n", @sink1.string)
    assert_equal("[BMX] Hello\n", @sink2.string)
  end

  test "tag logs only for one sink" do
    @logger1.extend(ActiveSupport::TaggedLogging)
    @logger1.push_tags("BMX")

    @broadcast.info { "Hello" }

    assert_equal("[BMX] Hello\n", @sink1.string)
    assert_equal("Hello\n", @sink2.string)
  end

  test "tag logs for the whole broadcast and extra tags are added to one sink" do
    @broadcast.extend(ActiveSupport::TaggedLogging)
    @logger1.extend(ActiveSupport::TaggedLogging)
    @logger1.push_tags("APP")

    @broadcast.tagged("BMX") { @broadcast.info("Hello") }

    assert_equal("[BMX] [APP] Hello\n", @sink1.string)
    assert_equal("[BMX] Hello\n", @sink2.string)
  end

  test "can broadcast to another broadcast logger with tagging functionalities" do
    @sink3 = StringIO.new
    @sink4 = StringIO.new
    @logger3 = Logger.new(@sink3, formatter: ActiveSupport::Logger::SimpleFormatter.new)
    @logger4 = Logger.new(@sink4, formatter: ActiveSupport::Logger::SimpleFormatter.new)
    @broadcast2 = ActiveSupport::BroadcastLogger.new(@logger3, @logger4)

    @broadcast.broadcast_to(@broadcast2)

    @broadcast.extend(ActiveSupport::TaggedLogging)
    @broadcast2.extend(ActiveSupport::TaggedLogging)

    @broadcast2.push_tags("BROADCAST2")

    @broadcast.tagged("BMX") { @broadcast.info("Hello") }

    assert_equal("[BMX] Hello\n", @sink1.string)
    assert_equal("[BMX] Hello\n", @sink2.string)
    assert_equal("[BMX] [BROADCAST2] Hello\n", @sink3.string)
    assert_equal("[BMX] [BROADCAST2] Hello\n", @sink4.string)
  end
end
