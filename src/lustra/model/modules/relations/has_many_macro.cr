# :nodoc:
module Lustra::Model::Relations::HasManyMacro
  # has many
  macro generate(
    self_type,
    method_name,
    relation_type,
    foreign_key = nil,
    primary_key = nil,
    polymorphic_as = nil,
    autosave = false,
  )
    # The method {{ method_name }} is a `has_many` relation to {{ relation_type }}
    def {{ method_name }} : {{ relation_type }}::Collection
      {% if polymorphic_as %}
        unless self.__pkey_column__.defined?
          raise "Cannot access polymorphic association '{{ method_name }}' on an unsaved {{ self_type }} because {{ self_type }}.#{self.__pkey_column__.name} is not defined."
        end
      {% end %}

      %primary_key = {{ (primary_key || "__pkey__").id }}

      %foreign_key =
        {% if foreign_key %}
          "{{ foreign_key }}"
        {% elsif polymorphic_as %}
          "{{ polymorphic_as }}_id"
        {% else %}
          (self.class.table.to_s.singularize + "_id")
        {% end %}

      %type_key =
        {% if polymorphic_as %}
          "{{ polymorphic_as }}_type"
        {% else %}
          nil
        {% end %}

      %tags = { "#{%foreign_key}" => "#{%primary_key}" }
      %tags["#{%type_key}"] = self.class.name if %type_key

      cache = @cache

      query =
        if cache && cache.active?("{{ method_name }}")
          arr = cache.hit("{{ method_name }}", self.__pkey_column__.to_sql_value, {{ relation_type }})

          # This relation will trigger the cache if it exists
          qry =
            {{ relation_type }}
              .query
              .tags(%tags)
              .where { raw(%foreign_key) == %primary_key }

          qry.where { raw(%type_key) == self.class.name } if %type_key

          qry.with_cached_result(arr)
        else
          qry =
            {{ relation_type }}
              .query
              .tags(%tags)
              .where { raw(%foreign_key) == %primary_key }

          qry.where { raw(%type_key) == self.class.name } if %type_key

          qry
        end

      query.append_operation = -> (x : {{ relation_type }}) {
        if x.persisted?
          x.invalidate_caching
          x.set(query.tags)
        else
          x.reset(query.tags)
        end

        x.save! if x.modified?

        x
      }
      query.run_append_operation_after_create = false

      # Set parent model context for autosave functionality
      {% if autosave %}
        query.parent_model = self
        query.association_name = "{{ method_name }}"
        query.autosave = true
      {% end %}

      query
    end

    # Addition of the method for eager loading and N+1 avoidance.
    class Collection
      # Eager load the has many relation {{ method_name }}.
      # Use it to avoid N+1 queries.
      def with_{{ method_name }}(fetch_columns = false, &block : {{ relation_type }}::Collection ->) : self
        before_query_with_context do |query|
          collection = query.as(typeof(self))
          %primary_key = {{ (primary_key || "#{relation_type}.__pkey__").id }}

          %foreign_key =
            {% if foreign_key %}
              "{{ foreign_key }}"
            {% elsif polymorphic_as %}
              "{{ polymorphic_as }}_id"
            {% else %}
              ({{ self_type }}.table.to_s.singularize + "_id")
            {% end %}

          %type_key =
            {% if polymorphic_as %}
              "{{ polymorphic_as }}_type"
            {% else %}
              nil
            {% end %}

          %type_value = {{ self_type }}.name

          #SELECT * FROM foreign WHERE foreign_key IN ( SELECT primary_key FROM users )
          sub_query = collection.key_subquery(%primary_key)

          qry = {{ relation_type }}.query.where { raw(%foreign_key).in?(sub_query) }
          qry.where { raw(%type_key) == %type_value } if %type_key
          block.call(qry)

          collection.cache.active "{{ method_name }}"

          h = {} of Lustra::SQL::Any => Array({{ relation_type }})

          qry.each(fetch_columns: true) do |mdl|
            unless h[mdl.attributes[%foreign_key]]?
              h[mdl.attributes[%foreign_key]] = [] of {{ relation_type }}
            end

            h[mdl.attributes[%foreign_key]] << mdl
          end

          h.each do |key, value|
            collection.cache.set("{{ method_name }}", key, value)
          end
        end

        self
      end

      def with_{{ method_name }}(fetch_columns = false)
        with_{{ method_name }}(fetch_columns) { }
      end
    end
  end
end
