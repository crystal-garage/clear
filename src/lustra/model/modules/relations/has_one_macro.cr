# :nodoc:
module Lustra::Model::Relations::HasOneMacro
  # :nodoc:
  # Write down the code for Has one relation
  macro generate(
    self_type,
    method_name,
    relation_type,
    foreign_key,
    primary_key,
  )
    # Return the related model `{{ method_name }}`.
    #
    # This relation is of type one to zero or one [1, 0..1]
    # between {{ relation_type }} and {{ self_type }}
    #
    # If the relation hasn't been cached, will call a `select` SQL operation.
    # Otherwise, will try to find in the cache.
    def {{ method_name }} : {{ relation_type }}?
      %primary_key = {{ (primary_key || "__pkey__").id }}

      %foreign_key =
        {% if foreign_key %}
          "{{ foreign_key }}"
        {% else %}
          self.class.table.to_s.singularize + "_id"
        {% end %}

      cache = @cache

      if cache && cache.active?("{{ method_name }}")
        arr = cache.hit("{{ method_name }}", self.__pkey_column__.to_sql_value, {{ relation_type }})
        arr.first?
      else
        query = ({{ relation_type }}).query.where { raw(%foreign_key) == %primary_key }.limit(1)
        query.first?
      end
    end

    # Return the related model `{{ method_name }}`,
    # but throw an error if the model is not found.
    def {{ method_name }}! : {{ relation_type }}
      {{ method_name }}.not_nil!
    end

    # Eager loading method for has_one relation
    class Collection
      # Eager load the has_one relation {{ method_name }}.
      # Use it to avoid N+1 queries.
      def with_{{ method_name }}(fetch_columns = false, &block : {{ relation_type }}::Collection ->) : self
        before_query_with_context do |query|
          collection = query.as(typeof(self))
          %primary_key = {{ (primary_key || "#{relation_type}.__pkey__").id }}
          %foreign_key = {% if foreign_key %} "{{ foreign_key }}" {% else %} ({{ self_type }}.table.to_s.singularize + "_id") {% end %}

          # SELECT * FROM foreign WHERE foreign_key IN ( SELECT primary_key FROM parents )
          sub_query = collection.key_subquery(%primary_key)

          qry = {{ relation_type }}.query.where { raw(%foreign_key).in?(sub_query) }
          block.call(qry)

          collection.cache.active "{{ method_name }}"

          h = {} of Lustra::SQL::Any => Array({{ relation_type }})

          qry.each(fetch_columns: true) do |mdl|
            key = mdl.attributes[%foreign_key]
            h[key] = [mdl]
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
