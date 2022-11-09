require "../spec_helper"
require "../data/example_models"

module CollectionSpec
  describe Clear::Model::CollectionBase do
    describe "#build" do
      it "can build from relation" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.build(title: "title")

          post.persisted?.should be_false
          post.valid?.should be_true
        end
      end

      it "can build from relation without params" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.build

          post.persisted?.should be_false
          post.valid?.should be_false
        end
      end

      it "can build from relation with block" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.build(&.title=("title"))

          post.persisted?.should be_false
          post.valid?.should be_true
        end
      end
    end

    describe "#create" do
      it "can create from relation" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.create(title: "title")

          post.persisted?.should be_true
          post.user.id.should eq(user.id)
          user.posts.count.should eq(1)
        end
      end

      it "can create from relation with block" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.create(&.title=("title"))

          post.persisted?.should be_true
          post.user.id.should eq(user.id)
          user.posts.count.should eq(1)
        end
      end

      it "return self if validation failed" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.create(title: "")

          post.valid?.should be_false
          post.errors.size.should eq(1)
          post.errors[0].reason.should eq("title: is empty")
        end
      end
    end

    describe "#create!" do
      it "can create from relation" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.create!(title: "title")

          post.user.id.should eq(user.id)
          user.posts.count.should eq(1)
        end
      end

      it "can create from relation with block" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          post = user.posts.create!(&.title=("title"))

          post.user.id.should eq(user.id)
          user.posts.count.should eq(1)
        end
      end

      it "raise exception if validation failed" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "name")

          expect_raises(Clear::Model::InvalidError) do
            post = user.posts.create!(title: "")
          end
        end
      end
    end

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

        User.query.find! { first_name == "user 2" }.first_name.should eq("user 2")
        User.query.find { first_name == "not_exists" }.should be_nil

        expect_raises(Clear::SQL::RecordNotFoundError) {
          User.query.find! { first_name == "not_exists" }
        }
      end
    end

    it "find / find! with join" do
      temporary do
        reinit_example_models

        user = User.create! first_name: "user"

        post1 = Post.create! title: "title 1", user_id: user.id
        post2 = Post.create! title: "title 2", user_id: user.id

        if post = Post
             .query
             .join("users") { users.id == posts.user_id }
             .find {
               (users.first_name == "user") &
                 (posts.title == "title 2")
             }
          (post.id).should eq(post2.id)
        end
      end
    end

    it "first_or_create" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        # already existing stuff
        User.query.where(first_name: "user 1").count.should eq(1)
        rec = User.query.find_or_create(first_name: "user 1") do
          raise "Should not initialize the model"
        end

        rec.persisted?.should be_true
        User.query.where(first_name: "user 1").count.should eq(1)

        User.query.where(first_name: "not_exist").count.should eq(0)
        rec = User.query.find_or_create(first_name: "not_exist") do |usr|
          usr.last_name = "now_it_exists"
        end
        rec.persisted?.should be_true
        User.query.where(last_name: "now_it_exists").count.should eq(1)

        # with @tags metadata of the collection it should infer the where clause
        usr = User.query.where(first_name: "Sarah", last_name: "Connor").find_or_create
        usr.persisted?.should be_true
        usr.first_name.should eq("Sarah")
        usr.last_name.should eq("Connor")
      end
    end

    it "first_or_build" do
      # same test than first_or_create, persistance check changing.
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        # already existing stuff
        User.query.where(first_name: "user 1").count.should eq(1)
        rec = User.query.find_or_build(first_name: "user 1") do
          raise "Should not initialize the model"
        end

        rec.persisted?.should be_true
        User.query.where(first_name: "user 1").count.should eq(1)

        # with @tags metadata of the collection it should infer the where clause
        usr = User.query.where(first_name: "Sarah", last_name: "Connor").find_or_build
        usr.persisted?.should be_false
        usr.first_name.should eq("Sarah")
        usr.last_name.should eq("Connor")
      end
    end

    it "first / first!" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        User.query.first!.first_name.should eq("user 0")
        User.query.order_by({id: :desc}).first!.first_name.should eq("user 9")

        Clear::SQL.truncate("users", cascade: true)

        expect_raises(Clear::SQL::RecordNotFoundError) do
          User.query.first!
        end

        User.query.first.should be_nil
      end
    end

    it "last / last!" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        User.query.last!.first_name.should eq("user 9")
        User.query.order_by({id: :desc}).last!.first_name.should eq("user 0")

        Clear::SQL.truncate(User, cascade: true)

        expect_raises(Clear::SQL::RecordNotFoundError) do
          User.query.last!
        end

        User.query.last.should be_nil
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
