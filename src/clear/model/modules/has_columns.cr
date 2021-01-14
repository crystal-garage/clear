require "inflector/core_ext"
require "pg"

# This module declare all the methods and macro related to columns in `Clear::Model`
module Clear::Model::HasColumns
  macro included # In Clear::Model
    macro included # In RealModel
      COLUMNS = {} of Nil => Nil
      # Attributes, used when fetch_columns is true
      getter attributes : Hash(String, ::Clear::SQL::Any) = {} of String => ::Clear::SQL::Any

      # Special reinitialization if we detect inheritance (meaning polymorphism)
      macro inherited
        # Reset COLUMNS constants
        COLUMNS = {} of Nil => Nil
        # Table is same than parent table
        self.table = \\{{@type.ancestors.first}}.table
      end
    end
  end

  # Reset one or multiple columns; Reseting set the current value of the column
  # to the given value, while the `changed?` flag remains false.
  # If you call save on a persisted model, the reset columns won't be
  # commited in the UPDATE query.
  def reset(**t : **T) forall T
    # Dev note:
    # ---------
    # The current implementation of reset is overriden on finalize (see below).
    # This method is a placeholder to ensure that we can call `super`
    # in case of inherited (polymorphic) models
  end

  # See `reset(**t : **T)`
  def reset(h : Hash(String, _))
  end

  # See `reset(**t : **T)`
  def reset(h : Hash(Symbol, _))
  end

  # Set one or multiple columns to a specific value
  # This two are equivalents:
  #
  # ```
  # model.set(a: 1)
  # model.a = 1
  # ```
  def set(**t : **T) forall T
    # Dev note:
    # ---------
    # The current implementation of set is overriden on finalize (see below).
    # This method is a placeholder to ensure that we can call `super`
    # in case of inherited (polymorphic) models
  end

  # See `set(**t : **T)`
  def set(h : Hash(String, _))
  end

  # See `set(**t : **T)`
  def set(h : Hash(Symbol, _))
  end

  # Access to direct SQL attributes given by the request used to build the model.
  # Access is read only and updating the model columns will not apply change to theses columns.
  #
  # ```
  # model = Model.query.select("MIN(id) as min_id").first(fetch_columns: true)
  # id = model["min_id"].to_i32
  # ```
  def [](x) : ::Clear::SQL::Any
    attributes[x]
  end

  # Access to direct SQL attributes given by the request and used to build the model
  # or Nil if not found.
  #
  # Access is read only and updating the model columns will not apply change to theses columns.
  # You must set `fetch_column: true` in your model to access the attributes.
  def []?(x) : ::Clear::SQL::Any
    attributes[x]?
  end

  # Returns the current hash of the modified values:
  #
  # ```
  # model = Model.query.first!
  # model.update_h # => {}
  # model.first_name = "hello"
  # model.update_h # => { "first_name" => "hello" }
  # model.save!
  # model.update_h # => {}
  # ```
  def update_h
    {} of String => ::Clear::SQL::Any
  end

  # Returns the model columns as Hash.
  # Calling `to_h` will returns only the defined columns, while settings the optional parameter `full` to `true`
  #   will return all the column and fill the undefined columns by `nil` values.
  # Example:
  #
  # ```
  # # Assuming our model has a primary key, a first name and last name and two timestamp columns:
  # model = Model.query.select("first_name, last_name").first!
  # model.to_h             # => { "first_name" => "Johnny", "last_name" => "Walker" }
  # model.to_h(full: true) # => {"id" => nil, "first_name" => "Johnny", "last_name" => "Walker", "created_at" => nil, "updated_at" => nil}
  # ```
  def to_h(full = false)
    {} of String => ::Clear::SQL::Any
  end

  # Bind a column to the model.
  #
  # Simple example:
  # ```
  # class MyModel
  #   include Clear::Model
  #
  #   column some_id : Int32, primary: true
  #   column nullable_column : String?
  # end
  # ```
  # options:
  #
  # * `primary : Bool`: Let Clear ORM know which column is the primary key.
  # Currently compound primary key are not compatible with Clear ORM.
  #
  # * `converter : Class | Module`: Use this class to convert the data from the
  # SQL. This class must possess the class methods
  # `to_column(::Clear::SQL::Any) : T` and `to_db(T) : ::Clear::SQL::Any`
  # with `T` the type of the column.
  #
  # * `column_name : String`: If the name of the column in the model doesn't fit the name of the
  #   column in the SQL, you can use the parameter `column_name` to tell Clear about
  #   which db column is linked to current field.
  #
  # * `presence : Bool (default = true)`: Use this option to let know Clear that
  #   your column is not nullable but with default value generated by the database
  #   on insert (e.g. serial)
  # During validation before saving, the presence will not be checked on this field
  #   and Clear will try to insert without the field value.
  #
  macro column(name, primary = false, converter = nil, column_name = nil, presence = true)
    {% _type = name.type %}
    {%
      unless converter
        if _type.is_a?(Path)
          if _type.resolve.stringify =~ /\(/
            converter = _type.stringify
          else
            converter = _type.resolve.stringify
          end
        elsif _type.is_a?(Generic) # Union?
          if _type.name.stringify == "::Union"
            converter = (_type.type_vars.map(&.resolve).map(&.stringify).sort.reject { |x| x == "Nil" || x == "::Nil" }.join("")).id.stringify
          else
            converter = _type.resolve.stringify
          end
        elsif _type.is_a?(Union)
          converter = (_type.types.map(&.resolve).map(&.stringify).sort.reject { |x| x == "Nil" || x == "::Nil" }.join("")).id.stringify
        else
          raise "Unknown: #{_type}, #{_type.class}"
        end
      end
    %}

    {%
      db_column_name = column_name == nil ? name.var : column_name.id

      COLUMNS["#{db_column_name.id}"] = {
        type:                  _type,
        primary:               primary,
        converter:             converter,
        db_column_name:        "#{db_column_name.id}",
        crystal_variable_name: name.var,
        presence:              presence,
      }
    %}
  end

  # :nodoc:
  # Used internally to gather the columns
  macro __generate_columns__
    {% for db_column_name, settings in COLUMNS %}
      {% type = settings[:type] %}

      {% var_name = settings[:crystal_variable_name] %}
      {% db_name = settings[:db_column_name] %}

      {% has_db_default = !settings[:presence] %}
      {% converter = Clear::Model::Converter::CONVERTERS[settings[:converter]] %}
      {% if converter == nil %}
        {% raise "No converter found for `#{settings[:converter].id}`.\n" +
                 "The type is probably not supported natively by Clear.\n" +
                 "Please refer to the manual to create a custom converter." %}
      {% end %}

      @{{var_name}}_column : Clear::Model::Column({{type}}, {{converter}}) =
        Clear::Model::Column({{type}}, {{converter}}).new({{db_name}},
        has_db_default: {{has_db_default}} )

      # Returns the column object used to manage `{{var_name}}` field
      #
      # See `Clear::Model::Column`
      def {{var_name}}_column : Clear::Model::Column({{type}}, {{converter}})
        @{{var_name}}_column
      end

      # Returns the value of `{{var_name}}` column or throw an exception if the column is not defined.
      def {{var_name}} : {{type}}
        @{{var_name}}_column.value
      end

      # Setter for `{{var_name}}` column.
      def {{var_name}}=(x : {{type}})
        @{{var_name}}_column.value = x
      end

      {% if settings[:primary] %}
        # :nodoc:
        class_property pkey : String = "{{var_name}}"

        # :nodoc:
        def pkey
          @{{var_name}}_column.value
        end

        # :nodoc:
        def pkey_column
          @{{var_name}}_column
        end
      {% end %}
    {% end %}

    # reset flavors
    def reset( **t : **T ) forall T
      super

      \{% for name, typ in T %}

        \{% if settings = COLUMNS["#{name}"] %}
          @\{{settings[:crystal_variable_name]}}_column.reset_convert(t[:\{{name}}])
        \{% else %}
          \{% if !@type.has_method?("#{name}=") %}
            \{% raise "No method #{@type}##{name}= while trying to set value of #{name}" %}
          \{% end %}
          self.\{{name}} = t[:\{{name}}]
        \{% end %}
      \{% end %}

      self
    end

    def reset( t : NamedTuple )
      reset(**t)
    end

    # Set the columns from hash
    def reset( h : Hash(Symbol, _) )
      super

      \{% for name, settings in COLUMNS %}
        v = h.fetch(:\{{settings[:db_column_name]}}){ Column::UNKNOWN }
        @\{{settings[:crystal_variable_name]}}_column.reset_convert(v) unless v.is_a?(Column::UnknownClass)
      \{% end %}

      self
    end

    # Set the model fields from hash
    def reset( h : Hash(String, _) )
      super

      \{% for name, settings in COLUMNS %}
        v = h.fetch(\{{settings[:db_column_name]}}){ Column::UNKNOWN }
        @\{{settings[:crystal_variable_name]}}_column.reset_convert(v) unless v.is_a?(Column::UnknownClass)
      \{% end %}

      self
    end

    def reset( from_json : JSON::Any )
      reset(from_json.as_h)
    end

    def set( **t : **T ) forall T
      super

      \{% for name, typ in T %}
        \{% if settings = COLUMNS["#{name}".id] %}
          @\{{settings[:crystal_variable_name]}}_column.set_convert(t[:\{{name}}])
        \{% else %}
          \{% if !@type.has_method?("#{name}=") %}
            \{% raise "No method #{@type}##{name}= while trying to set value of #{name}" %}
          \{% end %}
          self.\{{name}} = t[:\{{name}}]
        \{% end %}
      \{% end %}

      self
    end

    def set( t : NamedTuple )
      set(**t)
    end

    # Set the columns from hash
    def set( h : Hash(Symbol, _) )
      super

      \{% for name, settings in COLUMNS %}
        v = h.fetch(:\{{settings[:db_column_name]}}){ Column::UNKNOWN }
        @\{{settings[:crystal_variable_name]}}_column.set_convert(v) unless v.is_a?(Column::UnknownClass)
      \{% end %}

      self
    end

    # Set the model fields from hash
    def set( h : Hash(String, _) )
      super

      \{% for name, settings in COLUMNS %}
        v = h.fetch(\{{settings[:db_column_name]}}){ Column::UNKNOWN }
        @\{{settings[:crystal_variable_name]}}_column.set_convert(v) unless v.is_a?(Column::UnknownClass)
      \{% end %}

      self
    end

    def set( from_json : JSON::Any )
      set(from_json.as_h)
    end


    # Generate the hash for update request (like during save)
    def update_h : Hash(String, ::Clear::SQL::Any)
      o = super

      {% for name, settings in COLUMNS %}
        if @{{settings[:crystal_variable_name]}}_column.defined? &&
           @{{settings[:crystal_variable_name]}}_column.changed?
          o[{{settings[:db_column_name]}}] = @{{settings[:crystal_variable_name]}}_column.to_sql_value
        end
      {% end %}

      o
    end

    # set flavors


    # For each column, ensure than when needed the column has present
    # information into it.
    #
    # This method is called on validation.
    def validate_fields_presence
      # It should have only zero (non-polymorphic) or
      # one (polymorphic) ancestor inheriting from Clear::Model
      {% for ancestors in @type.ancestors %}{% if ancestors < Clear::Model %}
        super
      {% end %}{% end %}

      {% for name, settings in COLUMNS %}
        unless persisted?
          if @{{settings[:crystal_variable_name]}}_column.failed_to_be_present?
            add_error({{settings[:crystal_variable_name].stringify}}, "must be present")
          end
        end
      {% end %}
    end

    # Reset the `changed?` flag on all columns
    #
    # The model behave like its not dirty anymore
    # and call to save would apply no changes.
    #
    # Returns `self`
    def clear_change_flags
      {% for name, settings in COLUMNS %}
        @{{settings[:crystal_variable_name]}}_column.clear_change_flag
      {% end %}

      self
    end

    # Return a hash version of the columns of this model.
    def to_h(full = false) : Hash(String, ::Clear::SQL::Any)
      out = super

      {% for name, settings in COLUMNS %}
        if full || @{{settings[:crystal_variable_name]}}_column.defined?
          out[{{settings[:db_column_name]}}] = @{{settings[:crystal_variable_name]}}_column.to_sql_value(nil)
        end
      {% end %}

      out
    end

    def to_json(emit_nulls : Bool = false)
      JSON.build{ |json| to_json(json, emit_nulls) }
    end

    def to_json(json, emit_nulls = false)
      json.object do
        {% for name, settings in COLUMNS %}
        if emit_nulls || @{{settings[:crystal_variable_name]}}_column.defined?
          json.field {{settings[:db_column_name]}} do
            @{{settings[:crystal_variable_name]}}_column.value(nil).to_json(json)
          end
        end
        {% end %}
      end
    end

    # Return `true` if the model is dirty (e.g. one or more fields
    #   have been changed.). Return `false` otherwise.
    def changed?
      {% for name, settings in COLUMNS %}
          return true if @{{settings[:crystal_variable_name]}}_column.changed?
      {% end %}

      return false
    end

  end
end
