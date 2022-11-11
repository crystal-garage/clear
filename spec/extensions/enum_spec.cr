require "../spec_helper"
require "../data/example_models"

module EnumSpec
  describe "Clear.enum" do
    it "call custom member methods" do
      GenderType::Male.male?.should eq true
      GenderType::Female.male?.should eq false
      GenderType::Other.female?.should eq false
    end

    it "create and use enum" do
      temporary do
        reinit_example_models

        User.create!({first_name: "John", gender: GenderType::Male})
        User.create!({first_name: "Jane", gender: GenderType::Female})

        User.query.first!.gender.should eq GenderType::Male
        User.query.offset(1).first!.gender.should eq GenderType::Female

        User.query.first!.gender.should eq "male"
        User.query.offset(1).first!.gender.should eq "female"

        User.query.where { gender == GenderType::Female }.count.should eq 1
        User.query.where { gender == "male" }.count.should eq 1
        User.query.where { gender.in? GenderType.all }.count.should eq 2
      end
    end

    it "create and use enum with query" do
      temporary do
        reinit_example_models

        User.query.create!(first_name: "John", gender: GenderType::Male)
        User.query.create!(first_name: "Jane", gender: GenderType::Female)

        User.query.first!.gender.should eq GenderType::Male
        User.query.offset(1).first!.gender.should eq GenderType::Female

        User.query.first!.gender.should eq "male"
        User.query.offset(1).first!.gender.should eq "female"

        User.query.where { gender == GenderType::Female }.count.should eq 1
        User.query.where { gender == "male" }.count.should eq 1
        User.query.where { gender.in? GenderType.all }.count.should eq 2
      end
    end

    it "export to json" do
      temporary do
        reinit_example_models

        User.create!({first_name: "John", gender: GenderType::Male})
        u = User.query.first!
        u.to_json.should contain %<,"gender":"male",>
      end
    end
  end
end
