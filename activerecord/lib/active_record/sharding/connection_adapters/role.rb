# frozen_string_literal: true

module ActiveRecord
  module Sharding
    module ConnectionAdapters
      class Role # :nodoc:
        include Mutex_m

        attr_reader :db_config, :name
        attr_accessor :schema_cache

        INSTANCES = ObjectSpace::WeakMap.new
        private_constant :INSTANCES

        class << self
          def discard_pools!
            INSTANCES.each_key(&:discard_pool!)
          end
        end

        def initialize(name, db_config)
          super()
          @name = name
          @db_config = db_config
          @pool = nil
          INSTANCES[self] = self
        end

        def disconnect!
          ActiveSupport::ForkTracker.check!

          return unless @pool

          synchronize do
            return unless @pool

            @pool.automatic_reconnect = false
            @pool.disconnect!
          end

          nil
        end

        def pool
          ActiveSupport::ForkTracker.check!

          @pool || synchronize { @pool ||= ::ActiveRecord::ConnectionAdapters::ConnectionPool.new(self) }
        end

        def discard_pool!
          return unless @pool

          synchronize do
            return unless @pool

            @pool.discard!
            @pool = nil
          end
        end
      end
    end
  end
end

ActiveSupport::ForkTracker.after_fork { ActiveRecord::Sharding::ConnectionAdapters::Role.discard_pools! }
