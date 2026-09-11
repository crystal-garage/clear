require "pg"
require "json"

module Lustra::Model::Converter
  abstract class Base
  end

  CONVERTERS = {} of String => Base.class

  macro add_converter(name, klass)
    {% CONVERTERS[name] = klass %}
  end

  macro to_column(name, value)
    {% if !name.is_a?(StringLiteral) %}
      {% name = "#{name}" %}
    {% end %}

    {% if CONVERTERS[name] == nil %}
      {% raise "Unknown converter: #{name}" %}
    {% end %}

    {{ CONVERTERS[name] }}.to_column({{ value }})
  end

  macro to_db(name, value)
    {% if !name.is_a?(StringLiteral) %}
      {% name = "#{name.resolve}" %}
    {% end %}

    {% if CONVERTERS[name] == nil %}
      {% raise "Unknown converter: #{name}" %}
    {% end %}

    {{ CONVERTERS[name] }}.to_db({{ value }})
  end

  def self.format_time(value : Time)
    Time::Format::RFC_3339.format(value, fraction_digits: 9)
  end

  def self.format_numeric_range(range)
    # PQ::Params.format_numeric_range(range)
    if range.begin == range.end && range.excludes_end?
      "empty"
    else
      start_bracket = "["
      end_bracket = range.excludes_end? ? ")" : "]"

      begin_str = range.begin.nil? ? "" : range.begin.to_s
      end_str = range.end.nil? ? "" : range.end.to_s

      "#{start_bracket}#{begin_str},#{end_str}#{end_bracket}"
    end
  end

  def self.format_timestamp_range(range)
    if range.begin == range.end && range.excludes_end?
      "empty"
    else
      start_bracket = "["
      end_bracket = range.excludes_end? ? ")" : "]"

      begin_str = range.begin.try { |val| format_time(val) } || ""
      end_str = range.end.try { |val| format_time(val) } || ""

      "#{start_bracket}#{begin_str},#{end_str}#{end_bracket}"
    end
  end
end
