require "../spec_helper"
require "../data/example_models"

module CollectionSpec
  describe Clear::Model::CollectionBase do
    it "[] / []?" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        qry = User.query.order_by({first_name: :asc})

        qry[1].first_name.should eq("user 1")
        qry[3..5].map(&.first_name).should eq(["user 3", "user 4"])

        qry[2]?.not_nil!.first_name.should eq("user 2")
        qry[10]?.should be_nil

        expect_raises(Clear::SQL::RecordNotFoundError) {
          qry[11]
        }
      end
    end

    it "find / find!" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        User.query.find { first_name == "user 2" }.not_nil!.first_name.should eq("user 2")
        User.query.find { first_name == "not_exists" }.should be_nil

        expect_raises(Clear::SQL::RecordNotFoundError) {
          User.query.find! { first_name == "not_exists" }
        }
      end
    end

    it "delete_all" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        User.query.count.should eq(10)
        User.query.where { id <= 5 }.delete_all
        User.query.count.should eq(5)
      end
    end
  end
end
