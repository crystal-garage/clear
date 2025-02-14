# :nodoc:
module Clear::Model::Relations::BelongsToMacro
  macro generate(self_type, method_name, relation_type, nilable, foreign_key, primary, no_cache, foreign_key_type)
    {% foreign_key = foreign_key || method_name.stringify.underscore + "_id" %}

    {%
      relation_type_nilable =
        if nilable
          "#{relation_type} | Nil".id
        else
          relation_type
        end
    %}

    column {{foreign_key.id}} : {{foreign_key_type}}, primary: {{primary}}, presence: {{nilable}}
    getter _cached_{{method_name}} : {{relation_type}}?

    protected def invalidate_caching
      previous_def

      @_cached_{{method_name}} = nil

      self
    end

    # The method {{method_name}} is a `belongs_to` relation to {{relation_type}}
    def {{method_name}} : {{relation_type_nilable}}
      if cached = @_cached_{{method_name}}
        cached
      else
        cache = @cache

        if cache && cache.active? "{{method_name}}"
          {% if nilable %}
            @_cached_{{method_name}} = cache.hit("{{method_name}}",
              self.{{foreign_key.id}}_column.to_sql_value, {{relation_type}}
            ).first?
          {% else %}
            @_cached_{{method_name}} = cache.hit("{{method_name}}",
              self.{{foreign_key.id}}_column.to_sql_value, {{relation_type}}
            ).first? || raise Clear::SQL::RecordNotFoundError.new
          {% end %}
        else
          {% if nilable %}
            @_cached_{{method_name}} = {{relation_type}}.query.where { raw({{relation_type}}.__pkey__) == self.{{foreign_key.id}} }.first
          {% else %}
            @_cached_{{method_name}} = {{relation_type}}.query.where { raw({{relation_type}}.__pkey__) == self.{{foreign_key.id}} }.first!
          {% end %}
        end
      end
    end

    {% if nilable %}
      def {{method_name}}! : {{relation_type}}
        {{method_name}}.not_nil!
      end

      def {{method_name}}=(model : {{relation_type_nilable}})
        if model
          if model.persisted?
            raise "#{model.__pkey_column__.name} must be defined when assigning a belongs_to relation." unless model.__pkey_column__.defined?

            @{{foreign_key.id}}_column.value = model.__pkey__
          end

          @_cached_{{method_name}} = model
        else
          @{{foreign_key.id}}_column.value = nil
        end
      end
    {% else %}
      def {{method_name}}=(model : {{relation_type}})
        if model.persisted?
          raise "#{model.__pkey_column__.name} must be defined when assigning a belongs_to relation." unless model.__pkey_column__.defined?

          @{{foreign_key.id}}_column.value = model.__pkey__
        end

        @_cached_{{method_name}} = model
      end
    {% end %}

    # :nodoc:
    # save the belongs_to model first if needed
    def _bt_save_{{method_name}}
      c = @_cached_{{method_name}}

      return if c.nil?

      if c.persisted?
        @{{foreign_key.id}}_column.value = c.__pkey__
      else
        if c.save
          @{{foreign_key.id}}_column.value = c.__pkey__
        else
          add_error("{{method_name}}", c.print_errors)
        end
      end
    end

    __on_init__ do
      {{self_type}}.before(:validate) do |mdl|
        mdl.as(self)._bt_save_{{method_name}}
      end
    end

    class Collection
      def with_{{method_name}}(fetch_columns = false, &block : {{relation_type}}::Collection ->) : self
        before_query do
          sub_query = self.dup.clear_select.select("#{{{self_type}}.table}.{{foreign_key.id}}")

          cached_qry = {{relation_type}}.query.where { raw("#{{{relation_type}}.table}.#{{{relation_type}}.__pkey__}").in?(sub_query) }

          block.call(cached_qry)

          @cache.active "{{method_name}}"

          cached_qry.each(fetch_columns: fetch_columns) do |mdl|
            @cache.set("{{method_name}}", mdl.__pkey__, [mdl])
          end
        end

        self
      end

      def with_{{method_name}}(fetch_columns = false) : self
        with_{{method_name}}(fetch_columns) { }

        self
      end
    end
  end
end
