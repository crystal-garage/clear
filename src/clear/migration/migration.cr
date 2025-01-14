# # Clear's migration system
#
# Migrations in Clear are very similar to active record's migrations.
# Migrations are two-way modification of the database.
#
# It helps to keep a consistent database state during development lifecycle
# of your application.
#
# To create a migration, two ways:
#
# ## Clear command
#
# ### TL;DR
#
# You can create a new file which will be present in `src/db/migrate` using:
#
# `clear-cli migration:g migration_name`
#
# Thus will create a migration in `src/db/migration/[:uid]_migration_name.cr`
# (with uid number) and a class `MigrationName`
#
# ### Advanced options
#
# You can use `clear-cli migration help` to get advanced options.
#
# ## Manually
#
# You can create a class following this naming convention:
# `Anything + Number.`
# The number is then used to order the migration between each others and must be unique.
#
# Following the rule than inclusion is often better than inheritance, just
# include the module `Clear::Migration` to your class.
#
# ## Methods of migration
#
# ### Migration direction
#
# Only one method must be overrided: `change`. In comparison to ActiveRecord, there's no
# up and down methods, instead you can put specific up/down code like this:
#
# ```
# def change(dir)
#   dir.down { irreversible! }
# end
# ```
#
# ```
# def change(dir)
#   add_column :users, :full_name, :string
#
#   dir.up do
#     execute("UPDATE users SET full_name = (SELECT first_name || ' '  || last_name) from users")
#   end
# end
# ```
module Clear::Migration
  Log = ::Log.for("clear.migration")

  include Clear::ErrorMessages

  abstract def uid : Int64

  # This error is throw when you try to revert a migration which is irreversible.
  class IrreversibleMigration < Exception; end

  module Helper
    TYPE_MAPPING = {
      "string" => "text",
      "int32"  => "int",

      "int64"      => "bigint",
      "long"       => "bigint",
      "bigdecimal" => "numeric",

      "datetime" => "timestamp without time zone",
    }

    # Replace some common type to their equivalent in postgresql
    # if the type is not found in the correspondance table, then return
    # itself
    def self.datatype(type : String)
      ts = type
      TYPE_MAPPING[type]? || ts
    end

    def irreversible!
      raise IrreversibleMigration.new(migration_irreversible(self.class.name))
    end

    def execute(sql : String)
      @operations << Clear::Migration::Execute.new(sql)
    end

    def add_operation(op : Operation)
      op.migration = self
      @operations << op
    end

    abstract def change(dir)

    # This will apply the migration in a given direction (up or down)
    def apply(dir : Direction = Clear::Migration::Direction::Up)
      Clear::Migration::Manager.instance.ensure_ready

      Clear::SQL.transaction do
        Log.info { "[#{dir}] #{self.class.name}" }

        # In case the migration is called twice (e.g. in Spec?)
        # ensure the operations are clean-up before trying again
        @operations.clear

        change(dir)

        dir.up do
          @operations.each do |op|
            op.up.each { |x| Clear::SQL.execute(x.as(String)) }
          end

          SQL.insert("__clear_metadatas", {metatype: "migration", value: uid.to_s}).execute
        end

        dir.down do
          @operations.reverse_each do |op|
            op.down.each { |x| Clear::SQL.execute(x.as(String)) }
          end

          SQL.delete("__clear_metadatas").where({metatype: "migration", value: uid.to_s}).execute
        end

        self
      end
    end
  end

  include Helper

  macro included
    @operations : Array(Operation) = [] of Operation

    # Return the migration number (Unique ID or UID) for migration sorting.
    #
    # Default behavior (By order of priority):
    #
    # - The uid will be generated by the class name, if the class name contains number at the end.
    # - If there's no numbers in the migration class, then it will try to use the id in the filename
    # - If not found, an exception is raised. This method can be overwritten by the concrete migration in case you need it.
    #
    # Example:
    #
    # `class MyMigration1234567 # << Order = 1234567`
    # `file db/1234567_my_migration.cr # << Order = 1234567`
    def uid : Int64
      Int64.new(begin
        filename = File.basename(__FILE__)

        if self.class.name =~ /[0-9]+$/
          self.class.name[/[0-9]+$/]
        elsif filename =~ /^[0-9]+/
          filename[/^[0-9]+/]
        else
          raise uid_not_found(self.class.name)
        end
      end)
    end
  end

  macro included
    Clear::Migration::Manager.instance.add(new)
  end
end

# :nodoc:
# This class is here to prevent bug #5705
# and will be removed when the bug is fixed
class DummyMigration
  include Clear::Migration

  def uid : Int64
    -0x01_i64
  end

  def change(dir)
    # Nothing
  end
end

require "./operation"
