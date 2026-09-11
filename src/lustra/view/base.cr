# Define PostgreSQL views in code and recreate them alongside migrations.
#
# Declare dependencies with `require` so Lustra can create and drop views in
# the correct order, regardless of their registration order.
#
# ## How it works
#
# `Lustra::Migration::Manager#apply_all` drops registered views before applying
# migrations and recreates them afterward. Dependencies are created first and
# dropped last. Cyclic dependencies raise `ArgumentError`.
#
# ## Register views
#
# Initialize a connection and load your view definitions before creating them.
# The following example needs no application tables: it generates four rooms
# and a calendar, then combines them into a view of room-days.
#
# ```
# require "lustra"
#
# Lustra::SQL.init(ENV["DATABASE_URL"])
#
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
# In this example, `room_per_days` is dropped before `rooms` and `year_days`,
# then recreated after both dependencies exist.
#
# ## Create and query views
#
# Registration only stores definitions in the running program. Create the
# database views before querying them:
#
# ```
# Lustra::View.apply(:create)
#
# rows = Lustra::SQL.select("room_id", "day")
#   .from("public.room_per_days")
#   .where(room_id: 1)
#   .order_by(:day)
#   .limit(7)
#   .to_a
#
# rows.each do |row|
#   puts "Room #{row["room_id"]}: #{row["day"]}"
# end
# ```
#
# An ordinary view runs its defining query when read. Query it through
# `Lustra::SQL` just as you would query a table, or map it to a model for typed
# access:
#
# ```
# class RoomDay
#   include Lustra::Model
#
#   self.table = "room_per_days"
#   self.schema = "public"
#   self.read_only = true
#
#   column room_id : Int32
#   column day : Time
# end
#
# RoomDay.query.where(room_id: 1).order_by(:day).limit(7).each do |room_day|
#   puts "Room #{room_day.room_id}: #{room_day.day}"
# end
# ```
#
# This model needs no primary key for the queries shown. `read_only` prevents
# model saves; use a database role with SELECT-only permissions if writes must
# also be prohibited through direct SQL or bulk operations.
#
# ## Update definitions alongside migrations
#
# Keep registrations in files loaded by your application's migration entry
# point. After editing a definition, load the updated code and run:
#
# ```
# Lustra::Migration::Manager.instance.apply_all
# ```
#
# This drops registered views, applies pending migrations, and recreates the
# views from their current definitions, even when no migrations are pending.
# Individual `up`, `down`, and `apply_to` calls do not perform this view lifecycle.
# Run this as a migration step rather than on every request.
#
# ## Materialized views
#
# A materialized view stores its query results. For example, after registering
# the views above:
#
# ```
# Lustra::View.register :room_day_counts do |view|
#   view.materialized(true)
#   view.require(:room_per_days)
#   view.query "SELECT room_id, COUNT(*) AS day_count FROM public.room_per_days GROUP BY room_id"
# end
#
# # Create this materialized view for the first time.
# Lustra::View.apply(:create)
#
# counts = Lustra::SQL.select.from("public.room_day_counts").to_a
#
# # Recompute stored results when the underlying data changes.
# Lustra::SQL.execute("REFRESH MATERIALIZED VIEW public.room_day_counts")
# ```
#
# Lustra does not refresh materialized views automatically. To change their
# definitions, use the drop-and-create lifecycle described above. For views on a
# named connection, use that connection for reads and refreshes too:
# `query.use_connection("reporting")` and `Lustra::SQL.execute("reporting", sql)`.
class Lustra::View
  # Register a view definition. Registration does not execute SQL.
  # Registering the same name again replaces its definition, even if the schema
  # or connection differs.
  #
  # ```
  # Lustra::View.register(:name) do |view|
  #   view.query "SELECT 1 AS value"
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

  # Create (`:create`) or drop (`:drop`) all registered views in dependency order.
  # Each view uses its configured schema and connection.
  #
  # To recreate views directly:
  #
  # ```
  # Lustra::View.apply(:drop)
  # Lustra::View.apply(:create)
  # ```
  def self.apply(direction : Symbol, apply_cache = Set(String).new)
    @@views.values.each do |view|
      next if apply_cache.includes?(view.name)
      apply(direction, view.name, apply_cache)
    end
  end

  # :nodoc:
  def self.apply(direction : Symbol, view_name : String, apply_cache : Set(String), visiting = Set(String).new)
    return if apply_cache.includes?(view_name)
    raise ArgumentError.new("Cyclic view dependency involving '#{view_name}'") if visiting.includes?(view_name)
    visiting << view_name

    view = @@views[view_name]
    dependencies = if direction == :drop
                     @@views.values.select(&.requirement.includes?(view_name)).map(&.name)
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
  # Clear registered definitions without dropping database views.
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

  # Set the view name. Use `schema` to specify its PostgreSQL schema separately.
  def name(value : String | Symbol)
    @name = value.to_s
  end

  # Set the PostgreSQL schema. Defaults to `public`; the schema must already exist.
  def schema(value : String | Symbol)
    @schema = value.to_s
  end

  # Set the SELECT query defining the view. The SQL is used as supplied.
  def query(query : String)
    @query = query
  end

  # Select a named connection initialized with `Lustra::SQL.init`.
  # Defaults to `"default"`.
  def connection(connection : String)
    @connection = connection
  end

  # Set whether to create a materialized view. Defaults to `false`.
  # Existing materialized views must be dropped before they can be recreated;
  # PostgreSQL does not support `CREATE OR REPLACE MATERIALIZED VIEW`.
  def materialized(mat : Bool)
    @materialized = mat
  end

  # Declare the registered view names referenced by this view's query.
  # Dependencies are not inferred from SQL and must be registered before `apply`.
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
