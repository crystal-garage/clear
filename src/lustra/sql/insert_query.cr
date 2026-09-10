require "pg"
require "big"

require "./query/*"

#
# An insert query
#
# cf. PostgreSQL documentation
#
# ```
# [ WITH [ RECURSIVE ] with_query [, ...] ]
# INSERT INTO table_name [ AS alias ] [ ( column_name [, ...] ) ]
#    { DEFAULT VALUES | VALUES ( { expression | DEFAULT } [, ...] ) [, ...] | query }
#    [ ON CONFLICT [ conflict_target ] conflict_action ]
#    [ RETURNING * | output_expression [ [ AS ] output_name ] [, ...] ]
# ```
class Lustra::SQL::InsertQuery
  include Lustra::SQL::Query::CTE
  include Query::Change
  include Query::Connection
  include Query::OnConflict
  include Query::Returning

  alias Inserable = ::Lustra::SQL::Any | BigInt | BigFloat | Time
  getter keys : Array(Symbolic) = [] of Symbolic
  getter values : SelectBuilder | Array(Array(Inserable)) = [] of Array(Inserable)
  getter! table : Symbol | String

  def initialize
  end

  def initialize(@table : Symbol | String)
  end

  def initialize(@table : Symbol | String, values)
    self.values(values)
  end

  def into(@table : Symbol | String)
    change!
  end

  def execute(connection_name : String? = nil) : Hash(String, ::Lustra::SQL::Any)
    o = {} of String => ::Lustra::SQL::Any

    if @returning.nil?
      s = to_sql
      Lustra::SQL.execute(connection_name || self.connection_name, s)
    else
      fetch(connection_name) { |x| o = x }
    end

    o
  end

  # Run the insert and return the number of rows affected.
  def execute_and_count(connection_name : String? = nil) : Int64
    sql = to_sql
    Lustra::SQL.log_query(sql) do
      Lustra::SQL::ConnectionPool.with_connection(connection_name || self.connection_name, &.exec(sql).rows_affected)
    end
  end

  def clear_values
    @values = [] of Array(Inserable)

    change!
  end

  # Fast insert system
  #
  # insert({field: "value"}).into(:table)
  #
  def values(row : NamedTuple)
    append_row(row)
  end

  def values(row : Hash(Symbolic, Inserable))
    append_row(row)
  end

  private def append_row(row)
    case v = @values
    when Array(Array(Inserable))
      values_by_column = row.to_h.transform_keys(&.to_s)
      keys = v.empty? ? row.keys.to_a.map(&.as(Symbolic)) : @keys

      unless keys.size == values_by_column.size && keys.all? { |key| values_by_column.has_key?(key.to_s) }
        raise QueryBuildingError.new("All insert rows must have the same columns")
      end

      @keys = keys
      v << keys.map { |key| values_by_column[key.to_s].as(Inserable) }
    else # when SelectBuilder
      raise "Cannot insert both from SELECT query and from data"
    end

    change!
  end

  def values(rows : Array(NamedTuple))
    rows.each do |nt|
      values(nt)
    end

    change!
  end

  def values(rows : Array(Hash(Symbolic, Inserable)))
    rows.each do |nt|
      values(nt)
    end

    change!
  end

  # Used with values
  def columns(*args)
    @keys = args

    change!
  end

  def values(*args)
    @values << args

    change!
  end

  # Insert into ... (...) SELECT
  def values(select_query : SelectBuilder)
    if @values.is_a?(Array) && @values.as(Array).present?
      raise QueryBuildingError.new "Cannot insert both from SELECT and from data"
    end

    @values = select_query

    change!
  end

  # Number of rows in this insertion request.
  def size : Int32
    v = @values
    v.is_a?(Array) ? v.size : -1
  end

  protected def print_keys
    !@keys.empty? ? "(" + @keys.join(", ") { |x| Lustra::SQL.escape(x.to_s) } + ")" : nil
  end

  protected def print_values
    v = @values.as(Array(Array(Inserable)))

    v.each_with_index.join(",\n") do |row, idx|
      raise QueryBuildingError.new "No value to insert (at row ##{idx})" if row.empty?

      "(" + row.join(", ") { |x| Lustra::Expression[x] } + ")"
    end
  end

  def to_sql
    raise QueryBuildingError.new "You must provide a `into` clause" unless table = @table

    table = table.is_a?(Symbol) ? Lustra::SQL.escape(table) : table

    o = [print_ctes, "INSERT INTO", table, print_keys]
    v = @values
    case v
    when SelectBuilder
      o << "(" + v.to_sql + ")"
    else
      if v.empty? || (v.size == 1 && v[0].empty?) # < Case happening with model
        o << "DEFAULT VALUES"
      else
        o << "VALUES"
        o << print_values
      end
    end

    print_on_conflict(o)

    append_returning(o).compact.join(" ")
  end
end
