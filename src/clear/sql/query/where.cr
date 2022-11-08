# Feature WHERE clause building.
# each call to where method stack where clause.
# Theses clauses are then combined together using the `AND` operator.
# Therefore, `query.where("a").where("b")` will return `a AND b`
#
module Clear::SQL::Query::Where
  macro included
    # Return the list of where clause; each where clause are transformed into
    # Clear::Expression::Node
    getter wheres : Array(Clear::Expression::Node)
  end

  # Build SQL `where` condition using a Clear::Expression::Node
  #
  # ```
  # query.where(Clear::Expression::Node::InArray.new("id", ['1', '2', '3', '4']))
  # # Note: in this example, InArray node use unsafe strings
  # ```
  #
  # If useful for moving a where clause from a request to another one:
  #
  # ```
  # query1.where { a == b } # WHERE a = b
  # ```
  #
  # ```
  # query2.where(query1.wheres[0]) # WHERE a = b
  # ```
  def where(node : Clear::Expression::Node)
    @wheres << node

    change!
  end

  # Build SQL `where` condition using the Expression engine.
  #
  # ```
  # query.where { id == 1 }
  # ```
  def where(&block)
    where(Clear::Expression.ensure_node!(with Clear::Expression.new yield))
  end

  def where(**tuple)
    where(conditions: tuple)
  end

  # Build SQL `where` condition using a NamedTuple.
  # this will use:
  # - the `=` operator if compared with a literal
  #
  # ```
  # query.where({keyword: "hello"}) # WHERE keyword = 'hello'
  # ```
  #
  # - the `IN` operator if compared with an array:
  #
  # ```
  # query.where({x: [1, 2]}) # WHERE x in (1,2)
  # ```
  #
  # - the `>=` and `<=` | `<` if compared with a range:
  #
  # ```
  # query.where({x: (1..4)})  # WHERE x >= 1 AND x <= 4
  # query.where({x: (1...4)}) # WHERE x >= 1 AND x < 4
  # ```
  #
  # - You also can put another select query as argument:
  #
  # ```
  # query.where({x: another_select}) # WHERE x IN (SELECT ... )
  # ```
  def where(conditions : NamedTuple | Hash(String, Clear::SQL::Any))
    conditions.each do |k, v|
      k = Clear::Expression::Node::Variable.new(k.to_s)

      @wheres <<
        case v
        when Array
          Clear::Expression::Node::InArray.new(k, v.map { |it| Clear::Expression[it] })
        when SelectBuilder
          Clear::Expression::Node::InSelect.new(k, v)
        when Range
          Clear::Expression::Node::InRange.new(k,
            Clear::Expression[v.begin]..Clear::Expression[v.end],
            v.exclusive?)
        else
          Clear::Expression::Node::DoubleOperator.new(k,
            Clear::Expression::Node::Literal.new(v),
            (v.nil? ? "IS" : "=")
          )
        end
    end

    change!
  end

  # Build SQL `where` interpolating `:keyword` with the NamedTuple passed in argument.
  #
  # ```
  # where("id = :id OR date >= :start", id: 1, start: 1.day.ago)
  # # WHERE id = 1 AND date >= '201x-xx-xx ...'
  # ```
  def where(template : String, **tuple)
    where(Clear::Expression::Node::Raw.new(Clear::SQL.raw(template, **tuple)))
  end

  # Build SQL `where` condition using a template string and
  # interpolating `?` characters with parameters given in a tuple or array.
  #
  # ```
  # where("x = ? OR y = ?", 1, "l'eau") # WHERE x = 1 OR y = 'l''eau'
  # ```
  #
  # Raise error if there's not enough parameters to cover all the `?` placeholders
  def where(template : String, *args)
    where(Clear::Expression::Node::Raw.new(Clear::SQL.raw(template, *args)))
  end

  # Build custom SQL `where`
  # beware of SQL injections!
  #
  # ```
  # where("ADD_SOME_DANGEROUS_SQL_HERE") # WHERE ADD_SOME_DANGEROUS_SQL_HERE
  # ```
  def where(template : String)
    @wheres << Clear::Expression::Node::Raw.new(template)
    change!
  end

  # Build SQL `or_where` condition using a Clear::Expression::Node
  #
  # ```
  # query.or_where(Clear::Expression::Node::InArray.new("id", ['1', '2', '3', '4']))
  # # Note: in this example, InArray node use unsafe strings
  # ```
  #
  # If useful for moving a where clause from a request to another one:
  #
  # ```
  # query1.or_where { a == b } # WHERE a = b
  # ```
  #
  # ```
  # query2.or_where(query1.wheres[0]) # WHERE a = b
  # ```
  def or_where(node : Clear::Expression::Node)
    return where(node) if @wheres.empty?

    # Optimisation: if we have a OR Array as root, we use it and append directly the element.
    if @wheres.size == 1 &&
       (n = @wheres.first) &&
       n.is_a?(Clear::Expression::Node::NodeArray) &&
       n.link == "OR"
      n.expression << node
    else
      # Concatenate the old clauses in a list of AND conditions
      if @wheres.size == 1
        old_clause = @wheres.first
      else
        old_clause = Clear::Expression::Node::NodeArray.new(@wheres, "AND")
      end

      @wheres.clear
      @wheres << Clear::Expression::Node::NodeArray.new([old_clause, node], "OR")
    end

    change!
  end

  def or_where(template : String, **tuple)
    or_where(Clear::Expression::Node::Raw.new(Clear::Expression.raw("(#{template})", **tuple)))
  end

  def or_where(template : String, *args)
    or_where(Clear::Expression::Node::Raw.new(Clear::Expression.raw("(#{template})", *args)))
  end

  # Build SQL `where` condition using the Expression engine.
  #
  # ```
  # query.or_where { id == 1 }
  # ```
  def or_where(&block)
    or_where(Clear::Expression.ensure_node!(with Clear::Expression.new yield))
  end

  # Clear all the where clauses and return `self`
  def clear_wheres
    @wheres.clear

    change!
  end

  # :nodoc:
  protected def print_wheres
    {"WHERE ", @wheres.join(" AND ", &.resolve)}.join unless @wheres.empty?
  end
end
