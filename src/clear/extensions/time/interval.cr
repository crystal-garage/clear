struct Time
  def +(i : Clear::Interval)
    self + i.months.months + i.days.days + i.microseconds.microseconds
  end

  def -(i : Clear::Interval)
    self - i.months.months - i.days.days - i.microseconds.microseconds
  end
end

class Clear::Interval::Converter
  def self.to_column(x) : Clear::Interval?
    case x
    when PG::Interval
      Clear::Interval.new(months: x.months, days: x.days, microseconds: x.microseconds)
    when Slice # < Here bug of the crystal compiler with Slice(UInt8), do not want to compile
      Clear::Interval.decode(x.as(Slice(UInt8)))
    when Clear::Interval
      x
    when Nil
      nil
    else
      raise Clear::ErrorMessages.converter_error(x.class, "Interval")
    end
  end

  def self.to_db(x : Clear::Interval?)
    x.try &.to_sql
  end
end

Clear::Model::Converter.add_converter("Clear::Interval", Clear::Interval::Converter)
