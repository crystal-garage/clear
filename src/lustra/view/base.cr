# Create and maintain your database views directly in the code.
#
# You could use the migration system to create and drop your views. However this
# is proven to be difficult, even more if you want to update a view which depends on
# another subviews.
#
# ## How it works ?
#
# When you migrate using the migration system, all the views registered
# are going to be destroyed and recreated again.
# Order of creation depends of the requirement for each views
#
# ## Example
#
# ```
# Lustra::View.register :room_per_days do |view|
#   view.require(:rooms, :year_days)
#
#   view.query <<-SQL
#     SELECT room_id, day
#     FROM year_days
#     CROSS JOIN rooms
#   SQL
# end
#
# Lustra::View.register :rooms do |view|
#   view.query <<-SQL
#   SELECT room.id AS room_id
#   FROM generate_series(1, 4) AS room(id)
#   SQL
# end
#
# Lustra::View.register :year_days do |view|
#   view.query <<-SQL
#   SELECT date.day::date AS day
#   FROM   generate_series(
#     date_trunc('day', NOW()),
#     date_trunc('day', NOW() + INTERVAL '364 days'),
#     INTERVAL '1 day'
#   ) AS date(day)
#   SQL
# end
# ```
#
# In the example above, room_per_days will be first dropped before a migration
# start and last created after the migration finished, to prevent issue where some
# views are linked to others
class Lustra::View
  # Call the DSL to register a new view
  #
  # ```
  # Lustra::View.register(:name) do |view|
  #   # describe the view here.
  # end
  # ```
  def self.register(name : Lustra::SQL::Symbolic, &)
    view = Lustra::View.new
    view.name(name)
    yield view

    raise "Your view need to have a name" if view.name == ""
    raise "View `#{view.name}` need to have a query body" if view.query == ""

    @@views[view.name] = view
  end

  # Install the view into PostgreSQL using CREATE VIEW.
  def self.apply(direction : Symbol, apply_cache = Set(String).new)
    @@views.values.each do |view|
      next if apply_cache.includes?(view.name)
      apply(direction, view.name, apply_cache)
    end
  end

  # :ditto:
  def self.apply(direction : Symbol, view_name : String, apply_cache : Set(String), visiting = Set(String).new)
    return if apply_cache.includes?(view_name)
    raise ArgumentError.new("Cyclic view dependency involving '#{view_name}'") if visiting.includes?(view_name)
    visiting << view_name

    view = @@views[view_name]
    dependencies = if direction == :drop
                     @@views.values.select { |candidate| candidate.requirement.includes?(view_name) }.map(&.name)
                   else
                     view.requirement
                   end
    dependencies.each { |dep_view| apply(direction, dep_view, apply_cache, visiting) }

    Lustra::SQL.execute(view.connection, direction == :drop ? view.to_drop_sql : view.to_create_sql)
    apply_cache << view_name
    visiting.delete(view_name)
  end

  # :nodoc:
  #
  # lustra all the views currently registered
  def self.clear
    @@views = {} of String => Lustra::View
  end

  @@views = {} of String => Lustra::View

  getter name : String = ""
  getter schema : String = "public"
  getter query : String = ""
  getter requirement = Set(String).new
  getter connection : String = "default"
  getter? materialized : Bool = false

  # name of the view
  def name(value : String | Symbol)
    @name = value.to_s
  end

  # schema to store the view (default public)
  def schema(value : String | Symbol)
    @schema = value.to_s
  end

  # query body related to the view. Must be a SELECT clause
  def query(query : String)
    @query = query
  end

  # database connection where is installed the view
  def connection(connection : String)
    @connection = connection
  end

  # whether the view is materialized or not. I would recommend to use
  # migration execute create/drop whenever the view is a materialized view
  def materialized(mat : Bool)
    @materialized = mat
  end

  # list of dependencies from the other view related to this view
  def require(*req)
    req.map(&.to_s).each { |s| @requirement.add(s) }
  end

  def to_drop_sql
    {"DROP", (materialized? ? "MATERIALIZED VIEW" : "VIEW"), "IF EXISTS", full_name}.join(' ')
  end

  def full_name
    {@schema, @name}.join(".") { |x| Lustra::SQL.escape(x) }
  end

  def to_create_sql
    {(materialized? ? "CREATE MATERIALIZED VIEW" : "CREATE OR REPLACE VIEW"), full_name, "AS (", @query, ")"}.join(' ')
  end
end
