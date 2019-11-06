# frozen_string_literal: true

module ActiveRecord
  module Sharding
    module Integration
      extend self

      def take_over(base)
        ::ActiveRecord::ConnectionHandling.instance_methods.each do |meth|
          ::ActiveRecord::ConnectionHandling.remove_method(meth)
        end

        base.singleton_class.class_eval do
          remove_method :connection_handler
          remove_method :connection_handler=
        end

        use_new_connection_handling(base)
        modify_schema_migration(base)
      end

      def use_new_connection_handling(base)
        base.extend(Sharding::ConnectionHandling)

        base.default_connection_handler = Sharding::ConnectionAdapters::ConnectionHandler.new
        base.connection_handlers = { "ActiveRecord::Base" => base.default_connection_handler }
        base.establish_connection
      end

      def modify_schema_migration(base)
        ::ActiveRecord::ConnectionAdapters::AbstractAdapter.class_eval do
          def schema_migration
            @schema_migration ||= begin
                                   superclass = find_connection_handler
                                   if superclass == ActiveRecord::Base
                                     ActiveRecord::SchemaMigration
                                   else
                                     name = "#{pool.db_config.spec_name}::SchemaMigration"

                                     Class.new(superclass) do
                                       define_singleton_method(:name) { name }
                                       define_singleton_method(:to_s) { name }

                                       include ActiveRecord::SchemaMigration::Concern
                                     end
                                   end
                                 end
          end

          def find_connection_handler
            ActiveRecord::Base.connection_handlers.each do |name, handler|
              handler.connection_pools.each do |pool|
                return name.constantize if pool == self.pool
              end
            end
            raise ConnectionNotEstablished, "Couldn't find an active connection for #{pool.db_config.spec_name.inspect}"
          end
        end
      end
    end
  end
end
