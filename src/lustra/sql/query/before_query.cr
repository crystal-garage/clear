module Lustra::SQL::Query::BeforeQuery
  macro included
    @before_query_triggers : Array(Lustra::SQL::SelectBuilder -> Nil)

    # A hook to apply some operation just before the query is executed.
    #
    # ```
    # call = 0
    # req = Lustra::SQL.select("1").before_query { call += 1 }
    # 10.times { req.execute }
    # pp call # 10
    # ```
    def before_query(&block : -> Nil)
      before_query_with_context { |_| block.call }
    end

    # :nodoc:
    # Pass the executing query so copied hooks do not capture the original query.
    def before_query_with_context(&block : Lustra::SQL::SelectBuilder -> Nil)
      @before_query_triggers << block

      self
    end

    # Remove callbacks registered to run before the query executes.
    def clear_before_query_triggers
      @before_query_triggers = [] of Lustra::SQL::SelectBuilder -> Nil

      self
    end

    # :nodoc:
    protected def trigger_before_query
      @before_query_triggers.each &.call(self)
      @before_query_triggers.clear

      self
    end
  end
end
