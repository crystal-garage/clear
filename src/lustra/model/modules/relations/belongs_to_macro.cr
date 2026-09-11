# :nodoc:
module Lustra::Model::Relations::BelongsToMacro
  macro generate(
    self_type,
    method_name,
    relation_type,
    nilable,
    foreign_key,
    primary,
    no_cache,
    foreign_key_type,
    touch,
    counter_cache,
    polymorphic = false,
    polymorphic_types = nil,
    polymorphic_type = nil,
  )
    {% foreign_key = foreign_key || method_name.stringify.underscore + "_id" %}
    {% type_key = method_name.stringify.underscore + "_type" %}
    {% fixed_type_key = foreign_key.stringify.gsub(/_id$/, "_type") %}

    {%
      relation_type_nilable =
        if nilable
          "#{relation_type} | Nil".id
        else
          relation_type
        end
    %}

    column {{ foreign_key.id }} : {{ foreign_key_type }}, primary: {{ primary }}, presence: {{ nilable }}
    {% if polymorphic %}
      column {{ type_key.id }} : {{ nilable ? String? : String }}, presence: {{ nilable }}
    {% end %}
    getter _cached_{{ method_name }} : {{ relation_type }}?

    def invalidate_caching
      previous_def

      @_cached_{{ method_name }} = nil

      self
    end

    # The method {{ method_name }} is a `belongs_to` relation to {{ relation_type }}
    def {{ method_name }} : {{ relation_type_nilable }}
      if cached = @_cached_{{ method_name }}
        cached
      else
        cache = @cache

        {% if polymorphic %}
          @_cached_{{ method_name }} =
            case self.{{ type_key.id }}
            {% for target_type in polymorphic_types %}
              {%
                target_type_name = target_type.stringify
                target_type_name = target_type_name[2..] if target_type_name.starts_with?("::")
                if !target_type_name.includes?("::") && self_type.stringify.includes?("::")
                  target_type_name = "#{self_type.stringify.split("::")[0...-1].join("::")}::#{target_type_name}"
                end
              %}
              when {{ target_type_name }}
                if cache && cache.active? "{{ method_name }}"
                  cache.hit("{{ method_name }}",
                    self.{{ foreign_key.id }}_column.to_sql_value, {{ target_type }}
                  ).first? || raise Lustra::SQL::RecordNotFoundError.new
                else
                  {{ target_type }}.query.where { raw({{ target_type }}.__pkey__) == self.{{ foreign_key.id }} }.first!
                end
            {% end %}
            else
              raise "Unknown polymorphic type '#{self.{{ type_key.id }}}' for " + {{ "#{self_type}##{method_name}" }} + "."
            end
        {% else %}
          {% if polymorphic_type %}
            if self.{{ fixed_type_key.id }} != {{ polymorphic_type }}
              {% if nilable %}
                return nil
              {% else %}
                raise Lustra::SQL::RecordNotFoundError.new
              {% end %}
            end
          {% end %}

          if cache && cache.active? "{{ method_name }}"
            {% if nilable %}
              @_cached_{{ method_name }} = cache.hit("{{ method_name }}",
                self.{{ foreign_key.id }}_column.to_sql_value, {{ relation_type }}
              ).first?
            {% else %}
              @_cached_{{ method_name }} = cache.hit("{{ method_name }}",
                self.{{ foreign_key.id }}_column.to_sql_value, {{ relation_type }}
              ).first? || raise Lustra::SQL::RecordNotFoundError.new
            {% end %}
          else
            {% if nilable %}
              qry = {{ relation_type }}.query.where { raw({{ relation_type }}.__pkey__) == self.{{ foreign_key.id }} }
              @_cached_{{ method_name }} = qry.first
            {% else %}
              qry = {{ relation_type }}.query.where { raw({{ relation_type }}.__pkey__) == self.{{ foreign_key.id }} }
              @_cached_{{ method_name }} = qry.first!
            {% end %}
          end
        {% end %}
      end
    end

    {% if nilable %}
      def {{ method_name }}! : {{ relation_type }}
        {{ method_name }}.not_nil!
      end

      def {{ method_name }}=(model : {{ relation_type_nilable }})
        if model
          if model.persisted?
            raise "#{model.__pkey_column__.name} must be defined when assigning a belongs_to relation." unless model.__pkey_column__.defined?

            @{{ foreign_key.id }}_column.value = model.__pkey__
            {% if polymorphic %}
              @{{ type_key.id }}_column.value = model.class.name
            {% elsif polymorphic_type %}
              @{{ fixed_type_key.id }}_column.value = {{ polymorphic_type }}
            {% end %}
          end

          @_cached_{{ method_name }} = model
        else
          @{{ foreign_key.id }}_column.value = nil
          {% if polymorphic %}
            @{{ type_key.id }}_column.value = nil
          {% elsif polymorphic_type %}
            @{{ fixed_type_key.id }}_column.value = nil
          {% end %}
        end
      end
    {% else %}
      def {{ method_name }}=(model : {{ relation_type }})
        if model.persisted?
          raise "#{model.__pkey_column__.name} must be defined when assigning a belongs_to relation." unless model.__pkey_column__.defined?

          @{{ foreign_key.id }}_column.value = model.__pkey__
          {% if polymorphic %}
            @{{ type_key.id }}_column.value = model.class.name
          {% elsif polymorphic_type %}
            @{{ fixed_type_key.id }}_column.value = {{ polymorphic_type }}
          {% end %}
        end

        @_cached_{{ method_name }} = model
      end
    {% end %}

    # :nodoc:
    # save the belongs_to model first if needed
    def _bt_save_{{ method_name }}
      c = @_cached_{{ method_name }}

      return if c.nil?

      if c.persisted?
        @{{ foreign_key.id }}_column.value = c.__pkey__
        {% if polymorphic %}
          @{{ type_key.id }}_column.value = c.class.name
        {% elsif polymorphic_type %}
          @{{ fixed_type_key.id }}_column.value = {{ polymorphic_type }}
        {% end %}
      else
        if c.save
          @{{ foreign_key.id }}_column.value = c.__pkey__
          {% if polymorphic %}
            @{{ type_key.id }}_column.value = c.class.name
          {% elsif polymorphic_type %}
            @{{ fixed_type_key.id }}_column.value = {{ polymorphic_type }}
          {% end %}
        else
          add_error("{{ method_name }}", c.print_errors)
        end
      end
    end

    {% if touch %}
      # :nodoc:
      # touch the parent model's timestamp column
      def _bt_touch_{{ method_name }}
        {% if nilable %}
          parent = {{ method_name }}
          return if parent.nil?
        {% else %}
          parent = {{ method_name }}
        {% end %}

        {% if touch == true %}
          parent.touch
        {% else %}
          # Touch a specific column
          parent.{{ touch }} = Time.local
          parent.save!
        {% end %}

        # Reload the parent to ensure the timestamp is updated
        parent.reload
      end
    {% end %}

    {% if counter_cache %}
      # :nodoc:
      # Execute atomic counter cache update
      def _bt_update_parent_counter_cache_{{ method_name }}(delta : Int32, touch_parent = false)
        {% if nilable %}
          parent = {{ method_name }}

          return if parent.nil?
        {% else %}
          parent = {{ method_name }}
        {% end %}

        {% if counter_cache == true %}
          counter_column_name = "#{self.class.table}_count"
        {% else %}
          counter_column_name = "{{ counter_cache.id }}"
        {% end %}

        escaped_column = Lustra::SQL.escape(counter_column_name)
        operator = delta < 0 ? "-" : "+"
        amount = delta.abs
        updates = {} of String => Lustra::SQL::UpdateQuery::Updatable
        updates[counter_column_name] = Lustra::SQL.unsafe("#{escaped_column} #{operator} #{amount}")
        updates["updated_at"] = Time.local if touch_parent

        Lustra::SQL
          .update(parent.class.full_table_name)
          .set(updates)
          .where { raw(parent.class.__pkey__) == parent.__pkey__ }
          .execute(parent.class.connection)

        parent.reload if touch_parent
      end

      # Register counter cache information with the parent class at runtime.
      # Add initialization code to register counter cache when the class is loaded.
      {% if counter_cache == true %}
        # generate code that interpolates Model.table at runtime
        {{ relation_type }}.register_counter_cache(
          {{ self_type }},
          "#{ {{ self_type }}.table }_count",
          {{ foreign_key.id.stringify }}
        )
      {% else %}
        {{ relation_type }}.register_counter_cache(
          {{ self_type }},
          {{ counter_cache.id.stringify }},
          {{ foreign_key.id.stringify }}
        )
      {% end %}

    {% end %}

    __on_init__ do
      {{ self_type }}.before(:validate) do |mdl|
        mdl.as(self)._bt_save_{{ method_name }}
      end

      {% if touch %}
        {% unless touch == true && counter_cache %}
          {{ self_type }}.after(:create) do |mdl|
            mdl.as(self)._bt_touch_{{ method_name }}
          end
        {% end %}
        {{ self_type }}.after(:update) do |mdl|
          mdl.as(self)._bt_touch_{{ method_name }}
        end
      {% end %}

      {% if counter_cache %}
        {{ self_type }}.after(:create) do |mdl|
          mdl.as(self)._bt_update_parent_counter_cache_{{ method_name }}(
            1,
            touch_parent: {{ touch == true }}
          )
        end
        {{ self_type }}.after(:destroy) do |mdl|
          mdl.as(self)._bt_update_parent_counter_cache_{{ method_name }}(-1)
        end
      {% end %}
    end

    {% if polymorphic %}
      class Collection
        # Eager loading a polymorphic belongs_to relation runs one query for each
        # declared target type, then stores parents in the association cache.
        def with_{{ method_name }}(fetch_columns = false) : self
          before_query_with_context do |query|
            collection = query.as(typeof(self))
            base_query = collection.dup

            collection.cache.active "{{ method_name }}"

            {% for target_type in polymorphic_types %}
              {%
                target_type_name = target_type.stringify
                target_type_name = target_type_name[2..] if target_type_name.starts_with?("::")
                if !target_type_name.includes?("::") && self_type.stringify.includes?("::")
                  target_type_name = "#{self_type.stringify.split("::")[0...-1].join("::")}::#{target_type_name}"
                end
              %}
              source_query = base_query
                .dup
                .where { raw({{ type_key.stringify }}) == {{ target_type_name }} }
              sub_query = collection.key_subquery("{{ foreign_key.id }}", source_query)

              {{ target_type }}.query
                .where { raw("#{{{ target_type }}.table}.#{{{ target_type }}.__pkey__}").in?(sub_query) }
                .each(fetch_columns: fetch_columns) do |mdl|
                  collection.cache.set("{{ method_name }}", mdl.__pkey__, [mdl])
                end
            {% end %}
          end

          self
        end
      end
    {% else %}
      class Collection
        def with_{{ method_name }}(fetch_columns = false, &block : {{ relation_type }}::Collection ->) : self
          before_query_with_context do |query|
            collection = query.as(typeof(self))
            source_query = collection.dup
            {% if polymorphic_type %}
              source_query.where { raw({{ fixed_type_key }}) == {{ polymorphic_type }} }
            {% end %}
            sub_query = collection.key_subquery("{{ foreign_key.id }}", source_query)

            cached_qry = {{ relation_type }}.query.where { raw("#{{{ relation_type }}.table}.#{{{ relation_type }}.__pkey__}").in?(sub_query) }

            block.call(cached_qry)

            collection.cache.active "{{ method_name }}"

            cached_qry.each(fetch_columns: fetch_columns) do |mdl|
              collection.cache.set("{{ method_name }}", mdl.__pkey__, [mdl])
            end
          end

          self
        end

        def with_{{ method_name }}(fetch_columns = false) : self
          with_{{ method_name }}(fetch_columns) { }

          self
        end
      end
    {% end %}
  end
end
