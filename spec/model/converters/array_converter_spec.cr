require "../../spec_helper"

module ArrayConverterSpec
  describe "Clear::Model::Converter::ArrayConverter" do
    describe "#to_column" do
      it "converts to array of strings" do
        converter = Clear::Model::Converter::ArrayConverterString
        converter.to_column(["1", "2", "3"]).should eq(["1", "2", "3"])
      end

      it "converts to array of integers" do
        converter = Clear::Model::Converter::ArrayConverterInt32
        converter.to_column([1, 2, 3]).should eq([1, 2, 3])
      end

      it "converts to array of booleand" do
        converter = Clear::Model::Converter::ArrayConverterBool
        converter.to_column([true, false]).should eq([true, false])
      end
    end

    describe "#to_string" do
      it "array of strings" do
        converter = Clear::Model::Converter::ArrayConverterString
        converter.to_string(["for", "bar", "baz"]).should eq("'for', 'bar', 'baz'")
      end
    end

    describe "#to_db" do
      it "converts" do
        converter = Clear::Model::Converter::ArrayConverterString

        exp = converter.to_db(["foo", "bar"])
        exp.should be_a(Clear::Expression::UnsafeSql)

        exp.try(&.to_sql).should eq("Array['foo', 'bar']::text[]")
      end
    end
  end
end
