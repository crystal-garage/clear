# `Clear::Interval` represents the "interval" object of PostgreSQL

# It can be converted automatically from/to a `interval` column.
#
# ## Usage example
#
# ```
# class MyModel
#   include Clear::Model
#
#   column interval : Clear::TimeInDay
# end
#
# interval = Clear::Interval.new(60.days)
# record = MyModel.create!(interval: interval)
# ```
struct Clear::Interval
  getter months : Int32 = 0
  getter days : Int32 = 0
  getter microseconds : Int64 = 0

  getter hours : Int32 = 0
  getter minutes : Int32 = 0
  getter seconds : Int32 = 0
  getter milliseconds : Int32 = 0

  def initialize(span : Time::Span)
    @days = (span.days || 0).to_i32
    @hours = span.hours || 0
    @minutes = span.minutes || 0
    @seconds = span.seconds || 0
    @milliseconds = span.milliseconds || 0
    @microseconds = (span.microseconds || 0).to_i64
  end

  def initialize(span : Time::MonthSpan)
    @months = span.value.to_i32
  end

  # For `PG::Interval`
  def initialize(
    @months : Int32,
    @days : Int32,
    microseconds : Number
  )
    @microseconds = (
      microseconds.to_i64 +
      milliseconds * 1_000_i64 +
      seconds * 1_000_000_i64 +
      minutes * 60_000_000_i64 +
      hours * 3_600_000_000_i64
    )
  end

  def initialize(
    @months : Int32 = 0,
    @days : Int32 = 0,
    @hours : Int32 = 0,
    @minutes : Int32 = 0,
    @seconds : Int32 = 0,
    @milliseconds : Int32 = 0,
    @microseconds : Int64 = 0
  )
  end

  def initialize(io : IO)
    @microseconds = io.read_bytes(Int64, IO::ByteFormat::BigEndian)
    @days = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    @months = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
  end

  def to_s(io)
    ""
  end

  def to_json(json : JSON::Builder) : Nil
    json.string(to_s)
  end

  def to_sql
    o = [] of String

    (o << @months.to_s << "months") unless @months.zero?
    (o << @days.to_s << "days") unless @days.zero?
    (o << @hours.to_s << "hours") unless @hours.zero?
    (o << @minutes.to_s << "minutes") unless @minutes.zero?
    (o << @seconds.to_s << "seconds") unless @seconds.zero?
    (o << @milliseconds.to_s << "milliseconds") unless @milliseconds.zero?
    (o << @microseconds.to_s << "microseconds") unless @microseconds.zero?

    Clear::SQL.unsafe({
      "INTERVAL",
      Clear::Expression[o.join(" ")],
    }.join(" "))
  end

  def +(i : self)
    self.new(
      months: self.months + i.months,
      day: self.days + i.days,
      hours: self.hours + i.hours,
      minutes: self.minutes + i.minutes,
      seconds: self.seconds + i.seconds,
      milliseconds: self.milliseconds + i.milliseconds,
      microseconds: self.microseconds + i.microseconds
    )
  end

  def self.decode(x : Slice(UInt8))
    io = IO::Memory.new(x, writeable: false)

    self.new(io)
  end
end
