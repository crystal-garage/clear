# ## Lustra's Expression engine
#
# The goal of this module is to offer the most natural way to write queries in
# Crystal.
#
# If you're familiar with Sequel in Ruby, this should feel familiar.
#
# Instead of writing:
#
# ```
# model_collection.where("created_at BETWEEN ? AND ?", 1.day.ago, DateTime.local)
# ```
#
# You can write:
# ```
# model_collection.where { created_at.between?(1.day.ago, DateTime.local) }
# ```
#
# or even:
#
# ```
# model_collection.where { created_at.in?(1.day.ago..DateTime.local) }
# ```
#
# The latter generates `created_at > 1.day.ago AND created_at < DateTime.local`.
#
# ## Limitations
#
# Due to the use of the `missing_method` macro, some cases can be confusing.
#
# ### Existing local variable / instance method
#
# ```
# id = 1
# model_collection.where { id > 100 } # Raises an error, because the expression is resolved by Crystal.
# # Should be:
# id = 1
# model_collection.where { var("id") > 100 } # Works
# ```
#
# ### Usage of AND / OR
#
# AND/OR can be expressed using the bitwise operators `&` and `|`.
# Because `||` and `&&` cannot be reused, be aware that operator precedence
# rules are different.
#
# ```
# # v-- This will not work, as we cannot redefine the `or` operator
# model_collection.where { first_name == "yacine" || last_name == "petitprez" }
# # v-- This works, but parenthesize each term because `|` has priority over `==`
# model.collection.where { (first_name == "yacine") | (last_name == "petitprez") }
# # ^-- ... WHERE first_name = 'yacine' OR last_name == ''
# ```
#
class Lustra::Expression
  DATABASE_DATE_TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%L %:z"
  DATABASE_DATE_FORMAT      = "%Y-%m-%d"

  # Allow any type to be used in the expression engine by including
  # Lustra::Expression::Literal and defining `to_sql`.
  module Literal
    abstract def to_sql
    abstract def to_json(json : JSON::Builder)
  end

  # Wrap an unsafe string. Useful to bypass the internal safe_literal function.
  # Obviously, this can lead to SQL injection, so beware!
  class UnsafeSql
    include Literal

    @value : String

    def initialize(@value)
    end

    def to_s
      @value
    end

    def to_sql
      @value
    end

    def to_json(json = nil)
      @value
    end
  end

  alias AvailableLiteral = Int8 | Int16 | Int32 | Int64 | Float32 | Float64 |
                           UInt8 | UInt16 | UInt32 | UInt64 |
                           Literal | String | Symbol | Time | Bool?

  # A fast way to call `self.safe_literal`
  # See `safe_literal(x : _)`
  def self.[](arg)
    safe_literal(arg)
  end

  # :nodoc:
  def self.safe_literal(x : Number) : String
    x.to_s
  end

  # :nodoc:
  def self.safe_literal(x : Nil) : String
    "NULL"
  end

  # :nodoc:
  def self.safe_literal(x : String) : String
    {"'", x.gsub('\'', "''"), "'"}.join
  end

  # :nodoc:
  def self.safe_literal(x : ::Lustra::SQL::SelectBuilder)
    {"(", x.to_sql, ")"}
  end

  # :nodoc:
  def self.safe_literal(x : ::Lustra::Expression::Node)
    x.resolve
  end

  # Transform multiple objects into SQL-injection-safe string representations.
  def self.safe_literal(x : Array(AvailableLiteral)) : Array(String)
    x.map { |item| safe_literal(item) }
  end

  # Return an unsafe string injected into the query.
  # Can be used, for example, in `insert` query building.
  def self.unsafe(x)
    Lustra::Expression::UnsafeSql.new(x)
  end

  # Safe literal for Time returns a string representation in the format
  # understood by PostgreSQL.
  #
  # If the optional parameter `date` is passed, the time is truncated and only the date is passed:
  #
  # ## Example
  #
  # ```
  # Lustra::Expression[Time.local]             # < "2017-04-03 23:04:43.234 +08:00"
  # Lustra::Expression[Time.local, date: true] # < "2017-04-03"
  # ```
  def self.safe_literal(x : Time, date : Bool = false) : String
    {"'", x.to_utc.to_s(date ? DATABASE_DATE_FORMAT : DATABASE_DATE_TIME_FORMAT), "'"}.join
  end

  # :nodoc:
  def self.safe_literal(x : Bool) : String
    (x ? "TRUE" : "FALSE")
  end

  # :nodoc:
  def self.safe_literal(x : Node) : String
    x.resolve
  end

  # :nodoc:
  def self.safe_literal(x : UnsafeSql) : String
    x.to_s
  end

  # Sanitize an object and return a `String` representation that is protected
  # against SQL injection.
  def self.safe_literal(x : _) : String
    safe_literal(x.to_s)
  end

  # This method raises a compile-time error if discovered in the code.
  # This avoids issues like this:
  #
  # ```
  # id = 1
  # # ... and later
  # User.query.where { id == 2 }
  # ```
  #
  # In this case, the local variable `id` would be evaluated in the expression
  # engine, leading to buggy code.
  #
  # Having this method prevents the code from compiling.
  #
  # To pass a literal or values other than nodes, use `raw`.
  #
  def self.ensure_node!(any)
    {% raise \
         "The expression engine discovered a runtime-evaluable condition.\n" +
         "It happens when a test is done with values on both sides.\n" +
         "Maybe a local variable is breaking the expression engine like here:\n" +
         "id = 1\n" +
         "Users.where { id == nil }\n\n" +
         "In this case, please use `raw(\"id IS NULL\")` to allow the expression." %}
  end

  # :nodoc:
  def self.ensure_node!(node : Node) : Node
    node
  end

  # Return a node of the expression engine.
  # This node can then be combined with other nodes through the chaining engine,
  # e.g. `where {...}.where {...}`.
  def self.where(&) : Node
    expression_engine = new

    ensure_node!(with expression_engine yield)
  end

  # `NOT` operator
  #
  # Return a logically reversed version of the contained `Node`.
  #
  # ## Example
  #
  # ```
  # Lustra::Expression.where { not(a == b) }.resolve # >> "WHERE NOT( a = b )
  # ```
  def not(x : Node)
    Node::Not.new(x)
  end

  # If the variable name is a reserved word (e.g. `not`, `var`, `raw`) or if a
  # complex computation cannot be expressed with the expression engine (e.g.
  # function usage), use raw to pass the String.
  #
  # BE AWARE that the String is pasted AS-IS and can lead to SQL injection if not
  # used properly.
  #
  # ```
  # having { raw("COUNT(*)") > 5 }           # SELECT ... FROM ... HAVING COUNT(*) > 5
  # where { raw("func(?, ?) = ?", a, b, c) } # SELECT ... FROM ... WHERE function(a, b) = c
  # ```
  #
  def raw(x : String, *args)
    Node::Raw.new(self.class.raw(x, *args))
  end

  # If the variable name is a reserved word (e.g. `not`, `var`, `raw`) or if a
  # complex computation cannot be expressed with the expression engine (e.g.
  # function usage), use raw to pass the String.
  #
  # BE AWARE that the String is pasted AS-IS and can lead to SQL injection if not
  # used properly.
  #
  # ```
  # having { raw("COUNT(*)") > 5 }           # SELECT ... FROM ... HAVING COUNT(*) > 5
  # where { raw("func(?, ?) = ?", a, b, c) } # SELECT ... FROM ... WHERE function(a, b) = c
  # ```
  #
  def self.raw(x : String, *args)
    raw_enum(x, args)
  end

  # See `self.raw`
  # Can pass an array to this version.
  def self.raw_enum(x : String, args)
    idx = -1

    x.gsub("?") do |_|
      Lustra::Expression[args[idx += 1]]
    rescue e : IndexError
      raise Lustra::ErrorMessages.query_building_error(e.message)
    end
  end

  # If the variable name is a reserved word (e.g. `not`, `var`, `raw`) or if a
  # complex computation cannot be expressed with the expression engine (e.g.
  # function usage), use raw to pass the String.
  #
  # BE AWARE that the String is pasted AS-IS and can lead to SQL injection if not
  # used properly.
  #
  # ```
  # having { raw("COUNT(*)") > 5 }                       # SELECT ... FROM ... HAVING COUNT(*) > 5
  # where { raw("func(:a, :b) = :c", a: a, b: b, c: c) } # SELECT ... FROM ... WHERE function(a, b) = c
  # ```
  #
  def raw(__template : String, **tuple)
    Node::Raw.new(self.class.raw(__template, **tuple))
  end

  # If the variable name is a reserved word (e.g. `not`, `var`, `raw`) or if a
  # complex computation cannot be expressed with the expression engine (e.g.
  # function usage), use raw to pass the String.
  #
  # BE AWARE that the String is pasted AS-IS and can lead to SQL injection if not
  # used properly.
  #
  # ```
  # having { raw("COUNT(*)") > 5 }                       # SELECT ... FROM ... HAVING COUNT(*) > 5
  # where { raw("func(:a, :b) = :c", a: a, b: b, c: c) } # SELECT ... FROM ... WHERE function(a, b) = c
  # ```
  #
  def self.raw(__template : String, **tuple)
    __template.gsub(/(^|[^:])\:([a-zA-Z0-9_]+)/) do |_, match|
      sym = match[2]
      match[1] + Lustra::Expression[tuple[sym]]
    rescue e : KeyError
      raise Lustra::ErrorMessages.query_building_error(e.message)
    end
  end

  # Use var to create a variable expression. Variables are columns with or
  # without a namespace and table name:
  #
  # It escapes each part of the expression with double quotes as required by
  # PostgreSQL. This is useful to escape SQL keywords or `.` and `"` characters
  # in column names.
  #
  # ```
  # var("template1", "users", "name")        # "template1"."users"."name"
  # var("template1", "users.table2", "name") # "template1"."users.table2"."name"
  # var("order")                             # "order"
  # ```
  def var(*parts)
    _var(parts)
  end

  # :nodoc:
  private def _var(parts : Tuple, pos = parts.size - 1)
    if pos == 0
      Node::Variable.new(parts[pos].to_s)
    else
      Node::Variable.new(parts[pos].to_s, _var(parts, pos - 1))
    end
  end

  # Because many PostgreSQL operators are not directly translatable in Crystal,
  # this helper helps write expressions:
  #
  # ```
  # where { op(jsonb_field, "something", "?") } # << Return "jsonb_field ? 'something'"
  # ```
  #
  def op(a : (Node | AvailableLiteral), b : (Node | AvailableLiteral), op : String)
    a = Node::Literal.new(a) if a.is_a?(AvailableLiteral)
    b = Node::Literal.new(b) if b.is_a?(AvailableLiteral)

    Node::DoubleOperator.new(a, b, op)
  end

  # :nodoc:
  # Used internally by the expression engine.
  macro method_missing(call)
    {% if call.args.size > 0 %}
      args = {{ call.args }}.map { |x| Lustra::Expression[x] }
      return Node::Function.new("{{ call.name.id }}", args)
    {% else %}
      return Node::Variable.new({{ call.name.id.stringify }})
    {% end %}
  end
end
