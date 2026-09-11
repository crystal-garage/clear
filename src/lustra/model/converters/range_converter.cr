require "./base"

# Minimal PostgreSQL range parsing utilities tailored for Lustra converters.
# This supports basic numeric and time ranges in the form: "[1,10)", "(2020-01-01,2020-12-31]".
def string_to_range(str : String, &)
  return if str.empty? || str == "empty"

  match = str.match(/^([\[\(])\s*(.*?)\s*,\s*(.*?)\s*([\)\]])$/)
  unless match
    raise "Invalid range format: #{str}"
  end

  begin_incl = match[1] == "["
  begin_s = match[2]
  end_s = match[3]
  end_incl = match[4] == "]"

  begin_val = (begin_s == "" || begin_s == "") ? nil : yield(begin_s)
  end_val = (end_s == "" || end_s == "") ? nil : yield(end_s)

  # Crystal Range only supports an exclusive end flag; use right_exclusive accordingly.
  exclusive = !end_incl

  Range.new(begin_val, end_val, exclusive)
end

module Lustra::Model::Converter::RangeConverterInt32
  def self.to_column(x) : Range(Int32?, Int32?)?
    case x
    when Nil
      nil
    when PG::Range
      to_column(x.to_crystal_range)
    when Range
      b = x.begin.nil? ? nil : x.begin.to_s.to_i32
      e = x.end.nil? ? nil : x.end.to_s.to_i32

      Range.new(b, e, x.excludes_end?)
    when String
      string_to_range(x, &.to_i32)
    else
    end
  end

  def self.to_db(x)
    case x
    when Nil
      nil
    when Range
      Lustra::Model::Converter.format_numeric_range(x)
    else
    end
  end
end

module Lustra::Model::Converter::RangeConverterInt64
  def self.to_column(x) : Range(Int64?, Int64?)?
    case x
    when Nil
      nil
    when PG::Range
      to_column(x.to_crystal_range)
    when Range
      b = x.begin.nil? ? nil : x.begin.to_s.to_i64
      e = x.end.nil? ? nil : x.end.to_s.to_i64

      Range.new(b, e, x.excludes_end?)
    when String
      string_to_range(x, &.to_i64)
    else
    end
  end

  def self.to_db(x)
    case x
    when Nil
      nil
    when Range
      Lustra::Model::Converter.format_numeric_range(x)
    else
    end
  end
end

module Lustra::Model::Converter::RangeConverterPGNumeric
  def self.to_column(x) : Range(PG::Numeric?, PG::Numeric?)?
    case x
    when Nil
      nil
    when PG::Range
      to_column(x.to_crystal_range)
    when Range(PG::Numeric?, PG::Numeric?)
      x
    else
    end
  end

  def self.to_db(x)
    case x
    when Nil
      nil
    when Range
      Lustra::Model::Converter.format_numeric_range(x)
    else
    end
  end
end

module Lustra::Model::Converter::RangeConverterBigDecimal
  def self.to_column(x) : Range(BigDecimal?, BigDecimal?)?
    case x
    when Nil
      nil
    when PG::Range
      to_column(x.to_crystal_range)
    when Range(BigDecimal?, BigDecimal?)
      x
    when Range
      b = x.begin.nil? ? nil : BigDecimal.new(x.begin.to_s)
      e = x.end.nil? ? nil : BigDecimal.new(x.end.to_s)

      Range.new(b, e, x.excludes_end?)
    when String
      string_to_range(x) { |s| BigDecimal.new(s) }
    else
    end
  end

  def self.to_db(x)
    case x
    when Nil
      nil
    when Range
      Lustra::Model::Converter.format_numeric_range(x)
    else
    end
  end
end

module Lustra::Model::Converter::RangeConverterTime
  def self.to_column(x) : Range(Time?, Time?)?
    case x
    when Nil
      nil
    when PG::Range
      to_column(x.to_crystal_range)
    when Range
      b =
        if x.begin.nil?
          nil.as(Time?)
        else
          if x.begin.is_a?(Time)
            x.begin.as(Time)
          else
            Time::Format::RFC_3339.parse(x.begin.to_s)
          end
        end

      e =
        if x.end.nil?
          nil.as(Time?)
        else
          if x.end.is_a?(Time)
            x.end.as(Time)
          else
            Time::Format::RFC_3339.parse(x.end.to_s)
          end
        end

      Range.new(b, e, x.excludes_end?)
    when String
      r = string_to_range(x) do |s|
        # Try local parse for non-RFC formats, fall back to RFC_3339
        case s
        when /[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]+/
          Time.parse_local(s, "%F %X.%L")
        else
          Time::Format::RFC_3339.parse(s)
        end
      end
      r
    else
    end
  end

  def self.to_db(x)
    case x
    when Nil
      nil
    when Range
      Lustra::Model::Converter.format_timestamp_range(x)
    else
    end
  end
end

module Lustra::Model::Converter
  add_converter("Range(Int32 | Nil, Int32 | Nil)", Lustra::Model::Converter::RangeConverterInt32)
  add_converter("Range(Int64 | Nil, Int64 | Nil)", Lustra::Model::Converter::RangeConverterInt64)
  add_converter("Range(Time | Nil, Time | Nil)", Lustra::Model::Converter::RangeConverterTime)
  add_converter("Range(PG::Numeric | Nil, PG::Numeric | Nil)", Lustra::Model::Converter::RangeConverterPGNumeric)
  add_converter("Range(BigDecimal | Nil, BigDecimal | Nil)", Lustra::Model::Converter::RangeConverterBigDecimal)
end
