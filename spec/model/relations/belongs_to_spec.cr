require "../../spec_helper"
require "../../data/example_models"

module BelongsToSpec
  describe("belongs_to relation (not nilable)") do
    it "can access" do
      temporary do
        reinit_example_models

        user = User.create!(first_name: "name")
        post = Post.create!(user: user, title: "title")

        post.user.id.should eq(user.id)
        user.posts.count.should eq(1)
      end
    end

    it "throw error if not found" do
      temporary do
        reinit_example_models

        expect_raises(Exception) do
          Post.create!(user_id: nil) # Bad id
        end
      end
    end

    it "saves model before saving itself if associated model is not persisted" do
      temporary do
        reinit_example_models

        user = User.new({first_name: "name"})
        post = Post.new({user: user, title: "title"})

        post.save!
        post.persisted?.should be_true
        user.persisted?.should be_true
      end
    end

    it "fails to save if the associated model is incorrect" do
      temporary do
        reinit_example_models

        user = User.new
        post = Post.new({user: user, title: "title"})

        post.save.should be_false
        post.errors.size.should eq(1)
        post.errors[0].reason.should eq("first_name: must be present")

        # error correction
        user.first_name = "name"
        post.save.should be_true
      end
    end

    it "can avoid n+1 queries" do
      temporary do
        reinit_example_models

        users = {
          User.create!(first_name: "name"),
          User.create!(first_name: "name"),
        }

        5.times do |x|
          Post.create!(user: users.sample, title: "title")
        end

        post_call = 0
        user_call = 0

        post_query = Post.query.before_query { post_call += 1 }
        post_query.with_user { user_call += 1 }

        post_query.each do |post|
          post_call.should eq(1)
          user_call.should eq(1)

          post.user
        end
      end
    end
  end
end
