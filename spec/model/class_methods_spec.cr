require "../spec_helper"
require "../data/example_models"

describe Clear::Model::ClassMethods do
  context "#build" do
    it "can build empty model" do
      temporary do
        reinit_example_models

        user = User.build # first_name: must be present

        user.persisted?.should be_false
        user.valid?.should be_false
      end
    end

    it "can build with arguments" do
      temporary do
        reinit_example_models

        user = User.build(first_name: "name")

        user.persisted?.should be_false
        user.valid?.should be_true
      end
    end

    it "can build with block" do
      temporary do
        reinit_example_models

        user = User.build(first_name: "John") do |u|
          u.last_name = "Doe"
        end

        user.persisted?.should be_false
        user.valid?.should be_true
        user.full_name.should eq("John Doe")
      end
    end
  end

  context "#create!" do
    it "can create with parameters" do
      temporary do
        reinit_example_models

        user = User.create!(first_name: "John", last_name: "Doe")

        user.persisted?.should be_true
        User.query.count.should eq(1)
        User.query.first!.full_name.should eq("John Doe")
      end
    end

    it "can create with NamedTuple" do
      temporary do
        reinit_example_models

        user = User.create!({first_name: "John", last_name: "Doe"})

        user.persisted?.should be_true
        User.query.count.should eq(1)
        User.query.first!.full_name.should eq("John Doe")
      end
    end

    it "can create from relation with block" do
      temporary do
        reinit_example_models

        user1 = User.create!({first_name: "John"}) do |u|
          u.last_name = "Doe"
        end

        user2 = User.create!(first_name: "Jane") do |u|
          u.last_name = "Doe"
        end

        User.query.count.should eq(2)

        user1.full_name.should eq("John Doe")
        user2.full_name.should eq("Jane Doe")
      end
    end
  end

  context "#create" do
    it "can create with parameters" do
      temporary do
        reinit_example_models

        user = User.create(first_name: "John", last_name: "Doe")

        user.persisted?.should be_true
        User.query.count.should eq(1)
        User.query.first!.full_name.should eq("John Doe")
      end
    end

    it "can create with NamedTuple" do
      temporary do
        reinit_example_models

        user = User.create({first_name: "John", last_name: "Doe"})

        user.persisted?.should be_true
        User.query.count.should eq(1)
        User.query.first!.full_name.should eq("John Doe")
      end
    end

    it "can create from relation with block" do
      temporary do
        reinit_example_models

        user1 = User.create({first_name: "John"}) do |u|
          u.last_name = "Doe"
        end

        user2 = User.create(first_name: "Jane") do |u|
          u.last_name = "Doe"
        end

        User.query.count.should eq(2)

        user1.full_name.should eq("John Doe")
        user2.full_name.should eq("Jane Doe")
      end
    end
  end
end
