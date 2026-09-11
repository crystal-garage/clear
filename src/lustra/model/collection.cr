require "../sql/select_query"

# Model definition is made by adding the `Lustra::Model` mixin in your class.
# ## Simple Model
#
# ```
# class MyModel
#   include Lustra::Model
#
#   column my_column : String
# end
# ```
#
# We just created a new model linked to your database, mapping the column
# `my_column` as String (`text` in PostgreSQL).
#
# Now, you can play with your model:
#
# ```
# row = MyModel.new # create an empty row
# row.my_column = "This is a content"
# row.save! # insert the new row in the database !
# ```
#
# By convention, the table name follows an underscored, plural version of your
# model: `my_models`. A model inside a module prepends the module name, so
# `Logistic::MyModel` checks for `logistic_my_models` in your database.
# You can force a specific table name using:
#
# ```
# class MyModel
#   include Lustra::Model
#   self.table = "another_table_name"
# end
# ```
#
# ## Presence validation
#
# Unlike many ORMs, Lustra cares about non-nullable patterns in Crystal. That
# means `column my_column : String` assumes that `row.my_column` returns a String.
#
# But there are cases where the column is not initialized yet:
# - When the object is built without providing the value (see above).
# - When an object is partially fetched through a database query. This is useful
#   for skipping large fields that are not needed for the current operation.
#
# For example, this code will compile:
#
# ```
# row = MyModel.new # create an empty row
# puts row.my_column
# ```
#
# However, it will raise a runtime exception because the field has never been initialized.
#
# Same way, trying to save the object will raise an error:
#
# ```
# row.save      # Will return false
# pp row.errors # Will tell you that `my_column` presence is mandatory.
# ```
#
# Thanks to Crystal's expressiveness, we can handle presence validation by using
# a nilable type:
#
# ```
# class MyModel
#   include Lustra::Model
#
#   column my_column : String? # Now, the column can be NULL or text in PostgreSQL.
# end
# ```
#
# This time, the code above works; if there is no value, `my_column` is nil by default.
#
# ## Querying Your Model
#
# To fetch data from your database, create a collection query:
#
# `MyModel.query # Builds SELECT * FROM my_models`
#
# Queries are fetchable using `each`:
#
# ```
# MyModel.query.each do |model|
#   # Do something with your model here.
# end
# ```
#
# ## Refining Your Query
#
# A collection query can be refined with `where`, `join`, `order_by`, `limit`,
# `select`, `group_by`, and the other query helpers mixed in from
# `Lustra::SQL::SelectBuilder`.
#
# ## Column Types
#
# By default, Lustra maps these Crystal types through converters:
#
# - `String` => `text`
# - `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`, `BigDecimal` => PostgreSQL numeric types
# - `Bool` => `boolean`
# - `Time` => `timestamp without timezone or text`
# - `JSON::Any` => `json` or `jsonb`
# - `Array(Bool)`, `Array(String)`, `Array(Float32)`, `Array(Float64)`, `Array(Int32)`, `Array(Int64)` => PostgreSQL array columns
# - Nilable types such as `String?` or `Int64?` => nullable columns
#
# `crystal-pg` also maps additional PostgreSQL-specific values such as
# geometric types. Lustra provides converters for some of them through
# extensions, but support depends on the converter being registered.
#
# If you need to map a special structure, see the [Mapping Your Data](Mapping)
# guide for more information.
#
# ## Primary Key
#
# A primary key is essential for relational mapping. Lustra currently supports
# only one primary key column.
#
# A model without a primary key can work in a degraded mode, raising errors when
# some methods are used:
# - `collection#first` raises if no `order_by` has been set.
#
# To set up a primary key, add `primary: true` to the column:
#
# ```
# class MyModel
#   include Lustra::Model
#
#   column id : Int32, primary: true, presence: false
#   column my_column : String?
# end
# ```
#
# Note the `presence: false` flag added to the column. This tells Lustra that
# presence checking on save is not mandatory. This usually happens when you set
# up a default value in PostgreSQL. In the case of our primary key `id`, we use a
# serial auto-increment default value.
# Therefore, saving the model without a primary key works. The id is fetched after insertion:
#
# ```
# m = MyModel.new
# m.save!
# m.id # Now the id value is set.
# ```
#
# ## Helpers
#
# Lustra provides various built-in helpers to facilitate your life:
#
# ### Timestamps
#
# ```
# class MyModel
#   include Lustra::Model
#   timestamps # Maps 'created_at' and 'updated_at', and adds hooks to update their values.
# end
# ```
#
# These fields are automatically updated whenever you call `save` methods, like
# Rails ActiveRecord.
#
# ### With Serial Pkey
#
# ```
# class MyModel
#   include Lustra::Model
#   primary_key "my_primary_key"
# end
# ```
#
# With the default `:bigserial` type, this rewrites to
# `column id : Int64, primary: true, presence: false`.
#
# The column name is optional and defaults to `id`. The key type is optional and
# defaults to `:bigserial`; supported built-in types include `:bigserial`,
# `:serial`, `:text`, `:int`, and `:bigint`. Extensions can register additional
# primary key types, such as `:uuid`.
module Lustra::Model
  # `CollectionBase(T)` is the base class for model collections.
  # Model collections are a SQL `SELECT` query mapping and building system. They
  # are Enumerable and include `Lustra::SQL::SelectBuilder` behavior; therefore,
  # they can be used array-like and also work with low-level SQL building.
  #
  # The `CollectionBase(T)` is extended by each model. For example, generating
  # the model `MyModel` generates the class `MyModel::Collection`, which
  # inherits from `CollectionBase(MyModel)`.
  #
  # Collections are instantiated using the `Model.query` method.
  class CollectionBase(T)
    include Enumerable(T)
    include Lustra::SQL::SelectBuilder

    # Used for build from collection.
    @tags : Hash(String, Lustra::SQL::Any)

    @polymorphic : Bool = false
    @polymorphic_key : String?
    @polymorphic_scope : Set(String)?

    # :nodoc:
    protected getter cache : Lustra::Model::QueryCache

    # :nodoc:
    @cached_result : Array(T)?

    # :nodoc:
    property append_operation : Proc(T, T)?
    # :nodoc:
    property? run_append_operation_after_create : Bool = true
    # :nodoc:
    property unlink_operation : Proc(T, T)?

    # Parent model context for autosave functionality.
    property parent_model : Lustra::Model?
    property association_name : String?
    property? autosave : Bool = false

    # :nodoc:
    def initialize(
      @distinct_value = nil,
      @cte = {} of String => Lustra::SQL::SelectBuilder | String,
      @columns = [] of SQL::Column,
      @froms = [] of SQL::From,
      @joins = [] of SQL::Join,
      @wheres = [] of Lustra::Expression::Node,
      @havings = [] of Lustra::Expression::Node,
      @windows = [] of {String, String},
      @group_bys = [] of SQL::Symbolic,
      @order_bys = [] of Lustra::SQL::Query::OrderBy::Record,
      @limit = nil,
      @offset = nil,
      @lock = nil,
      @before_query_triggers = [] of Lustra::SQL::SelectBuilder -> Nil,
      @tags = {} of String => Lustra::SQL::Any,
      @cache = Lustra::Model::QueryCache.new,
      @cached_result = nil,
    )
    end

    def dup
      copy = super
      copy.tags(@tags)
      copy.append_operation = append_operation
      copy.unlink_operation = unlink_operation
      copy.run_append_operation_after_create = run_append_operation_after_create?
      copy.parent_model = parent_model
      copy.association_name = association_name
      copy.autosave = autosave?
      if @polymorphic && (polymorphic_key = @polymorphic_key) && (polymorphic_scope = @polymorphic_scope)
        copy.flag_as_polymorphic!(polymorphic_key, polymorphic_scope)
      end
      copy
    end

    # :nodoc:
    # Set this query's connection to the model class connection.
    def connection_name
      T.connection
    end

    # Return the model class for this collection.
    def item_class
      T
    end

    # :nodoc:
    # Set a query cache on this Collection. Fetching and enumeration will use
    # the cache instead of calling SQL.
    def cached(cache : Lustra::Model::QueryCache)
      @cache = cache

      self
    end

    # :nodoc:
    def with_cached_result(r : Array(T))
      @cached_result = r

      self
    end

    # :nodoc:
    # Used internally to fetch models if the collection is flagged as polymorphic.
    def flag_as_polymorphic!(@polymorphic_key, scope : Enumerable(String))
      @polymorphic = true
      polymorphic_scope = @polymorphic_scope = Set(String).new
      scope.each { |x| polymorphic_scope.add(x) }

      self
    end

    # :nodoc:
    # Clear the current cache.
    def clear_cached_result
      @cached_result = nil

      self
    end

    # :nodoc:
    def change!
      # If we filter this collection, remove the cache.
      clear_cached_result
    end

    # :nodoc:
    def tags(x : NamedTuple)
      @tags.merge!(x.to_h)

      self
    end

    # :nodoc:
    def tags(x : Hash(String, X)) forall X
      @tags.merge!(x.to_h)

      self
    end

    def tags
      @tags
    end

    # :nodoc:
    # Redefine where with a tuple argument that adds tags.
    def where(**tuple)
      hash = tuple.to_h.transform_keys &.to_s

      any_hash = {} of String => Lustra::SQL::Any

      # Remove terms that are not real values but conditions like range or array.
      hash.each do |k, v|
        any_hash[k] = v if v.is_a?(Lustra::SQL::Any)
      end

      tags(any_hash)

      super(**tuple)
    end

    # :nodoc:
    def clear_tags
      @tags = {} of String => Lustra::SQL::Any

      self
    end

    private def build_fetched_model(hash : Hash(String, Lustra::SQL::Any), fetch_columns : Bool) : T
      if @polymorphic
        type = hash[@polymorphic_key].as(String)
        Lustra::Model::Factory.build(type, hash, persisted: true, fetch_columns: fetch_columns, cache: @cache).as(T)
      else
        Lustra::Model::Factory.build(T, hash, persisted: true, fetch_columns: fetch_columns, cache: @cache)
      end
    end

    private def fetch_models(fetch_columns : Bool) : Array(T)
      if result = @cached_result
        return result
      end

      result = [] of T

      fetch(fetch_all: false) do |hash|
        result << build_fetched_model(hash, fetch_columns)
      end

      result
    end

    # Build the SQL, send the query, then iterate through each model gathered by
    # the request.
    def each(fetch_columns = false, & : T ->) : Nil
      fetch_models(fetch_columns).each do |value|
        yield value
      end
    end

    # Build the SQL, send the query, then build an array by applying the block
    # transformation over it.
    def map(fetch_columns = false, &block : T -> X) : Array(X) forall X
      o = [] of X
      each(fetch_columns) { |mdl| o << block.call(mdl) }

      o
    end

    # Build the SQL, send the query, then iterate through each model gathered by
    # the request.
    # Use a PostgreSQL cursor to avoid memory bloat.
    # Useful to fetch millions of rows at once.
    def each_with_cursor(batch = 1000, fetch_columns = false, &block : T ->)
      cr = @cached_result

      if cr
        cr.each(&block)
      else
        fetch_with_cursor(count: batch) do |hash|
          yield build_fetched_model(hash, fetch_columns)
        end
      end
    end

    # Build a new collection; if the collection comes from a has_many relation
    # (e.g. `my_model.associations.build`), the foreign column that stores the
    # primary key of `my_model` will be set by default, preventing you from
    # forgetting it.
    # You can pass extra parameters using a named tuple:
    # `my_model.associations.build({a_column: "value"}) `
    def build(**tuple, & : T -> Nil) : T
      str_hash = @tags.dup
      reset_tuple = false

      tuple.each do |key, value|
        if value.is_a?(Lustra::SQL::Any)
          str_hash[key.to_s] = value
        else
          reset_tuple = true
        end
      end

      r = Lustra::Model::Factory.build(T, str_hash, persisted: false)
      r.reset(tuple) if reset_tuple

      yield(r)

      # Register with parent model for autosave functionality.
      if autosave? && (pm = parent_model) && (an = association_name)
        pm.add_built_association(an, r)
      end

      r
    end

    # :ditto:
    def build(**tuple) : T
      build(**tuple) { }
    end

    # :ditto:
    def build(x : NamedTuple) : T
      build(**x) { }
    end

    # :ditto:
    def build(x : NamedTuple, &block : T -> Nil) : T
      build(**x, &block)
    end

    # Build a new object and set the fields from the condition tuple.
    # Just after building, save the object.
    def create(**tuple, & : T -> Nil) : T
      r = build(**tuple) { |mdl| yield(mdl) }

      if r.save
        handle_append_operation(r)
      end

      r
    end

    # :ditto:
    def create(**tuple) : T
      create(**tuple) { }
    end

    # :ditto:
    def create(x : NamedTuple) : T
      create(**x)
    end

    # :ditto:
    def create(x : NamedTuple, &block : T -> Nil) : T
      create(**x, &block)
    end

    # Build a new object and set the fields from the condition tuple.
    # Just after building, save the object.
    # Instead of returning self if validation fails, raise
    # `Lustra::Model::InvalidError`.
    def create!(**tuple, & : T -> Nil) : T
      r = build(**tuple) { |mdl| yield(mdl) }

      r.save!

      handle_append_operation(r)

      r
    end

    # :ditto:
    def create!(**tuple) : T
      create!(**tuple) { }
    end

    # :ditto:
    def create!(x : NamedTuple) : T
      create!(**x)
    end

    # :ditto:
    def create!(x : NamedTuple, &block : T -> Nil) : T
      create!(**x, &block)
    end

    # Check whether the query returns any row.
    def any? : Bool
      cr = @cached_result

      return !cr.empty? if cr

      query = dup.clear_before_query_triggers.clear_select.clear_order_bys.select("1")
      query.limit(1) unless query.limit == 0
      query.fetch { |_| return true }

      false
    end

    # Inverse of `any?`; return true if the request returns no rows.
    def empty? : Bool
      !any?
    end

    # Use SQL `COUNT` over your query, and return this number as an Int64.
    def count(type : X.class = Int64) forall X
      cr = @cached_result

      return X.new(cr.size) unless cr.nil?

      super(type)
    end

    # Add an item to the current collection.
    #
    # If the current collection does not originate from a `has_many` or
    # `has_many through:` relation, calling `<<` over the collection will raise a
    # `Lustra::SQL::OperationNotPermittedError`.
    #
    # Returns `self` and therefore can be chained.
    def <<(item : T)
      append_operation = self.append_operation

      raise relation_operation_not_permitted("append", item) unless append_operation

      append_operation.call(item)
      @cached_result.try &.<<(item)

      self
    end

    # Alias for `Collection#<<`
    def add(item : T)
      self << item
    end

    private def handle_append_operation(item : T)
      if append_operation = self.append_operation
        append_operation.call(item) if run_append_operation_after_create?
        @cached_result.try &.<<(item)
      end
    end

    # Save a model and handle append_operation for has_many through relationships.
    # This allows the build + save pattern to work.
    def save!(item : T)
      item.save!
      handle_append_operation(item)
      item
    end

    # Unlink the model currently referenced through a `has_many through` relation.
    #
    # If the current collection doesn't come from a `has_many through` relation,
    # this method will throw `Lustra::SQL::OperationNotPermittedError`.
    #
    # Returns `true` if unlinking is successful (e.g. one or more rows have been
    # updated), or `false` otherwise.
    def unlink(item : T)
      unlink_operation = self.unlink_operation

      raise relation_operation_not_permitted("unlink", item) unless unlink_operation

      unlink_operation.call(item)
      @cached_result.try &.delete(item)

      self
    end

    private def relation_operation_not_permitted(operation : String, item : T)
      relation = if parent = parent_model
                   if name = association_name
                     " Association context: #{parent.class}##{name}."
                   else
                     " Association context: #{parent.class}."
                   end
                 else
                   " This collection is a plain #{T}.query result."
                 end

      "Cannot #{operation} #{item.class} on this collection. " \
      "This operation is only available on writable `has_many` or `has_many through` association collections." \
      "#{relation} Use an association collection such as `user.posts`, not `#{T}.query`."
    end

    # Create an array from the query.
    def to_a(fetch_columns = false) : Array(T)
      fetch_models(fetch_columns)
    end

    # Basically a fancy way to write `OFFSET x LIMIT 1`
    def [](off, fetch_columns = false) : T
      self[off, fetch_columns]? || raise Lustra::SQL::RecordNotFoundError.new
    end

    # Basically a fancy way to write `OFFSET x LIMIT 1`
    def []?(off, fetch_columns = false) : T?
      previous_offset = offset

      begin
        offset(off).first(fetch_columns)
      ensure
        offset(previous_offset)
      end
    end

    # Get a range of models.
    def [](range : Range(Number, Number), fetch_columns = false) : Array(T)
      previous_offset = offset
      previous_limit = limit

      begin
        offset(range.begin).limit(range.end - range.begin).to_a(fetch_columns)
      ensure
        offset(previous_offset)
        limit(previous_limit)
      end
    end

    # Return an empty, chainable collection (Rails-like `.none`).
    # Useful for conditional branches where no records should be returned
    # while keeping query chaining intact.
    #
    # ```
    # User.query.none.where { active == true }.count # => 0
    # ```
    def none
      where { raw("1 = 0") }
    end

    # Returns a model using primary key equality.
    # Returns `nil` if not found.
    def find(x) : T?
      with_restored_finder_state do
        where { raw(T.__pkey__) == x }.first
      end
    end

    # Find multiple models by an array of primary keys.
    # Returns an array of models (may be empty if none found).
    def find(ids : Array) : Array(T)
      with_restored_finder_state do
        where { raw(T.__pkey__).in?(ids) }.to_a
      end
    end

    # Returns a model using primary key equality.
    # Raises an error if the model is not found.
    def find!(x) : T
      find(x) || raise Lustra::SQL::RecordNotFoundError.new
    end

    # Find multiple models by an array of primary keys.
    # Raises an error if ANY of the IDs are not found.
    def find!(ids : Array) : Array(T)
      results = find(ids)
      if results.size != ids.size
        raise Lustra::SQL::RecordNotFoundError.new("Couldn't find all records with IDs: #{ids.inspect}")
      end
      results
    end

    # A convenient way to write `where { condition }.first(fetch_columns)`
    def find_by(fetch_columns = false, &) : T?
      x = Lustra::Expression.ensure_node!(with Lustra::Expression.new yield)

      with_restored_finder_state do
        where(x).first(fetch_columns)
      end
    end

    # Find a model by column values. Returns `nil` if not found.
    #
    # ```
    # user = User.query.find_by(email: "test@example.com")
    # user = User.query.where { active == true }.find_by(role: "admin")
    # ```
    def find_by(**tuple) : T?
      with_restored_finder_state do
        where(tuple).first
      end
    end

    # :ditto:
    def find_by(tuple : NamedTuple, fetch_columns = false) : T?
      with_restored_finder_state do
        where(tuple).first(fetch_columns)
      end
    end

    # A convenient way to write `where { condition }.first!(fetch_columns)`
    def find_by!(fetch_columns = false, &) : T
      x = Lustra::Expression.ensure_node!(with Lustra::Expression.new yield)

      with_restored_finder_state do
        where(x).first!(fetch_columns)
      end
    end

    # Find a model by column values. Raises error if not found.
    #
    # ```
    # user = User.query.find_by!(email: "test@example.com")
    # ```
    def find_by!(**tuple) : T
      with_restored_finder_state do
        where(**tuple).first!
      end
    end

    # :ditto:
    def find_by!(tuple : NamedTuple, fetch_columns = false) : T
      with_restored_finder_state do
        where(**tuple).first!(fetch_columns)
      end
    end

    # Try to fetch a row. If not found, build a new object and set the fields
    # from the condition tuple.
    def find_or_build(**tuple, & : T -> Nil) : T
      with_restored_finder_state do
        where(tuple) unless tuple.size == 0
        r = first

        if r
          r
        else
          str_hash = @tags.dup
          tuple.map { |k, v| str_hash[k.to_s] = v }

          r = Lustra::Model::Factory.build(T, str_hash)

          yield(r)

          r
        end
      end
    end

    def find_or_build(**tuple) : T
      find_or_build(**tuple) { }
    end

    # :ditto:
    def find_or_build(x : NamedTuple) : T
      find_or_build(**x)
    end

    # :ditto:
    def find_or_build(x : NamedTuple, &block : T -> Nil) : T
      find_or_build(**x, &block)
    end

    # Try to fetch a row. If not found, build a new object and set the fields
    # from the condition tuple.
    # Just after building, save the object.
    def find_or_create(**tuple, & : T -> Nil) : T
      built = false
      r = find_or_build(**tuple) do |mdl|
        built = true
        yield(mdl)
      end

      if built
        r.save!
        handle_append_operation(r)
      end

      r
    end

    # :ditto:
    def find_or_create(**tuple) : T
      find_or_create(**tuple) { }
    end

    # :ditto:
    def find_or_create(x : NamedTuple) : T
      find_or_create(**x)
    end

    # :ditto:
    def find_or_create(x : NamedTuple, &block : T -> Nil) : T
      find_or_create(**x, &block)
    end

    private def with_restored_finder_state(&)
      previous_wheres = @wheres.dup
      previous_tags = @tags.dup

      begin
        yield
      ensure
        @wheres = previous_wheres
        @tags = previous_tags
      end
    end

    # Get the first row from the collection query.
    # if not found, return `nil`
    def first(fetch_columns = false) : T?
      previous_order_bys = order_bys.dup
      previous_limit = limit

      begin
        order_by(Lustra::SQL.escape("#{T.__pkey__}"), :asc) if T.__pkey__ || order_bys.empty?

        limit(1).fetch do |hash|
          return Lustra::Model::Factory.build(T, hash, persisted: true, cache: @cache, fetch_columns: fetch_columns)
        end

        nil
      ensure
        order_by(previous_order_bys)
        limit(previous_limit)
      end
    end

    # Get the first row from the collection query.
    # if not found, throw an error
    def first!(fetch_columns = false) : T
      first(fetch_columns) || raise Lustra::SQL::RecordNotFoundError.new
    end

    # Get the last row from the collection query.
    # if not found, return `nil`
    def last(fetch_columns = false) : T?
      previous_order_bys = order_bys.dup
      previous_limit = limit

      begin
        order_by("#{T.__pkey__}", :asc) if T.__pkey__ || order_bys.empty?

        new_order = order_bys.map do |x|
          Lustra::SQL::Query::OrderBy::Record.new(x.op, (x.dir == :asc ? :desc : :asc), nil)
        end

        clear_order_bys.order_by(new_order)

        limit(1).fetch do |hash|
          return Lustra::Model::Factory.build(T, hash, persisted: true, cache: @cache, fetch_columns: fetch_columns)
        end

        nil
      ensure
        order_by(previous_order_bys)
        limit(previous_limit)
      end
    end

    # Get the last row from the collection query.
    # if not found, throw an error
    def last!(fetch_columns = false) : T
      last(fetch_columns) || raise Lustra::SQL::RecordNotFoundError.new
    end

    # Redefinition of `join_impl` to avoid ambiguity on the column
    # name if no specific column have been selected.
    protected def join_impl(name, type, lateral, clear_expr)
      self.default_wildcard_table = Lustra::SQL.escape(T.table)

      super(name, type, lateral, clear_expr)
    end

    # Join a relation using association name (auto-detects join conditions)
    # Overrides the parent join to handle association names without blocks
    def join(association : Lustra::SQL::Symbolic, type = :inner, lateral = false)
      auto_join_association(association, type, lateral)
    end

    {% for j in ["left", "right", "full_outer", "inner"] %}
      # {{ j.id.upcase }} JOIN using association name (auto-detects join conditions)
      def {{ j.id }}_join(association : Lustra::SQL::Symbolic, lateral = false)
        auto_join_association(association, :{{ j.id }}, lateral)
      end
    {% end %}

    # Filter records missing the given association.
    #
    # ```
    # User.query.where.missing(:posts)
    # # SELECT "users".* FROM "users"
    # # LEFT JOIN "posts" ON ("posts"."user_id" = "users"."id")
    # # WHERE ("posts"."id" IS NULL)
    # ```
    def missing(association : Lustra::SQL::Symbolic)
      auto_join_association(association, :left, false, "Association filters accept an association name, not a table name.")
      where("#{association_primary_key_sql(association)} IS NULL")
    end

    # Filter records having at least one matching association.
    #
    # ```
    # User.query.where.associated(:posts)
    # # SELECT "users".* FROM "users"
    # # INNER JOIN "posts" ON ("posts"."user_id" = "users"."id")
    # # WHERE ("posts"."id" IS NOT NULL)
    # ```
    def associated(association : Lustra::SQL::Symbolic)
      auto_join_association(association, :inner, false, "Association filters accept an association name, not a table name.")
      where("#{association_primary_key_sql(association)} IS NOT NULL")
    end

    # Add a computed count column for the given association without loading the
    # associated records.
    #
    # ```
    # User.query.with_count(:posts)
    # # SELECT "users".*, (SELECT COUNT(*) FROM "posts" WHERE "posts"."user_id" = "users"."id") AS posts_count FROM "users"
    # ```
    def with_count(association : Lustra::SQL::Symbolic, alias_name : String? = nil)
      table = T.table
      base_select = "#{Lustra::SQL.escape(table)}.*"
      count_alias = alias_name || "#{association}_count"

      self.select(base_select) if columns.empty?
      self.select(SQL::Column.new(association_count_sql(association), count_alias))
      group_by("#{table}.#{T.__pkey__}") if !joins.empty? && group_bys.empty?
      self
    end

    # Build a single-column key query while preserving selected expressions
    # required by ordering and pagination in the inner query.
    protected def key_subquery(column : String, source : CollectionBase(T) = dup)
      key_alias = "__lustra_query_key"
      source_alias = "__lustra_query_source"

      source.select(SQL::Column.new(
        "#{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(column)}",
        key_alias
      ))

      Lustra::SQL
        .select("#{source_alias}.#{key_alias}")
        .from({__lustra_query_source: source})
        .use_connection(connection_name)
    end

    private def unknown_association_message(association, advice : String)
      available = {% begin %}
        {% available_associations = T::RELATIONS.keys.map(&.stringify).sort %}
        {% if available_associations.empty? %}
          "none"
        {% else %}
          {{ available_associations.join(", ") }}
        {% end %}
      {% end %}

      "Unknown association '#{association}' for #{T}. Available associations: #{available}. #{advice}"
    end

    # Return the SQL identifier used for the association existence predicate.
    private def association_primary_key_sql(association : Lustra::SQL::Symbolic)
      {% begin %}
        case association.to_s
        {% for name, settings in T::RELATIONS %}
          when "{{ name }}"
            {% if settings[:relation_type] == :has_many || settings[:relation_type] == :has_many_through %}
              %relation_table = {{ settings[:type] }}.table
              %primary_key = {{ settings[:type] }}.__pkey__
              "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%primary_key)}"
            {% elsif settings[:relation_type] == :has_one %}
              %relation_table = {{ settings[:type].stringify.gsub(/\s*\|\s*Nil/, "").gsub(/\s*\|\s*::Nil/, "").id }}.table
              %primary_key = {{ settings[:type].stringify.gsub(/\s*\|\s*Nil/, "").gsub(/\s*\|\s*::Nil/, "").id }}.__pkey__
              "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%primary_key)}"
            {% elsif settings[:relation_type] == :belongs_to %}
              {% if settings[:polymorphic] && !settings[:polymorphic_type] %}
                # A polymorphic belongs_to can point at multiple tables, so
                # there is no single SQL JOIN target to infer here.
                raise "Polymorphic association '#{association}' for #{T} cannot be used for SQL joins because it can target multiple tables. Filter the polymorphic id/type columns directly."
              {% else %}
                %relation_table = {{ settings[:type] }}.table
                %primary_key = {{ settings[:type] }}.__pkey__
                "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%primary_key)}"
              {% end %}
            {% end %}
          {% if settings[:relation_type] == :has_many_through %}
            when {{ settings[:through] }}.table
              %through_table = {{ settings[:through] }}.table
              %through_pkey = {{ settings[:through] }}.__pkey__
              "#{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%through_pkey)}"
          {% end %}
        {% end %}
        else
          raise unknown_association_message(association, "Association filters accept an association name, not a table name.")
        end
      {% end %}
    end

    # Return a correlated subquery that counts records for the association.
    private def association_count_sql(association : Lustra::SQL::Symbolic)
      {% begin %}
        case association.to_s
        {% for name, settings in T::RELATIONS %}
          when "{{ name }}"
            {% if settings[:relation_type] == :has_many %}
              %foreign_key =
                {% if settings[:foreign_key] %}
                  "{{ settings[:foreign_key] }}"
                {% elsif settings[:as] %}
                  "{{ settings[:as] }}_id"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              %relation_table = {{ settings[:type] }}.table

              %primary_key =
                {% if settings[:primary_key] %}
                  "{{ settings[:primary_key] }}"
                {% else %}
                  T.__pkey__
                {% end %}

              count_condition = "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%foreign_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%primary_key)}"

              {% if settings[:as] %}
                %type_key = "{{ settings[:as] }}_type"
                count_condition += " AND #{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%type_key)} = #{Lustra::Expression[T.name]}"
              {% end %}

              "(SELECT COUNT(*) FROM #{Lustra::SQL.escape(%relation_table)} WHERE #{count_condition})"
            {% elsif settings[:relation_type] == :has_one %}
              %foreign_key =
                {% if settings[:foreign_key] %}
                  "{{ settings[:foreign_key] }}"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              %relation_table = {{ settings[:type].stringify.gsub(/\s*\|\s*Nil/, "").gsub(/\s*\|\s*::Nil/, "").id }}.table

              %primary_key =
                {% if settings[:primary_key] %}
                  "{{ settings[:primary_key] }}"
                {% else %}
                  T.__pkey__
                {% end %}

              "(SELECT COUNT(*) FROM #{Lustra::SQL.escape(%relation_table)} WHERE #{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%foreign_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%primary_key)})"
            {% elsif settings[:relation_type] == :belongs_to %}
              {% if settings[:polymorphic] && !settings[:polymorphic_type] %}
                # A polymorphic belongs_to can point at multiple tables, so a
                # single correlated count subquery would be ambiguous.
                raise "Polymorphic association '#{association}' for #{T} cannot be used with with_count because it can target multiple tables. Filter or count each concrete type directly."
              {% else %}
                %foreign_key =
                  {% if settings[:foreign_key] %}
                    "{{ settings[:foreign_key] }}"
                  {% else %}
                    "{{ name }}_id"
                  {% end %}

                %relation_table = {{ settings[:type] }}.table
                %primary_key = {{ settings[:type] }}.__pkey__

                count_condition = "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%primary_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%foreign_key)}"
                {% if settings[:polymorphic_type] %}
                  %type_key = %foreign_key.gsub(/_id$/, "_type")
                  count_condition += " AND #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%type_key)} = #{Lustra::Expression[{{ settings[:polymorphic_type] }}]}"
                {% end %}

                "(SELECT COUNT(*) FROM #{Lustra::SQL.escape(%relation_table)} WHERE #{count_condition})"
              {% end %}
            {% elsif settings[:relation_type] == :has_many_through %}
              %through_table = {{ settings[:through] }}.table

              %own_key =
                {% if settings[:own_key] %}
                  "{{ settings[:own_key] }}"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              "(SELECT COUNT(*) FROM #{Lustra::SQL.escape(%through_table)} WHERE #{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%own_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(T.__pkey__)})"
            {% end %}
          {% if settings[:relation_type] == :has_many_through %}
            when {{ settings[:through] }}.table
              %through_table = {{ settings[:through] }}.table

              %own_key =
                {% if settings[:own_key] %}
                  "{{ settings[:own_key] }}"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              "(SELECT COUNT(*) FROM #{Lustra::SQL.escape(%through_table)} WHERE #{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%own_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(T.__pkey__)})"
          {% end %}
        {% end %}
        else
          raise unknown_association_message(association, "with_count accepts an association name, not a table name.")
        end
      {% end %}
    end

    # Helper to auto-detect join conditions from association metadata
    private def auto_join_association(
      association : Lustra::SQL::Symbolic,
      type,
      lateral,
      unknown_association_advice = "For a table name, use join with a block.",
    )
      {% begin %}
        case association.to_s
        {% for name, settings in T::RELATIONS %}
          when "{{ name }}"
            {% if settings[:relation_type] == :has_many %}
              # has_many :posts => posts.user_id = users.id
              %foreign_key =
                {% if settings[:foreign_key] %}
                  "{{ settings[:foreign_key] }}"
                {% elsif settings[:as] %}
                  "{{ settings[:as] }}_id"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              %relation_table = {{ settings[:type] }}.table

              %primary_key =
                {% if settings[:primary_key] %}
                  "{{ settings[:primary_key] }}"
                {% else %}
                  T.__pkey__
                {% end %}

              condition = "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%foreign_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%primary_key)}"
              {% if settings[:as] %}
                %type_key = "{{ settings[:as] }}_type"
                condition += " AND #{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%type_key)} = #{Lustra::Expression[T.name]}"
              {% end %}
              join(Lustra::SQL.escape(%relation_table), type, condition, lateral)
            {% elsif settings[:relation_type] == :has_one %}
                # has_one :info => user_infos.user_id = users.id
                %foreign_key =
                  {% if settings[:foreign_key] %}
                    "{{ settings[:foreign_key] }}"
                  {% else %}
                    T.table.to_s.singularize + "_id"
                  {% end %}

                # Get the table name from the type (handling nilable like UserInfo?)
                %relation_table = {{ settings[:type].stringify.gsub(/\s*\|\s*Nil/, "").gsub(/\s*\|\s*::Nil/, "").id }}.table

                %primary_key =
                  {% if settings[:primary_key] %}
                    "{{ settings[:primary_key] }}"
                  {% else %}
                    T.__pkey__
                  {% end %}

                condition = "#{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%foreign_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%primary_key)}"
                join(Lustra::SQL.escape(%relation_table), type, condition, lateral)
            {% elsif settings[:relation_type] == :belongs_to %}
              {% if settings[:polymorphic] && !settings[:polymorphic_type] %}
                # A polymorphic belongs_to can point at multiple tables, so
                # there is no single SQL JOIN target to infer here.
                raise "Polymorphic association '#{association}' for #{T} cannot be used for SQL joins because it can target multiple tables. Filter the polymorphic id/type columns directly."
              {% else %}
                # belongs_to :user => posts.user_id = users.id
                %foreign_key =
                  {% if settings[:foreign_key] %}
                    "{{ settings[:foreign_key] }}"
                  {% else %}
                    "{{ name }}_id"
                  {% end %}

                %relation_table = {{ settings[:type] }}.table
                %primary_key = {{ settings[:type] }}.__pkey__

                condition = "#{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%foreign_key)} = #{Lustra::SQL.escape(%relation_table)}.#{Lustra::SQL.escape(%primary_key)}"
                {% if settings[:polymorphic_type] %}
                  %type_key = %foreign_key.gsub(/_id$/, "_type")
                  condition += " AND #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(%type_key)} = #{Lustra::Expression[{{ settings[:polymorphic_type] }}]}"
                {% end %}
                join(Lustra::SQL.escape(%relation_table), type, condition, lateral)
              {% end %}
            {% elsif settings[:relation_type] == :has_many_through %}
              # has_many through requires two joins
              # Example: User has_many :categories, through: Post
              # 1. JOIN posts ON posts.user_id = users.id
              # 2. JOIN categories ON posts.category_id = categories.id

              %through_table = {{ settings[:through] }}.table

              %own_key =
                {% if settings[:own_key] %}
                  "{{ settings[:own_key] }}"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              %through_key =
                {% if settings[:foreign_key] %}
                  "{{ settings[:foreign_key] }}"
                {% else %}
                  {{ settings[:type] }}.table.to_s.singularize + "_id"
                {% end %}

              %final_table = {{ settings[:type] }}.table
              %final_pkey = {{ settings[:type] }}.__pkey__

              # First join: through table
              through_condition = "#{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%own_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(T.__pkey__)}"
              join(Lustra::SQL.escape(%through_table), type, through_condition, lateral)

              # Second join: final table
              final_condition = "#{Lustra::SQL.escape(%final_table)}.#{Lustra::SQL.escape(%final_pkey)} = #{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%through_key)}"
              join(Lustra::SQL.escape(%final_table), type, final_condition, lateral)
            {% end %}
          {% if settings[:relation_type] == :has_many_through %}
            when {{ settings[:through] }}.table
              %through_table = {{ settings[:through] }}.table

              %own_key =
                {% if settings[:own_key] %}
                  "{{ settings[:own_key] }}"
                {% else %}
                  T.table.to_s.singularize + "_id"
                {% end %}

              condition = "#{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%own_key)} = #{Lustra::SQL.escape(T.table)}.#{Lustra::SQL.escape(T.__pkey__)}"
              join(Lustra::SQL.escape(%through_table), type, condition, lateral)
          {% end %}
        {% end %}
        else
          raise unknown_association_message(association, unknown_association_advice)
        end
      {% end %}
    end

    # Delete all the rows which would have been returned by this collection WITHOUT callbacks.
    # This is a bulk operation that doesn't load models into memory.
    # Is equivalent to `collection.to_delete.execute_and_count`.
    #
    # ```
    # User.query.where { active == false }.delete_all
    # ```
    #
    # Returns the number of rows affected.
    def delete_all : Int64
      affected = to_delete.execute_and_count
      change! # because we want to clear the caches in case we do something with the collection later
      affected
    end

    # Delete all matching rows and return selected columns as typed tuples.
    # Tuple values follow the declared column order. PostgreSQL does not
    # guarantee the order of the returned rows.
    #
    # ```
    # users = User.query.where(active: false).delete_all(
    #   returning: {id: Int64, email: String}
    # )
    # ```
    def delete_all(returning : T) forall T
      deleted = to_delete.execute_returning(returning)
      change!
      deleted
    end

    # Destroy all the rows which would have been returned by this collection WITH callbacks.
    # This loads each model into memory and calls `destroy` on it, triggering all `:delete` callbacks.
    # Use `delete_all` if you don't need callbacks (much faster for large datasets).
    #
    # ```
    # # With callbacks - slower but safe
    # User.query.where { active == false }.destroy_all
    #
    # # Without callbacks - faster
    # User.query.where { active == false }.delete_all
    # ```
    #
    # Returns `self` for chaining.
    def destroy_all : self
      each do |model|
        model.destroy
      end
      change! # because we want to clear the caches in case we do something with the collection later
    end

    # Update all the rows which would have been returned by this collection
    # without loading the models into memory. Bypasses validations and callbacks.
    #
    # This is useful for bulk updates where you don't need to run validations
    # or callbacks on each individual model.
    #
    # ```
    # # Update all inactive users to have a specific status
    # affected = User.query.where { active == false }.update_all(status: "inactive")
    # puts "Updated #{affected} users"
    #
    # # Update multiple columns at once
    # Post.query.where { published == false }.update_all(published: true, published_at: Time.utc)
    #
    # # With complex conditions
    # User.query.where { created_at < 1.year.ago }.update_all(archived: true)
    # ```
    #
    # Returns the number of rows affected.
    def update_all(**fields) : Int64
      to_update.set(**fields).execute_and_count
    end

    # :ditto:
    def update_all(fields : NamedTuple) : Int64
      to_update.set(fields).execute_and_count
    end

    # :ditto:
    def update_all(fields : Hash(String, Lustra::SQL::Any)) : Int64
      to_update.set(fields).execute_and_count
    end

    # Update all matching rows and return selected columns as typed tuples.
    # The update fields are positional so `returning` cannot be confused with
    # a column passed to the keyword-argument overload.
    #
    # ```
    # users = User.query.where(active: false).update_all(
    #   {active: true},
    #   returning: {id: Int64, email: String}
    # )
    # ```
    #
    # Tuple values follow the declared column order. PostgreSQL does not
    # guarantee the order of the returned rows.
    def update_all(fields : NamedTuple, returning : T) forall T
      to_update.set(fields).execute_returning(returning)
    end

    # :ditto:
    def update_all(fields : Hash(String, Lustra::SQL::Any), returning : T) forall T
      to_update.set(fields).execute_returning(returning)
    end

    # Return primary key values while preserving selected expressions required
    # by the query's ordering and pagination.
    #
    # ```
    # User.query.where { active == true }.ids
    # # => [1, 2, 3, 4, 5]
    #
    # Post.query.where { published == true }.ids
    # # => [10, 25, 42, 100]
    # ```
    #
    # Returns an array of primary key values (typically `Array(Int64)` or `Array(Int32)`).
    def ids : Array(Lustra::SQL::Any)
      key_subquery(T.__pkey__).pluck_col("__lustra_query_key")
    end
  end
end
