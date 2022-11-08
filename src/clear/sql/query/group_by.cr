module Clear::SQL::Query::GroupBy
  getter group_bys : Array(Symbolic)

  def clear_group_bys
    @group_bys.clear
    change!
  end

  def group_by(column : Symbolic)
    @group_bys << column
    change!
  end

  protected def print_group_bys
    return if @group_bys.empty?

    "GROUP BY " + @group_bys.join(", ") { |x| x.is_a?(Symbol) ? SQL.escape(x) : x }
  end
end
