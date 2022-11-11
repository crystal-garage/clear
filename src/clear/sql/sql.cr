require "../expression/expression"

require "pg"
require "db"
require "crypto/bcrypt/password"

require "./errors"
require "./logger"
require "./transaction"

# Add a field to DB::Database to handle
#   the state of transaction of a specific
#   connection
abstract class DB::Connection
  # add getter to transaction status for this specific DB::Connection
  property? _clear_in_transaction : Bool = false
end

module Clear
  #
  # ## Clear::SQL
  #
  # Clear is made like an onion:
  #
  # ```
  # +------------------------------------+
  # |           THE ORM STACK            +
  # +------------------------------------+
  # |  Model | DB Views | Migrations     | < High Level Tools
  # +---------------+--------------------+
  # |  Columns | Validation | Converters | < Mapping system
  # +---------------+--------------------+
  # |  Clear::SQL   | Clear::Expression  | < Low Level SQL Builder
  # +------------------------------------+
  # |  Crystal DB   | Crystal PG         | < Low Level connection
  # +------------------------------------+
  # ```
  #
  # On the bottom stack, Clear offer SQL query building.
  # Theses features are then used by top level parts of the engine.
  #
  # The SQL module provide a simple API to generate `delete`, `insert`, `select`
  # and `update` methods.
  #
  # Each requests can be duplicated then modified and executed.
  #
  # Note: Each request object is mutable. Therefore, to update and store a request,
  # you must use manually the `dup` method.
  #
  module SQL
    alias Any = Array(PG::BoolArray) | Array(PG::CharArray) | Array(PG::Float32Array) |
                Array(PG::Float64Array) | Array(PG::Int16Array) | Array(PG::Int32Array) |
                Array(PG::Int64Array) | Array(PG::StringArray) | Array(PG::TimeArray) |
                Array(PG::UUIDArray) | Array(PG::NumericArray) |
                Bool | Char | Float32 | Float64 | Int8 | Int16 | Int32 | Int64 | BigDecimal | JSON::Any | JSON::PullParser | PG::Geo::Box | PG::Geo::Circle |
                PG::Geo::Line | PG::Geo::LineSegment | PG::Geo::Path | PG::Geo::Point |
                PG::Geo::Polygon | PG::Numeric | PG::Interval | Slice(UInt8) | String | Time |
                UInt8 | UInt16 | UInt32 | UInt64 | UUID | ::Crypto::Bcrypt::Password |
                Clear::Expression::UnsafeSql | Clear::Expression::Literal |
                Clear::TimeInDay | Clear::Interval |
                Nil

    include Clear::SQL::Logger
    include Clear::SQL::Transaction
    extend self

    alias Symbolic = String | Symbol
    alias Selectable = Symbolic | Clear::SQL::SelectBuilder

    # Sanitize string and convert some literals (e.g. `Time`)
    def sanitize(x)
      Clear::Expression[x]
    end

    # This provide a fast way to create SQL fragment while escaping items, both with `?` and `:key` system:
    #
    # ```
    # query = Mode.query.select(Clear::SQL.raw("CASE WHEN x=:x THEN 1 ELSE 0 END as check", x: "blabla"))
    # query = Mode.query.select(Clear::SQL.raw("CASE WHEN x=? THEN 1 ELSE 0 END as check", "blabla"))
    # ```
    def raw(x, *params)
      Clear::Expression.raw(x, *params)
    end

    # See `self.raw`
    # Can pass an array to this version
    def raw_enum(x, params : Enumerable(T)) forall T
      Clear::Expression.raw_enum(x, params)
    end

    def raw(__template, **params)
      Clear::Expression.raw(__template, **params)
    end

    # Escape the expression, double quoting it.
    #
    # It allows use of reserved keywords as table or column name
    # NOTE: Escape is used for escaping postgresql keyword. For example
    # if you have a column named order (which is a reserved word), you want
    # to escape it by double-quoting it.
    #
    # For escaping STRING value, please use Clear::SQL.sanitize
    def escape(x : String | Symbol)
      "\"" + x.to_s.gsub("\"", "\"\"") + "\""
    end

    def unsafe(x)
      Clear::Expression::UnsafeSql.new(x)
    end

    def init(url : String)
      Clear::SQL::ConnectionPool.init(url, "default")
    end

    def init(name : String, url : String)
      Clear::SQL::ConnectionPool.init(url, name)
    end

    def init(connections : Hash(Symbolic, String))
      connections.each do |name, url|
        Clear::SQL::ConnectionPool.init(url, name)
      end
    end

    def add_connection(name : String, url : String)
      Clear::SQL::ConnectionPool.init(url, name)
    end

    @@savepoint_uid : UInt64 = 0_u64

    # Create a transaction, but this one is stackable
    # using savepoints.
    #
    # Example:
    #
    # ```
    # Clear::SQL.with_savepoint do
    #   # do something
    #   Clear::SQL.with_savepoint do
    #     rollback # < Rollback only the last `with_savepoint` block
    #   end
    # end
    # ```
    def with_savepoint(connection_name = "default", &block)
      transaction do |cnx|
        sp_name = "sp_#{@@savepoint_uid += 1}"
        begin
          execute(connection_name, "SAVEPOINT #{sp_name}")
          yield
          execute(connection_name, "RELEASE SAVEPOINT #{sp_name}") if cnx._clear_in_transaction?
        rescue e : RollbackError
          execute(connection_name, "ROLLBACK TO SAVEPOINT #{sp_name}") if cnx._clear_in_transaction?
        end
      end
    end

    # Raise a rollback, in case of transaction
    def rollback
      raise RollbackError.new
    end

    # Execute a SQL statement.
    #
    # Usage:
    # Clear::SQL.execute("SELECT 1 FROM users")
    #
    def execute(sql)
      execute("default", sql)
    end

    # Execute a SQL statement on a specific connection.
    #
    # Usage:
    # Clear::SQL.execute("seconddatabase", "SELECT 1 FROM users")
    def execute(connection_name : String, sql)
      log_query(sql) { Clear::SQL::ConnectionPool.with_connection(connection_name, &.exec_all(sql)) }
    end

    # :nodoc:
    def sel_str(s : Selectable)
      s.is_a?(Symbolic) ? s.to_s : s.to_sql
    end

    # Start a DELETE table query
    def delete(table : Symbolic)
      Clear::SQL::DeleteQuery.new.from(table)
    end

    # Start an INSERT INTO table query
    #
    # ```
    # Clear::SQL.insert_into("table", {id: 1, name: "hello"}, {id: 2, name: "World"})
    # ```
    def insert_into(table : Symbolic, *args)
      Clear::SQL::InsertQuery.new(table).values(*args)
    end

    # Prepare a new INSERT INTO table query
    # :ditto:
    def insert_into(table : Symbolic)
      Clear::SQL::InsertQuery.new(table)
    end

    # Create a new INSERT query
    def insert
      Clear::SQL::InsertQuery.new
    end

    # Alias of `insert_into`, for hurry developers
    def insert(table, *args)
      insert_into(table, *args)
    end

    def insert(table, args : NamedTuple)
      insert_into(table, args)
    end

    # Start a UPDATE table query
    def update(table)
      Clear::SQL::UpdateQuery.new(table)
    end

    # Start a SELECT FROM table query
    def select(*args)
      if args.size > 0
        Clear::SQL::SelectQuery.new.select(*args)
      else
        Clear::SQL::SelectQuery.new
      end
    end
  end
end

require "./select_query"
require "./delete_query"
require "./insert_query"
require "./update_query"

require "./fragment/*"
