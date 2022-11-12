struct Time
  def +(interval : Clear::Interval)
    [
      interval.months.months,
      interval.days.days,
      interval.hours.hours,
      interval.minutes.minutes,
      interval.seconds.seconds,
      interval.milliseconds.milliseconds,
      interval.microseconds.microseconds,
    ].reduce(self) { |acc, e| acc + e }
  end

  def -(interval : Clear::Interval)
    [
      interval.months.months,
      interval.days.days,
      interval.hours.hours,
      interval.minutes.minutes,
      interval.seconds.seconds,
      interval.milliseconds.milliseconds,
      interval.microseconds.microseconds,
    ].reduce(self) { |acc, e| acc - e }
  end
end

class Clear::Interval::Converter
  def self.to_column(x) : Clear::Interval?
    case x
    when PG::Interval
      Clear::Interval.new(x.months, x.days, x.microseconds)
    when Slice(UInt8)
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
