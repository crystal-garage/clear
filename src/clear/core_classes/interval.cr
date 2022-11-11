# Represents the "interval" object of PostgreSQL
struct Clear::Interval
  getter microseconds : Int64 = 0
  getter days : Int32 = 0
  getter months : Int32 = 0

  def initialize(span : Time::Span)
    @microseconds = span.total_nanoseconds.to_i64 // 1_000
  end

  def initialize(span : Time::MonthSpan)
    @months = span.value.to_i32
  end

  def initialize(
    years : Number = 0,
    months : Number = 0,
    weeks : Number = 0,
    days : Number = 0,
    hours : Number = 0,
    minutes : Number = 0,
    seconds : Number = 0,
    milliseconds : Number = 0,
    microseconds : Number = 0
  )
    @months = (12 * years + months).to_i32
    @days = days.to_i32
    @microseconds = (
      microseconds.to_i64 +
      milliseconds * 1_000_i64 +
      seconds * 1_000_000_i64 +
      minutes * 60_000_000_i64 +
      hours * 3_600_000_000_i64
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

    (o << @months.to_s << "months") if @months != 0
    (o << @days.to_s << "days") if @days != 0
    (o << @microseconds.to_s << "microseconds") if @microseconds != 0

    Clear::SQL.unsafe({
      "INTERVAL",
      Clear::Expression[o.join(" ")],
    }.join(" "))
  end

  def +(i : self)
    self.new(months: self.months + i.months, day: self.days + i.days, microseconds: self.microseconds + i.microseconds)
  end

  def self.decode(x : Slice(UInt8))
    io = IO::Memory.new(x, writeable: false)

    self.new(io)
  end
end
