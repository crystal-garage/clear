require "../../spec_helper"

module RangeConverterSpec
  describe "Lustra::Model::Converter Range Converters" do
    describe "RangeConverterInt32" do
      it "parses and serializes int ranges" do
        converter = Lustra::Model::Converter::RangeConverterInt32

        # parse textual range
        r = converter.to_column("[1,10)")
        r.should eq(1...10)

        # serialize Range -> PG textual
        serialized = converter.to_db(Range.new(1_i32, 10_i32, true))
        serialized.should eq("[1,10)")

        # empty -> nil
        converter.to_column("empty").should be_nil

        # unbounded lower bound
        r2 = converter.to_column("(,10]")
        r2.should eq(..10)
      end
    end

    describe "RangeConverterInt64" do
      it "parses and serializes big int ranges" do
        converter = Lustra::Model::Converter::RangeConverterInt64

        r = converter.to_column("[10000000000,20000000000)")
        r.should eq(10000000000...20000000000)

        serialized = converter.to_db(Range.new(10000000000, 20000000000, true))
        serialized.should eq("[10000000000,20000000000)")

        # endless upper bound
        r2 = converter.to_column("[1,)")
        r2.should eq(1...)
      end
    end

    describe "RangeConverterTime" do
      it "parses and serializes time ranges" do
        converter = Lustra::Model::Converter::RangeConverterTime

        txt = "[2020-01-01T00:00:00Z,2020-12-31T23:59:59Z]"
        r = converter.to_column(txt)
        start_t = Time.utc(2020, 1, 1)
        end_t = Time.utc(2020, 12, 31, 23, 59, 59)
        r.should eq(start_t..end_t)

        serialized = converter.to_db(Range.new(start_t, end_t, false))
        serialized.should eq("[2020-01-01T00:00:00.000000000Z,2020-12-31T23:59:59.000000000Z]")

        # unbounded both sides (both bounds empty)
        r2 = converter.to_column("(,)")
        r2.should eq(...)
      end
    end
  end
end
