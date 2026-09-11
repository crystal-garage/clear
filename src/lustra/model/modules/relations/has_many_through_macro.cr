# :nodoc:
module Lustra::Model::Relations::HasManyThroughMacro
  # has_many through
  macro generate(
    self_type,
    method_name,
    relation_type,
    through,
    own_key = nil,
    foreign_key = nil,
    autosave = false,
  )
    def {{ method_name }} : {{ relation_type }}::Collection
      %final_table = {{ relation_type }}.table
      %final_pkey = {{ relation_type }}.__pkey__

      %through_table = {{ through }}.table

      %through_key =
        {% if foreign_key %}
          "{{ foreign_key }}"
        {% else %}
          {{ relation_type }}.table.to_s.singularize + "_id"
        {% end %}

      %own_key =
        {% if own_key %}
          "{{ own_key }}"
        {% else %}
          {{ self_type }}.table.to_s.singularize + "_id"
        {% end %}

      cache = @cache

      current_model_id = self.__pkey__

      qry =
        {{ relation_type }}.query.select("#{Lustra::SQL.escape(%final_table)}.*")
          .join(Lustra::SQL.escape(%through_table))  {
            var(%through_table, %through_key) == var(%final_table, %final_pkey)
          }.where {
            var(%through_table, %own_key) == current_model_id
          }.distinct("#{Lustra::SQL.escape(%final_table)}.#{Lustra::SQL.escape(%final_pkey)}")

      if cache && cache.active?("{{ method_name }}")
        arr = cache.hit("{{ method_name }}", self.__pkey_column__.to_sql_value, {{ relation_type }})

        qry.with_cached_result(arr)
      end

      qry.append_operation = -> (x : {{ relation_type }}) {
        x.save! unless x.persisted?

        # Check if the association already exists to prevent duplicates
        existing = {{ through }}.query.where({
          %own_key => current_model_id,
          %through_key => x.__pkey__
        }).exists?

        unless existing
          through_model = {{ through }}.new

          through_model.reset({
            "#{%own_key}" => current_model_id,
            "#{%through_key}" => x.__pkey__
          })

          through_model.save!
        end

        x
      }

      # Set parent model context for autosave functionality
      {% if autosave %}
        qry.parent_model = self
        qry.association_name = "{{ method_name }}"
        qry.autosave = true
      {% end %}

      qry.unlink_operation = -> (x : {{ relation_type }}) {
        Lustra::SQL.delete({{ through }}.table).where({
          "#{%own_key}" => current_model_id,
          "#{%through_key}" => x.__pkey__
        }).execute

        x
      }

      qry
    end

    # Addition of the method for eager loading and N+1 avoidance.
    class Collection
      # Eager load the relation {{ method_name }}.
      # Use it to avoid N+1 queries.
      def with_{{ method_name }}(&block : {{ relation_type }}::Collection ->) : self
        before_query_with_context do |query|
          collection = query.as(typeof(self))
          %final_table = {{ relation_type }}.table
          %final_pkey = {{ relation_type }}.__pkey__
          %through_table = {{ through }}.table

          %through_key =
            {% if foreign_key %}
              "{{ foreign_key }}"
            {% else %}
              {{ relation_type }}.table.to_s.singularize + "_id"
            {% end %}

          %own_key =
            {% if own_key %}
              "{{ own_key }}"
            {% else %}
              {{ self_type }}.table.to_s.singularize + "_id"
            {% end %}

          self_type = {{ self_type }}

          collection.cache.active "{{ method_name }}"

          sub_query = collection.key_subquery(self_type.__pkey__)

          qry = {{ relation_type }}.query.join(%through_table) {
            var(%through_table, %through_key) == var(%final_table, %final_pkey)
          }.where {
            var(%through_table, %own_key).in?(sub_query)
          }.distinct.select( "#{Lustra::SQL.escape(%final_table)}.*",
            "#{Lustra::SQL.escape(%through_table)}.#{Lustra::SQL.escape(%own_key)} AS __own_id"
          )

          block.call(qry)

          h = {} of Lustra::SQL::Any => Array({{ relation_type }})

          qry.each(fetch_columns: true) do |mdl|
            unless h[mdl.attributes["__own_id"]]?
              h[mdl.attributes["__own_id"]] = [] of {{ relation_type }}
            end

            h[mdl.attributes["__own_id"]] << mdl
          end

          h.each do |key, value|
            collection.cache.set("{{ method_name }}", key, value)
          end
        end

        self
      end

      def with_{{ method_name }}
        with_{{ method_name }} { }
      end
    end

    # Handle append operation for through associations (called by autosave system)
    def __trigger_append_operation_for_association__(association_name : String, models : Array(Lustra::Model))
      if association_name == "{{ method_name }}"
        %own_key =
          {% if own_key %}
            "{{ own_key }}"
          {% else %}
            {{ self_type }}.table.to_s.singularize + "_id"
          {% end %}

        %through_key =
          {% if foreign_key %}
            "{{ foreign_key }}"
          {% else %}
            {{ relation_type }}.table.to_s.singularize + "_id"
          {% end %}

        models.each do |model|
          through_model = {{ through }}.new

          through_model.reset({
            %own_key => self.__pkey__,
            %through_key => model.__pkey__
          })

          through_model.save!
        end
      end
    end
  end
end
