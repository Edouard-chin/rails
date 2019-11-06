# frozen_string_literal: true

module ActiveRecord
  module Sharding
    module ConnectionAdapters
      class ConnectionHandler
        FINALIZER = lambda { |_| ActiveSupport::ForkTracker.check! }
        private_constant :FINALIZER

        def initialize
          # These caches are keyed by spec.name (ConnectionSpecification#name).
          @roles = Concurrent::Map.new(initial_capacity: 2)

          # Backup finalizer: if the forked child skipped Kernel#fork the early discard has not occurred
          ObjectSpace.define_finalizer self, FINALIZER
        end

        def current_role
          current_roles[object_id]
        end

        def with_role(role)
          old_role, current_roles[object_id] = current_role, role
          yield
        ensure
          current_roles[object_id] = old_role
        end

        def prevent_writes # :nodoc:
          Thread.current[:prevent_writes]
        end

        def prevent_writes=(prevent_writes) # :nodoc:
          Thread.current[:prevent_writes] = prevent_writes
        end

        # Prevent writing to the database regardless of role.
        #
        # In some cases you may want to prevent writes to the database
        # even if you are on a database that can write. `while_preventing_writes`
        # will prevent writes to the database for the duration of the block.
        def while_preventing_writes(enabled = true)
          original, self.prevent_writes = self.prevent_writes, enabled
          yield
        ensure
          self.prevent_writes = original
        end

        def connection_pool_names # :nodoc:
          roles.keys
        end

        def connection_pool_list
          roles.values.compact.map(&:pool)
        end
        alias :connection_pools :connection_pool_list

        def establish_connection(config, role: nil)
          resolver = Resolver.new(Base.configurations)
          role = resolver.resolve_role(config, role: role)

          remove_connection(role.name)

          message_bus = ActiveSupport::Notifications.instrumenter
          payload = {
            connection_id: object_id,
            config: role.db_config.configuration_hash,
          }
          roles[role.name] = role

          message_bus.instrument("!connection.active_record", payload) do
            role.pool
          end
        end

        # Returns true if there are any active connections among the connection
        # pools that the ConnectionHandler is managing.
        def active_connections?
          connection_pool_list.any?(&:active_connection?)
        end

        # Returns any connections in use by the current thread back to the pool,
        # and also returns connections to the pool cached by threads that are no
        # longer alive.
        def clear_active_connections!
          connection_pool_list.each(&:release_connection)
        end

        # Clears the cache which maps classes.
        #
        # See ConnectionPool#clear_reloadable_connections! for details.
        def clear_reloadable_connections!
          connection_pool_list.each(&:clear_reloadable_connections!)
        end

        def clear_all_connections!
          connection_pool_list.each(&:disconnect!)
        end

        # Disconnects all currently idle connections.
        #
        # See ConnectionPool#flush! for details.
        def flush_idle_connections!
          connection_pool_list.each(&:flush!)
        end

        # Locate the connection of the nearest super class. This can be an
        # active or defined connection: if it is the latter, it will be
        # opened and set as the active connection for the class it was defined
        # for (not necessarily the current class).
        def retrieve_connection(role) #:nodoc:
          pool = retrieve_connection_pool(role)

          unless pool
            # multiple database application
            if connection_pool_list.any?
              database_name = connection_pool_list.first.db_config.database
              raise ConnectionNotEstablished, "No connection pool for '#{role}' role found for the '#{database_name}' database."
            else
              raise ConnectionNotEstablished, "No connection pool for '#{role}' role found."
            end
          end

          pool.connection
        end

        # Returns true if a connection that's accessible to this class has
        # already been opened.
        def connected?(role)
          retrieve_connection_pool(role)&.connected?
        end

        # Remove the connection for this class. This will close the active
        # connection and the defined connection (if they exist). The result
        # can be used as an argument for #establish_connection, for easily
        # re-establishing the connection.
        def remove_connection(role)
          if role_object = roles.delete(role)
            role_object.disconnect!
            role_object.db_config.configuration_hash
          end
        end

        # Retrieving the connection pool happens a lot, so we cache it in @roles.
        # This makes retrieving the connection pool O(1) once the process is warm.
        # When a connection is established or removed, we invalidate the cache.
        def retrieve_connection_pool(role)
          roles[role]&.pool
        end

        private
        attr_reader :roles

        def current_roles
          roles = Thread.current.thread_variable_get(:ar_current_roles)
          roles || Thread.current.thread_variable_set(:ar_current_roles, {})
        end

        def current_role=(role)
          current_roles[object_id] = role
        end
      end
    end
  end
end
