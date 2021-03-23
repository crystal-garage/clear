module Clear::SQL
  module Query::From
    getter froms : Array(SQL::From)

    def from(*args)
      args.each do |arg|
        case arg
        when NamedTuple
          arg.each { |k, v| @froms << Clear::SQL::From.new(v, k.to_s) }
        else
          @froms << Clear::SQL::From.new(arg)
        end
      end

      change!
    end

    def clear_from
      @froms.clear
      change!
    end

    protected def print_froms
      unless @froms.empty?
        "FROM " + @froms.join(", ", &.to_sql)
      end
    end
  end
end
