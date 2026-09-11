require "../expression/expression"

require "pg"
require "db"
require "crypto/bcrypt/password"

require "./errors"
require "./logger"
require "./transaction"

# Add a field to DB::Database to track the transaction state of a specific
# connection.
abstract class DB::Connection
  # Add a getter for the transaction status of this DB::Connection.
  property? _in_transaction : Bool = false
end

module Lustra
  #
  # ## Lustra::SQL
  #
  # Lustra is made like an onion:
  #
  # ```
  # +------------------------------------+
  # |          THE ORM STACK             +
  # +------------------------------------+
  # |  Model | DB Views |  Migrations    | < High Level Tools
  # +---------------+--------------------+
  # |  Columns | Validation | Converters | < Mapping system
  # +---------------+--------------------+
  # |  Lustra::SQL  | Lustra::Expression | < Low Level SQL Builder
  # +------------------------------------+
  # |  Crystal DB   |    Crystal PG      | < Low Level connection
  # +------------------------------------+
  # ```
  #
  # At the bottom of the stack, Lustra offers SQL query building.
  # These features are then used by higher-level parts of the engine.
  #
  # The SQL module provides a simple API to generate `delete`, `insert`, `select`
  # and `update` methods.
  #
  # Each request can be duplicated, modified, and executed.
  #
  # Note: Each request object is mutable. To update and store a request, manually
  # use the `dup` method.
  #
  module SQL
    extend self

    include Lustra::SQL::Logger
    include Lustra::SQL::Transaction

    alias Any = Array(PG::BoolArray) | Array(PG::CharArray) | Array(PG::Float32Array) |
                Array(PG::Float64Array) | Array(PG::Int16Array) | Array(PG::Int32Array) |
                Array(PG::Int64Array) | Array(PG::StringArray) | Array(PG::TimeArray) |
                Array(PG::UUIDArray) | Array(PG::NumericArray) |
                Bool | Char | Float32 | Float64 | Int8 | Int16 | Int32 | Int64 | BigDecimal | JSON::Any | JSON::PullParser | PG::Geo::Box | PG::Geo::Circle |
                PG::Geo::Line | PG::Geo::LineSegment | PG::Geo::Path | PG::Geo::Point |
                PG::Geo::Polygon | PG::Numeric | PG::Interval | Slice(UInt8) | String | Time |
                PG::Range(Int32) | PG::Range(Int64) | PG::Range(PG::Numeric) | PG::Range(Time) |
                Range(Int32?, Int32?) | Range(Int64?, Int64?) | Range(PG::Numeric?, PG::Numeric?) | Range(Time?, Time?) |
                Array(PG::Range(Int32)) | Array(PG::Range(Int64)) | Array(PG::Range(PG::Numeric)) | Array(PG::Range(Time)) |
                Array(Range(Int32?, Int32?)) | Array(Range(Int64?, Int64?)) | Array(Range(PG::Numeric?, PG::Numeric?)) | Array(Range(Time?, Time?)) |
                UInt8 | UInt16 | UInt32 | UInt64 | UUID | ::Crypto::Bcrypt::Password |
                Lustra::Expression::UnsafeSql | Lustra::Expression::Literal?

    alias Symbolic = String | Symbol
    alias Selectable = Symbolic | Lustra::SQL::SelectBuilder

    # Sanitize string and convert some literals (e.g. `Time`)
    def sanitize(x)
      Lustra::Expression[x]
    end

    # This provides a fast way to create SQL fragments while escaping items, both
    # with the `?` and `:key` systems:
    #
    # ```
    # query = Model.query.select(Lustra::SQL.raw("CASE WHEN x=:x THEN 1 ELSE 0 END AS check", x: "blabla"))
    # query = Model.query.select(Lustra::SQL.raw("CASE WHEN x=? THEN 1 ELSE 0 END AS check", "blabla"))
    # ```
    def raw(x, *params)
      Lustra::Expression.raw(x, *params)
    end

    # See `self.raw`
    # Can pass an array to this version
    def raw_enum(x, params : Enumerable(T)) forall T
      Lustra::Expression.raw_enum(x, params)
    end

    def raw(__template, **params)
      Lustra::Expression.raw(__template, **params)
    end

    # Escape the expression, double quoting it.
    #
    # It allows use of reserved keywords as table or column names.
    # NOTE: Escape is used for escaping PostgreSQL keywords. For example,
    # if you have a column named order (which is a reserved word), you need
    # to escape it by double-quoting it.
    #
    # For escaping STRING value, please use Lustra::SQL.sanitize
    def escape(x : String | Symbol)
      "\"" + x.to_s.gsub("\"", "\"\"") + "\""
    end

    def unsafe(x)
      Lustra::Expression::UnsafeSql.new(x)
    end

    def init(url : String)
      Lustra::SQL::ConnectionPool.init(url, "default")
    end

    def init(name : String, url : String)
      Lustra::SQL::ConnectionPool.init(url, name)
    end

    def init(connections : Hash(Symbolic, String))
      connections.each do |name, url|
        Lustra::SQL::ConnectionPool.init(url, name)
      end
    end

    def add_connection(name : String, url : String)
      Lustra::SQL::ConnectionPool.init(url, name)
    end

    @@savepoint_uid : UInt64 = 0_u64

    # Create a transaction, but this one is stackable
    # using savepoints.
    #
    # Example:
    #
    # ```
    # Lustra::SQL.with_savepoint do
    #   # do something
    #   Lustra::SQL.with_savepoint do
    #     rollback # < Rollback only the last `with_savepoint` block
    #   end
    # end
    # ```
    def with_savepoint(connection_name = "default", &)
      transaction(connection_name) do |cnx|
        sp_name = "sp_#{@@savepoint_uid += 1}"
        begin
          execute(connection_name, "SAVEPOINT #{sp_name}")
          yield
          execute(connection_name, "RELEASE SAVEPOINT #{sp_name}") if cnx._in_transaction?
        rescue RollbackError
          execute(connection_name, "ROLLBACK TO SAVEPOINT #{sp_name}") if cnx._in_transaction?
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
    # Lustra::SQL.execute("SELECT 1 FROM users")
    #
    def execute(sql)
      execute("default", sql)
    end

    # Execute a SQL statement on a specific connection.
    #
    # Usage:
    # Lustra::SQL.execute("seconddatabase", "SELECT 1 FROM users")
    def execute(connection_name : String, sql)
      log_query(sql) { Lustra::SQL::ConnectionPool.with_connection(connection_name, &.exec_all(sql)) }
    end

    # :nodoc:
    def sel_str(s : Selectable)
      s.is_a?(Symbolic) ? s.to_s : s.to_sql
    end

    # Start a DELETE table query
    def delete(table : Symbolic)
      Lustra::SQL::DeleteQuery.new.from(table)
    end

    # Start an INSERT INTO table query
    #
    # ```
    # Lustra::SQL.insert_into("table", {id: 1, name: "hello"}, {id: 2, name: "World"})
    # ```
    def insert_into(table : Symbolic, *args)
      Lustra::SQL::InsertQuery.new(table).values(*args)
    end

    # Prepare a new INSERT INTO table query
    # :ditto:
    def insert_into(table : Symbolic)
      Lustra::SQL::InsertQuery.new(table)
    end

    # Create a new INSERT query
    def insert
      Lustra::SQL::InsertQuery.new
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
      Lustra::SQL::UpdateQuery.new(table)
    end

    # Start a SELECT FROM table query
    def select(*args)
      if args.size > 0
        Lustra::SQL::SelectQuery.new.select(*args)
      else
        Lustra::SQL::SelectQuery.new
      end
    end
  end
end

require "./select_query"
require "./delete_query"
require "./insert_query"
require "./update_query"

require "./fragment/*"
