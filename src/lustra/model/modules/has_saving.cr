# This module handles saving models to the database and triggering lifecycle
# callbacks. It is where the actual `:create`, `:update`, `:destroy`, and
# `:save` callbacks are triggered.
#
# Key callback trigger points:
# - `:save` callbacks: triggered for the entire save operation (wraps create/update)
# - `:create` callbacks: triggered when a new record is created
# - `:update` callbacks: triggered when an existing record is updated
# - `:destroy` callbacks: triggered when a record is destroyed
#
# The callbacks are triggered via `with_triggers`, which calls
# `Lustra::Model::EventManager`.
module Lustra::Model::HasSaving
  # Default class-wise read_only? method is `false`
  macro included # When included into Model
    macro included # When included into final Model
      class_property? read_only : Bool = false

      # Import a batch of models in one SQL insert query.
      # Each model must be non-persisted.
      #
      # `on_conflict` callback can be optionally enabled to manage database
      # constraints.
      #
      # Note: Old models are not modified. This method returns a copy of the
      # models as saved in the database.
      #
      # ## Example:
      #
      # ```
      # users = [User.new(id: 1), User.new(id: 2), User.new(id: 3)]
      # users = User.import(users)
      # ```
      def self.import(array : Enumerable(self), on_conflict : (Lustra::SQL::InsertQuery ->)? = nil)
        array.each do |item|
          raise "One of your model is persisted while calling import" if item.persisted?
        end

        hashes = array.map do |item|
          item.trigger_before_events(:save)
          raise "import: Validation failed for `#{item}`" unless item.valid?
          item.trigger_before_events(:create)
          item.to_h
        end

        query = Lustra::SQL.insert_into(self.table, hashes).returning("*")
        on_conflict.call(query) if on_conflict

        o = [] of self
        query.fetch(@@connection) do |hash|
          o << Lustra::Model::Factory.build(self.name, hash, persisted: true,
            fetch_columns: false, cache: nil).as(self)
        end

        o.each(&.trigger_after_events(:create))
        o.each(&.trigger_after_events(:save))

        o
      end
    end
  end

  getter? persisted : Bool

  # Save the model. If the model is already persisted, it calls an `UPDATE`
  # query. If the model is not persisted, it calls `INSERT`.
  #
  # Optionally, you can pass a `Proc` to refine the `INSERT` with on conflict
  # resolution functions.
  #
  # Return `false` if the model cannot be saved due to validation issues.
  # Return `true` if the model has been saved correctly.
  #
  # Example:
  #
  # ```
  # u = User.new
  # if u.save
  #   puts "User correctly saved !"
  # else
  #   puts "There was a problem during save: "
  #   # do something with `u.errors`
  # end
  # ```
  #
  # ## `on_conflict` optional parameter
  #
  # Example:
  #
  # ```
  # u = User.new id: 123, email: "email@example.com"
  # u.save(-> (qry) { qry.on_conflict.do_update { |u| u.set(email: "email@example.com") } #update
  # # IMPORTANT NOTICE: user may not be saved, but will still be detected as persisted!
  # ```
  #
  # You may want to use a block for the optional `on_conflict` parameter:
  #
  # ```
  # u = User.new id: 123, email: "email@example.com"
  # u.save do |qry|
  #    qry.on_conflict.do_update { |u| u.set(email: "email@example.com")
  # end
  # ```
  #
  def save(on_conflict : (Lustra::SQL::InsertQuery ->)? = nil)
    return false if self.class.read_only?

    with_triggers(:save) do
      if valid?
        if persisted?
          h = update_h
          unless h.empty?
            with_triggers(:update) do
              save_main_model(on_conflict)
            end
          end
        else
          with_triggers(:create) do
            save_main_model(on_conflict)
          end
        end

        clear_change_flags

        return true
      else
        return false
      end
    end
  end

  def save(&block)
    save(on_conflict: block)
  end

  # Performs `save` call, but instead of returning `false` if validation failed,
  # raise `Lustra::Model::InvalidError` exception
  # Automatically handles built associations
  def save!(on_conflict : (Lustra::SQL::InsertQuery ->)? = nil)
    raise Lustra::Model::ReadOnlyError.new(self) if self.class.read_only?

    if has_built_associations?
      raise Lustra::Model::InvalidError.new(self) unless save_with_associations(on_conflict)
    else
      raise Lustra::Model::InvalidError.new(self) unless save(on_conflict)
    end

    self
  end

  # Pass the `on_conflict` optional parameter via block.
  def save!(&block : Lustra::SQL::InsertQuery ->)
    save!(block)
  end

  # Save the model along with all built associations
  def save_with_associations(on_conflict : (Lustra::SQL::InsertQuery ->)? = nil)
    return false if self.class.read_only?

    with_triggers(:save) do
      if valid?
        save_built_associations

        if persisted?
          h = update_h
          unless h.empty?
            with_triggers(:update) do
              save_main_model(on_conflict)
            end
          end
        else
          with_triggers(:create) do
            save_main_model(on_conflict)
          end
        end

        handle_through_associations

        clear_change_flags
        clear_built_associations

        return true
      else
        return false
      end
    end
  end

  # Set the fields passed as argument and call `save` on the object
  def update(**args)
    set(**args)
    save
  end

  # Set the fields passed as argument and call `save!` on the object
  def update!(**args)
    set(**args)
    save!
  end

  # :nodoc:
  def update(named_tuple : NamedTuple)
    set(named_tuple)
    save
  end

  # :nodoc:
  def update!(named_tuple : NamedTuple)
    set(named_tuple)
    save!
  end

  def reload : self
    set(self.class.query.where { var("#{self.class.__pkey__}") == __pkey__ }.fetch_first!)

    invalidate_caching

    @attributes.clear
    clear_change_flags
    @persisted = true

    self
  end

  # Delete the model from the database WITHOUT running callbacks.
  # Use this for performance when you don't need to trigger callbacks.
  # The deleted model is not persisted anymore and can be saved again.
  #
  # ```
  # user.delete
  # user.persisted? # => false
  # ```
  #
  # Returns `true` if successfully deleted, `false` otherwise.
  def delete
    return false unless persisted?

    Lustra::SQL::DeleteQuery.new.from(self.class.full_table_name).where { var("#{self.class.__pkey__}") == __pkey__ }.execute(@@connection)

    @persisted = false
    clear_change_flags

    true
  end

  # Destroy the model from the database WITH callbacks and validations.
  # This is the safe way to delete records as it triggers all `:destroy` callbacks.
  # The destroyed model is not persisted anymore and can be saved again.
  #
  # ```
  # user.destroy    # Triggers before(:destroy) and after(:destroy) callbacks
  # user.persisted? # => false
  # ```
  #
  # Returns `true` if successfully destroyed, `false` otherwise.
  def destroy
    return false unless persisted?

    with_triggers(:destroy) do
      Lustra::SQL::DeleteQuery.new.from(self.class.full_table_name).where { var("#{self.class.__pkey__}") == __pkey__ }.execute(@@connection)

      @persisted = false
      clear_change_flags
    end

    true
  end

  # Increment a numeric column by a specific amount (default 1) without running validations or callbacks.
  # Updates the database directly and updates the in-memory value.
  #
  # ```
  # user.increment!(:login_count)   # Increment by 1
  # user.increment!(:score, 10)     # Increment by 10
  # user.increment!(:balance, -5.5) # Can use negative values
  # ```
  #
  # Returns `self` for chaining.
  def increment!(column : Symbol | String, by : Number = 1)
    raise "Model must be persisted before incrementing" unless persisted?

    column_name = column.to_s

    # Update database atomically
    escaped_column = Lustra::SQL.escape(column_name)
    updates = {} of String => Lustra::SQL::UpdateQuery::Updatable
    updates[column_name] = Lustra::SQL.unsafe("#{escaped_column} + #{Lustra::Expression[by]}")
    Lustra::SQL.update(self.class.full_table_name)
      .set(updates)
      .where { raw(self.class.__pkey__) == __pkey__ }
      .execute(@@connection)

    # Update in-memory value by reloading just this column
    result = Lustra::SQL.select(column_name).from(self.class.full_table_name).where { raw(self.class.__pkey__) == __pkey__ }.use_connection(@@connection).fetch_first!
    reset({column_name => result[column_name]})

    self
  end

  # Increment a numeric column without saving to the database.
  # Only updates the in-memory value. Call `save!` to persist.
  #
  # ```
  # user.increment(:login_count)
  # user.save! # Persist the change
  # ```
  #
  # Returns `self` for chaining.
  def increment(column : Symbol | String, by : Number = 1)
    column_name = column.to_s

    current_value = to_h[column_name]

    # Increment the value
    new_value =
      case current_value
      when Int32   then current_value + by.to_i32
      when Int64   then current_value + by.to_i64
      when Float32 then current_value + by.to_f32
      when Float64 then current_value + by.to_f64
      else
        raise "Column #{column_name} is not a numeric type"
      end

    set({column_name => new_value})
    self
  end

  # Decrement a numeric column by a specific amount (default 1) without running validations or callbacks.
  # Updates the database directly and updates the in-memory value.
  #
  # ```
  # user.decrement!(:attempts_left) # Decrement by 1
  # user.decrement!(:balance, 10.5) # Decrement by 10.5
  # ```
  #
  # Returns `self` for chaining.
  def decrement!(column : Symbol | String, by : Number = 1)
    increment!(column, -by)
  end

  # Decrement a numeric column without saving to the database.
  # Only updates the in-memory value. Call `save!` to persist.
  #
  # ```
  # user.decrement(:attempts_left)
  # user.save! # Persist the change
  # ```
  #
  # Returns `self` for chaining.
  def decrement(column : Symbol | String, by : Number = 1)
    increment(column, -by)
  end

  # Update a single column directly in the database without running validations or callbacks.
  # This is useful for updating columns that don't need validation (like counters, flags, timestamps).
  #
  # ```
  # user.update_column(:login_count, 10)
  # user.update_column(:last_login_at, Time.utc)
  # ```
  #
  # **Warning:** This bypasses:
  # - Validations
  # - Callbacks
  # - Timestamp updates (updated_at will NOT change)
  #
  # Returns `self` for chaining.
  def update_column(column : Symbol | String, value)
    column_name = column.to_s
    update_columns_direct({column_name => value})
  end

  # Update multiple columns directly in the database without running validations or callbacks.
  #
  # ```
  # user.update_columns(login_count: 10, last_login_at: Time.utc)
  # user.update_columns({status: "active", verified: true})
  # ```
  #
  # **Warning:** This bypasses:
  # - Validations
  # - Callbacks
  # - Timestamp updates (updated_at will NOT change)
  #
  # Returns `self` for chaining.
  def update_columns(**columns)
    update_columns_direct(columns)
  end

  # :ditto:
  def update_columns(columns : NamedTuple)
    update_columns_direct(columns)
  end

  # :ditto:
  def update_columns(columns : Hash(String, Lustra::SQL::Any))
    update_columns_direct(columns)
  end

  private def update_columns_direct(columns)
    raise "Model must be persisted before updating columns" unless persisted?

    # Update database directly
    Lustra::SQL.update(self.class.full_table_name)
      .set(columns)
      .where { raw(self.class.__pkey__) == __pkey__ }
      .execute(@@connection)

    # Update in-memory values
    reset(columns)

    self
  end

  private def save_built_associations
    built_associations.each do |_, models|
      models.each do |model|
        model.save! unless model.persisted?
      end
    end
  end

  private def save_main_model(on_conflict : (Lustra::SQL::InsertQuery ->)? = nil)
    if persisted?
      h = update_h

      unless h.empty?
        Lustra::SQL.update(self.class.full_table_name).set(update_h).where { var("#{self.class.__pkey__}") == __pkey__ }.execute(@@connection)
      end
    else
      query = Lustra::SQL.insert_into(self.class.full_table_name, to_h).returning("*")
      on_conflict.call(query) if on_conflict
      hash = query.execute(@@connection)

      reset(hash)
      @persisted = true
    end
  end

  private def handle_through_associations
    # Handle has_many through relationships after main model is saved
    # This avoids recursion because the main model is already persisted
    built_associations.each do |association_name, models|
      # Call the trigger method on the parent model (self) with the built models
      if self.responds_to?(:__trigger_append_operation_for_association__)
        self.__trigger_append_operation_for_association__(association_name, models)
      end
    end
  end
end
