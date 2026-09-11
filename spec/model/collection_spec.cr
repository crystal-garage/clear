require "../spec_helper"
require "../data/example_models"

module CollectionSpec
  describe Lustra::Model::CollectionBase do
    describe "#dup on associations" do
      it "preserves the parent foreign key when building through a duplicate" do
        temporary do
          reinit_example_models
          user = User.create!(first_name: "John")

          post = user.posts.dup.build(title: "Draft")

          post.user_id_column.defined?.should be_true
          post.user_id.should eq(user.id)
        end
      end

      it "preserves autosave when building through a duplicate" do
        temporary do
          reinit_example_models
          user = User.create!(first_name: "John")
          post = user.posts.dup.build(title: "Draft", user_id: user.id)

          user.save!

          post.persisted?.should be_true
          user.posts.count.should eq(1)
        end
      end

      it "preserves append behavior on a duplicated association" do
        temporary do
          reinit_example_models
          original_owner = User.create!(first_name: "John")
          new_owner = User.create!(first_name: "Jane")
          post = Post.create!(title: "Post", user_id: original_owner.id)

          new_owner.posts.dup << post

          post.reload.user_id.should eq(new_owner.id)
        end
      end

      it "preserves unlink behavior on a duplicated through association" do
        temporary do
          reinit_example_models
          user = User.create!(first_name: "John")
          post = Post.create!(title: "Post", user_id: user.id)
          tag = Tag.create!(name: "Crystal")
          post.tags << tag

          post.tags.dup.unlink(tag)

          post.tags.count.should eq(0)
          Tag.query.where(id: tag.id).count.should eq(1)
        end
      end
    end

    describe "with query" do
      context "#build" do
        it "build empty model" do
          temporary do
            reinit_example_models

            user = User.query.build # first_name: must be present

            user.persisted?.should be_false
            user.valid?.should be_false

            user.first_name = "John"
            user.valid?.should be_true
          end
        end

        it "build with arguments" do
          temporary do
            reinit_example_models

            user = User.query.build(first_name: "name")

            user.persisted?.should be_false
            user.valid?.should be_true
          end
        end

        it "build with NamedTuple" do
          temporary do
            reinit_example_models

            user = User.query.build({first_name: "name"})

            user.persisted?.should be_false
            user.valid?.should be_true
          end
        end

        it "build with block" do
          temporary do
            reinit_example_models

            user1 = User.query.build(first_name: "John") do |u|
              u.last_name = "Doe"
            end

            user2 = User.query.build({first_name: "Jane"}) do |u|
              u.last_name = "Doe"
            end

            user3 = User.query.build do |u|
              u.first_name = "Baby"
              u.last_name = "Doe"
            end

            user1.persisted?.should be_false
            user1.valid?.should be_true
            user1.full_name.should eq("John Doe")

            user2.persisted?.should be_false
            user2.valid?.should be_true
            user2.full_name.should eq("Jane Doe")

            user3.persisted?.should be_false
            user3.valid?.should be_true
            user3.full_name.should eq("Baby Doe")
          end
        end
      end

      context "#create!" do
        it "create with parameters" do
          temporary do
            reinit_example_models

            user = User.query.create!(first_name: "John", last_name: "Doe")

            user.persisted?.should be_true
            User.query.count.should eq(1)
            User.query.first!.full_name.should eq("John Doe")
          end
        end

        it "create with NamedTuple" do
          temporary do
            reinit_example_models

            user = User.query.create!({first_name: "John", last_name: "Doe"})

            user.persisted?.should be_true
            User.query.count.should eq(1)
            User.query.first!.full_name.should eq("John Doe")
          end
        end

        it "creates with a JSON-serializable value" do
          temporary do
            reinit_example_models
            preferences = {"topics" => ["crystal", "postgresql"]}

            user = User.query
              .where(first_name: "John")
              .create!(notification_preferences: preferences)

            persisted_user = User.find!(user.id)
            persisted_user.first_name.should eq("John")
            persisted_user.notification_preferences.should eq(JSON.parse(preferences.to_json))
          end
        end

        it "raises for an invalid NamedTuple" do
          temporary do
            reinit_example_models

            expect_raises(Lustra::Model::InvalidError) do
              Post.query.create!({title: ""})
            end
          end
        end

        it "raises for an invalid NamedTuple with a block" do
          temporary do
            reinit_example_models

            expect_raises(Lustra::Model::InvalidError) do
              Post.query.create!({title: "valid"}) do |post|
                post.title = ""
              end
            end
          end
        end

        it "create with block" do
          temporary do
            reinit_example_models

            user1 = User.query.create!({first_name: "John"}) do |u|
              u.last_name = "Doe"
            end

            user2 = User.query.create!(first_name: "Jane") do |u|
              u.last_name = "Doe"
            end

            user3 = User.query.create! do |u|
              u.first_name = "Baby"
              u.last_name = "Doe"
            end

            User.query.count.should eq(3)

            user1.full_name.should eq("John Doe")
            user2.full_name.should eq("Jane Doe")
            user3.full_name.should eq("Baby Doe")
          end
        end
      end

      context "#create" do
        it "create with parameters" do
          temporary do
            reinit_example_models

            user = User.query.create(first_name: "John", last_name: "Doe")

            user.persisted?.should be_true
            User.query.count.should eq(1)
            User.query.first!.full_name.should eq("John Doe")
          end
        end

        it "create with NamedTuple" do
          temporary do
            reinit_example_models

            user = User.create({first_name: "John", last_name: "Doe"})

            user.persisted?.should be_true
            User.query.count.should eq(1)
            User.query.first!.full_name.should eq("John Doe")
          end
        end

        it "create from relation with block" do
          temporary do
            reinit_example_models

            user1 = User.query.create({first_name: "John"}) do |u|
              u.last_name = "Doe"
            end

            user2 = User.query.create(first_name: "Jane") do |u|
              u.last_name = "Doe"
            end

            User.query.count.should eq(2)

            user1.full_name.should eq("John Doe")
            user2.full_name.should eq("Jane Doe")
          end
        end
      end

      context "#find_or_build" do
        it "create with block" do
          temporary do
            reinit_example_models

            User.query.create(first_name: "Johnny", last_name: "Doe")

            user1 = User.query.find_or_build({first_name: "John"}) do |u|
              u.last_name = "Doe"
            end

            user2 = User.query.find_or_build(first_name: "Jane") do |u|
              u.last_name = "Doe"
            end

            user3 = User.query.find_or_build do |u|
              u.first_name = "Baby"
              u.last_name = "Doe"
            end

            user4 = User.query.find_or_build({first_name: "Johnny"}) do |u|
              u.last_name = "Roe"
            end

            User.query.count.should eq(1)

            user1.full_name.should eq("John Doe")
            user2.full_name.should eq("Jane Doe")
            user3.full_name.should eq("Johnny Doe")
            user4.full_name.should eq("Johnny Doe")
          end
        end
      end

      context "#find_or_create" do
        it "create with block" do
          temporary do
            reinit_example_models

            existing_user = User.query.create(first_name: "Johnny", last_name: "Doe")

            user1 = User.query.find_or_create({first_name: "John"}) do |u|
              u.last_name = "Doe"
            end

            user2 = User.query.find_or_create(first_name: "Jane") do |u|
              u.last_name = "Doe"
            end

            user3 = User.query.find_or_create do |u|
              u.first_name = "Baby"
              u.last_name = "Doe"
            end

            user4 = User.query.find_or_create({first_name: "Johnny"}) do |u|
              u.last_name = "Roe"
            end

            User.query.count.should eq(3)

            user1.full_name.should eq("John Doe")
            user2.full_name.should eq("Jane Doe")
            user3.id.should eq(existing_user.id)
            user4.id.should eq(existing_user.id)
          end
        end
      end
    end

    describe "with relation" do
      describe "#build" do
        it "build from relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.build(title: "title")

            post.persisted?.should be_false
            post.valid?.should be_true
          end
        end

        it "build from relation without params" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.build

            post.persisted?.should be_false
            post.valid?.should be_false
          end
        end

        it "build from relation with block" do
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
        it "create from relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.create(title: "title")

            post.persisted?.should be_true
            post.user.id.should eq(user.id)
            user.posts.count.should eq(1)
          end
        end

        it "create from relation with NameTuple" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.create({title: "title"})

            post.persisted?.should be_true
            post.user.id.should eq(user.id)
            user.posts.count.should eq(1)
          end
        end

        it "create from relation with block" do
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

      describe "#create / #create!" do
        it "create! from has_many relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.create!(title: "title")

            post.user.id.should eq(user.id)
            user.posts.count.should eq(1)
          end
        end

        it "saves once when creating through a has_many relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")
            save_calls = 0
            callback = ->(_model : Lustra::Model) { save_calls += 1 }
            callback_key = {Post.to_s, :before, :save}
            Lustra::Model::EventManager.attach(Post, :before, :save, callback)

            begin
              user.posts.create!(title: "title")
              save_calls.should eq(1)
            ensure
              Lustra::Model::EventManager::EVENT_CALLBACKS[callback_key].delete(callback)
            end
          end
        end

        it "saves once with non-bang create through a has_many relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")
            save_calls = 0
            callback = ->(_model : Lustra::Model) { save_calls += 1 }
            callback_key = {Post.to_s, :before, :save}
            Lustra::Model::EventManager.attach(Post, :before, :save, callback)

            begin
              user.posts.create(title: "title").persisted?.should be_true
              save_calls.should eq(1)
            ensure
              Lustra::Model::EventManager::EVENT_CALLBACKS[callback_key].delete(callback)
            end
          end
        end

        it "adds the created model to a cached has_many collection" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")
            posts = user.posts.with_cached_result([] of Post)

            post = posts.create!(title: "title")

            posts.to_a.should eq([post])
          end
        end

        it "create! from has_many relation with block" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post = user.posts.create!(&.title=("title"))

            post.user.id.should eq(user.id)
            user.posts.count.should eq(1)
          end
        end

        it "create! raises exception if validation failed" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            expect_raises(Lustra::Model::InvalidError) do
              user.posts.create!(title: "")
            end
          end
        end

        it "create! for has_many through" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)

            tag = post.tags.create!(name: "Tag1")

            Tag.query.count.should eq(1)
            PostTag.query.count.should eq(1)

            post.tags.count.should eq(1)
            post.tags.first!.name.should eq("Tag1")
          end
        end

        it "create for has_many through" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)

            tag = post.tags.create(name: "Tag1")

            Tag.query.count.should eq(1)
            PostTag.query.count.should eq(1)

            post.tags.count.should eq(1)
            post.tags.first!.name.should eq("Tag1")
          end
        end

        it "raise exception if validation failed" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            expect_raises(Lustra::Model::InvalidError) do
              user.posts.create!(title: "")
            end
          end
        end
      end

      describe "#find_or_create" do
        it "from has_many relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")

            post1 = user.posts.create!(title: "title1")
            user.posts.where(title: "title1").find_or_create

            user.posts.where(title: "title2").find_or_create
            user.posts.find_or_create(title: "title3")

            post1.user.id.should eq(user.id)
            user.posts.count.should eq(3)
          end
        end

        it "does not append a record found through a has_many relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "name")
            user.posts.create!(title: "existing")

            save_calls = 0
            callback = ->(_model : Lustra::Model) { save_calls += 1 }
            callback_key = {Post.to_s, :before, :save}
            Lustra::Model::EventManager.attach(Post, :before, :save, callback)

            begin
              user.posts.find_or_create(title: "existing")
              save_calls.should eq(0)
            ensure
              Lustra::Model::EventManager::EVENT_CALLBACKS[callback_key].delete(callback)
            end
          end
        end

        it "from has_many through relation" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)

            tag = post.tags.find_or_create(name: "Tag1")

            post.tags.count.should eq(1)
            Tag.query.count.should eq(1)
            PostTag.query.count.should eq(1)
          end
        end
      end

      describe "#<< operator" do
        it "works with has_many association (user.posts << post)" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.new({title: "Test Post"})

            user.posts << post

            post.persisted?.should be_true
            post.user_id.should eq(user.id)
            user.posts.count.should eq(1)
          end
        end

        it "moves a persisted model to a has_many association" do
          temporary do
            reinit_example_models

            first_user = User.create!(first_name: "John")
            second_user = User.create!(first_name: "Jane")
            post = Post.create!(title: "Test Post", user: first_user)

            second_user.posts << post

            post.reload.user_id.should eq(second_user.id)
            first_user.posts.count.should eq(0)
            second_user.posts.count.should eq(1)
          end
        end

        it "works with has_many through association (post.tags << tag)" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)
            tag = Tag.create!(name: "Tag1")

            post.tags << tag

            Tag.query.count.should eq(1)
            PostTag.query.count.should eq(1)

            post.tags.count.should eq(1)
            post.tags.first!.name.should eq("Tag1")
          end
        end

        it "prevents duplicate associations in has_many through" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)
            tag = Tag.create!(name: "Tag1")

            post.tags << tag
            post.tags << tag # Add same tag again

            Tag.query.count.should eq(1)
            PostTag.query.count.should eq(1) # No duplicates!
          end
        end

        it "raises helpful error on plain query collection" do
          temporary do
            reinit_example_models

            expect_raises(Exception, /Cannot append Post.*plain Post\.query result.*user\.posts/) do
              Post.query << Post.new({title: "Test Post"})
            end
          end
        end
      end

      describe "#unlink" do
        it "raises helpful error on plain query collection" do
          temporary do
            reinit_example_models

            expect_raises(Exception, /Cannot unlink Tag.*has_many through.*plain Tag\.query result/) do
              Tag.query.unlink(Tag.new({name: "Tag1"}))
            end
          end
        end
      end

      context "autosave functionality" do
        it "build + save! for has_many with autosave: true" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")

            # Build posts with autosave (User.posts has autosave: true)
            post1 = user.posts.build(title: "Post 1")
            post2 = user.posts.build(title: "Post 2")

            # Save parent with all built posts
            user.save!

            Post.query.count.should eq(2)
            user.posts.count.should eq(2)

            post1.persisted?.should be_true
            post1.user_id.should eq(user.id)
            post2.persisted?.should be_true
            post2.user_id.should eq(user.id)
          end
        end

        it "build + save! for has_many through with autosave: true" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")
            post = Post.create!(title: "Title", user: user)

            # Build associations (Post.tags has autosave: true)
            tag1 = post.tags.build(name: "Tag1")
            tag2 = post.tags.build(name: "Tag2")

            # Save parent with all built associations
            post.save!

            Tag.query.count.should eq(2)
            PostTag.query.count.should eq(2)

            post.tags.count.should eq(2)
            post.tags.map(&.name).should contain("Tag1")
            post.tags.map(&.name).should contain("Tag2")
          end
        end

        it "does NOT autosave when autosave: false (default)" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John")

            # Build comments without autosave (User.comments has no autosave)
            comment1 = user.comments.build(content: "Comment 1")
            comment2 = user.comments.build(content: "Comment 2")

            # Save parent - should NOT save built comments (autosave: false)
            user.save!

            Comment.query.count.should eq(0)
            user.comments.count.should eq(0)
          end
        end
      end
    end

    context "#where" do
      it "with find_or_create" do
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

      it "does not save a record found by find_or_create" do
        temporary do
          reinit_example_models
          User.create!(first_name: "existing")

          save_calls = 0
          callback = ->(_model : Lustra::Model) { save_calls += 1 }
          callback_key = {User.to_s, :before, :save}
          Lustra::Model::EventManager.attach(User, :before, :save, callback)

          begin
            User.query.find_or_create(first_name: "existing")
            save_calls.should eq(0)
          ensure
            Lustra::Model::EventManager::EVENT_CALLBACKS[callback_key].delete(callback)
          end
        end
      end

      it "with find_or_build" do
        # Same test as find_or_create, with the persistence check changed.
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

      it "find_or_build and find_or_create do not mutate the query" do
        temporary do
          reinit_example_models

          User.create!(first_name: "existing")

          users = User.query.order_by(id: :asc)
          sql = users.to_sql

          users.find_or_build(first_name: "existing").persisted?.should be_true
          users.to_sql.should eq(sql)
          users.tags.should be_empty

          users.find_or_build({first_name: "built"}).persisted?.should be_false
          users.to_sql.should eq(sql)
          users.tags.should be_empty

          users.find_or_create({first_name: "created"}).persisted?.should be_true
          users.to_sql.should eq(sql)
          users.tags.should be_empty
          users.map(&.first_name).should eq(["existing", "created"])
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
        sql = qry.to_sql

        qry[1].first_name.should eq("user 1")
        qry.to_sql.should eq(sql)

        qry[3..5].map(&.first_name).should eq(["user 3", "user 4"])
        qry.to_sql.should eq(sql)

        qry[2].first_name.should eq("user 2")
        qry.to_sql.should eq(sql)

        qry[10]?.should be_nil
        qry.to_sql.should eq(sql)

        expect_raises(Lustra::SQL::RecordNotFoundError) { qry[11] }
        qry.to_sql.should eq(sql)
        qry.map(&.first_name).should eq((0..9).map { |x| "user #{x}" })
      end
    end

    it "accessors restore the query while preserving eager-loading constraints" do
      temporary do
        reinit_example_models

        category = Category.create!(id: 1, name: "Category")
        users = Array.new(3) { |id| User.create!(id: id + 1, first_name: "User #{id + 1}") }
        users.each do |user|
          Post.create!(title: "Post #{user.id}", user_id: user.id, category_id: category.id)
        end

        eager_sql = nil
        query = User.query.with_posts do |posts|
          eager_sql = posts.to_sql
          posts.with_category
        end.order_by(id: :asc)
        sql = query.to_sql

        query[1].posts.first!.category.name.should eq("Category")
        eager_sql.not_nil!.should contain("LIMIT 1 OFFSET 1")
        query.to_sql.should eq(sql)

        eager_sql = nil
        query = User.query.with_posts do |posts|
          eager_sql = posts.to_sql
          posts.with_category
        end.order_by(id: :asc)
        sql = query.to_sql

        query[1..3].map(&.id).should eq([users[1].id, users[2].id])
        eager_sql.not_nil!.should contain("LIMIT 2 OFFSET 1")
        query.to_sql.should eq(sql)
      end
    end

    it "accessors restore the query after an eager-loading error" do
      temporary do
        reinit_example_models
        User.create!(first_name: "User")

        query = User.query.with_posts { raise "eager-loading error" }.offset(4).limit(5)
        sql = query.to_sql
        expect_raises(Exception, "eager-loading error") { query[0] }
        query.to_sql.should eq(sql)

        query = User.query.with_posts { raise "eager-loading error" }.offset(4).limit(5)
        sql = query.to_sql
        expect_raises(Exception, "eager-loading error") { query[0..1] }
        query.to_sql.should eq(sql)
      end
    end

    context "#none" do
      it "returns an empty chainable relation" do
        temporary do
          reinit_example_models

          User.create!(first_name: "John")

          none = User.query.none

          none.count.should eq(0)
          none.where { first_name == "John" }.count.should eq(0)
          none.first.should be_nil
        end
      end
    end

    context "find / find!" do
      it "with primary key" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"

          User.query.find!(user.id).first_name.should eq("user")
          User.query.find(999).should be_nil

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.find!(999)
          end
        end
      end

      it "with an array of primary keys" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1"
          user2 = User.create! first_name: "user2"

          users = User.query.find!([user1.id, user2.id])
          users.should be_a(Array(User))
          users.size.should eq(2)

          users = User.query.find([user1.id, user2.id, 999])
          users.size.should eq(2)

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.find!([user1.id, user2.id, 999])
          end
        end
      end

      it "does not mutate the query while eager loading associations" do
        temporary do
          reinit_example_models

          selected = User.create!(first_name: "Selected")
          other = User.create!(first_name: "Other")
          Post.create!(title: "Selected post", user_id: selected.id)
          Post.create!(title: "Other post", user_id: other.id)

          eager_sql = nil
          users = User.query.with_posts { |posts| eager_sql = posts.to_sql }.order_by(id: :asc)
          sql = users.to_sql

          found = users.find!([selected.id])
          found.size.should eq(1)
          found.first.posts.map(&.title).should eq(["Selected post"])
          eager_sql.not_nil!.should contain("id IN (#{selected.id})")
          users.to_sql.should eq(sql)
        end
      end
    end

    context "find_by / find_by!" do
      it "with block" do
        temporary do
          reinit_example_models

          10.times do |x|
            User.create! first_name: "user #{x}"
          end

          User.query.find_by! { first_name == "user 2" }.first_name.should eq("user 2")
          User.query.find_by { first_name == "not_exists" }.should be_nil

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.find_by! { first_name == "not_exists" }
          end
        end
      end

      it "with NamedTuple" do
        temporary do
          reinit_example_models

          10.times do |x|
            User.create! first_name: "user #{x}"
          end

          User.query.find_by!({first_name: "user 2"}).first_name.should eq("user 2")
          User.query.find_by({first_name: "not_exists"}).should be_nil

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.find_by!({first_name: "not_exists"})
          end
        end
      end

      it "with arguments" do
        temporary do
          reinit_example_models

          10.times do |x|
            User.create!(first_name: "first #{x}", last_name: "last #{x}")
          end

          User.query.find_by!(first_name: "first 2", last_name: "last 2").first_name.should eq("first 2")
          User.query.find_by(first_name: "not_exists").should be_nil

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.find_by!(first_name: "not_exists")
          end
        end
      end

      it "does not mutate the query while eager loading nested associations" do
        temporary do
          reinit_example_models

          category = Category.create!(id: 1, name: "Category")
          selected = User.create!(first_name: "Selected")
          other = User.create!(first_name: "Other")
          Post.create!(title: "Selected post", user_id: selected.id, category_id: category.id)
          Post.create!(title: "Other post", user_id: other.id, category_id: category.id)

          eager_sql = nil
          users = User.query.with_posts do |posts|
            eager_sql = posts.to_sql
            posts.with_category
          end
          sql = users.to_sql

          user = users.find_by!(first_name: "Selected")

          user.posts.map(&.title).should eq(["Selected post"])
          user.posts.first!.category.name.should eq("Category")
          eager_sql.not_nil!.should contain(%("first_name" = 'Selected'))
          eager_sql.not_nil!.should contain("LIMIT 1")
          users.to_sql.should eq(sql)
          users.tags.should be_empty
        end
      end

      it "restores the query after an eager-loading error" do
        temporary do
          reinit_example_models
          User.create!(first_name: "User")

          users = User.query.with_posts { raise "eager-loading error" }.where(active: true)
          sql = users.to_sql
          tags = users.tags.dup

          expect_raises(Exception, "eager-loading error") { users.find_by(first_name: "User") }
          users.to_sql.should eq(sql)
          users.tags.should eq(tags)
        end
      end
    end

    context "join" do
      it "find / find! with join using block syntax" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"

          Post.create! title: "title 1", user_id: user.id
          post2 = Post.create! title: "title 2", user_id: user.id

          if post = Post
               .query
               .join("users") { users.id == posts.user_id }
               .find_by do
                 (users.first_name == "user") &
                   (posts.title == "title 2")
               end
            (post.id).should eq(post2.id)
          end
        end
      end

      it "join with has_many association" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          Post.create! title: "title 1", user_id: user.id
          post2 = Post.create! title: "title 2", user_id: user.id

          query = User.query.join(:posts).where { posts.title == "title 2" }
          query.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") WHERE (\"posts\".\"title\" = 'title 2')"
          )

          query.size.should eq(1)
          query.first!.id.should eq(user.id)
        end
      end

      it "join with belongs_to association" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          Post.create! title: "title 1", user_id: user.id
          post2 = Post.create! title: "title 2", user_id: user.id

          query = Post.query.join(:user).where { posts.title == "title 2" }
          query.to_sql.should eq(
            "SELECT \"posts\".* FROM \"posts\" INNER JOIN \"users\" ON (\"posts\".\"user_id\" = \"users\".\"id\") WHERE (\"posts\".\"title\" = 'title 2')"
          )

          if post = query.find_by { users.first_name == "user" }
            post.id.should eq(post2.id)
          end
        end
      end

      it "joins concrete polymorphic belongs_to alias" do
        temporary do
          reinit_example_models

          employee = Employee.create! name: "employee"
          product = Product.create! name: "product"

          employee.id.should eq(product.id)
          Picture.create! name: "Employee picture", imageable_id: employee.id, imageable_type: "Employee"
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"

          query = Picture.query.join(:employee).where { employees.name == "employee" }
          query.to_sql.should eq(
            "SELECT \"pictures\".* FROM \"pictures\" INNER JOIN \"employees\" ON (\"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee') WHERE (\"employees\".\"name\" = 'employee')"
          )

          query.size.should eq(1)
          query.first!.name.should eq("Employee picture")
        end
      end

      it "raises a clear error when joining polymorphic belongs_to association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Polymorphic association 'imageable' for Picture cannot be used for SQL joins.*multiple tables/) do
            Picture.query.join(:imageable)
          end
        end
      end

      it "left_join with has_many association" do
        temporary do
          reinit_example_models

          user_with_posts = User.create! first_name: "With Posts"
          user_without_posts = User.create! first_name: "Without Posts"
          Post.create! title: "Post 1", user_id: user_with_posts.id

          query = User.query.left_join(:posts).group_by("users.id")
          query.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" LEFT JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") GROUP BY users.id"
          )

          query.size.should eq(2)
        end
      end

      it "where.missing with has_many association" do
        temporary do
          reinit_example_models

          user_with_posts = User.create! first_name: "With Posts"
          user_without_posts = User.create! first_name: "Without Posts"
          Post.create! title: "Post 1", user_id: user_with_posts.id

          query = User.query.where.missing(:posts)
          query.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" LEFT JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") WHERE \"posts\".\"id\" IS NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(user_without_posts.id)
        end
      end

      it "where.associated with has_many association" do
        temporary do
          reinit_example_models

          user_with_posts = User.create! first_name: "With Posts"
          user_without_posts = User.create! first_name: "Without Posts"
          Post.create! title: "Post 1", user_id: user_with_posts.id

          query = User.query.where.associated(:posts)
          query.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") WHERE \"posts\".\"id\" IS NOT NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(user_with_posts.id)
        end
      end

      it "join with polymorphic has_many association" do
        temporary do
          reinit_example_models

          employee = Employee.create! name: "employee"
          product = Product.create! name: "product"

          employee.id.should eq(product.id)
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"

          query = Employee.query.join(:pictures)
          query.to_sql.should eq(
            "SELECT \"employees\".* FROM \"employees\" INNER JOIN \"pictures\" ON (\"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee')"
          )

          query.count.should eq(0)
        end
      end

      it "where.missing with polymorphic has_many association" do
        temporary do
          reinit_example_models

          employee_without_pictures = Employee.create! name: "Without Pictures"
          employee_with_pictures = Employee.create! name: "With Pictures"
          product = Product.create! name: "product"

          employee_without_pictures.id.should eq(product.id)
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"
          Picture.create! name: "Employee picture", imageable_id: employee_with_pictures.id, imageable_type: "Employee"

          query = Employee.query.where.missing(:pictures)
          query.to_sql.should eq(
            "SELECT \"employees\".* FROM \"employees\" LEFT JOIN \"pictures\" ON (\"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee') WHERE \"pictures\".\"id\" IS NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(employee_without_pictures.id)
        end
      end

      it "where.associated with polymorphic has_many association" do
        temporary do
          reinit_example_models

          employee_without_pictures = Employee.create! name: "Without Pictures"
          employee_with_pictures = Employee.create! name: "With Pictures"
          product = Product.create! name: "product"

          employee_without_pictures.id.should eq(product.id)
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"
          Picture.create! name: "Employee picture", imageable_id: employee_with_pictures.id, imageable_type: "Employee"

          query = Employee.query.where.associated(:pictures)
          query.to_sql.should eq(
            "SELECT \"employees\".* FROM \"employees\" INNER JOIN \"pictures\" ON (\"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee') WHERE \"pictures\".\"id\" IS NOT NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(employee_with_pictures.id)
        end
      end

      it "raises a clear error when using where.missing with polymorphic belongs_to association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Polymorphic association 'imageable' for Picture cannot be used for SQL joins.*multiple tables/) do
            Picture.query.where.missing(:imageable)
          end
        end
      end

      it "raises a clear error when using where.associated with polymorphic belongs_to association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Polymorphic association 'imageable' for Picture cannot be used for SQL joins.*multiple tables/) do
            Picture.query.where.associated(:imageable)
          end
        end
      end

      it "filters associated records through concrete polymorphic belongs_to alias" do
        temporary do
          reinit_example_models

          employee = Employee.create! name: "employee"
          product = Product.create! name: "product"

          employee.id.should eq(product.id)
          Picture.create! name: "Employee picture", imageable_id: employee.id, imageable_type: "Employee"
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"

          query = Picture.query.where.associated(:employee)
          query.to_sql.should eq(
            "SELECT \"pictures\".* FROM \"pictures\" INNER JOIN \"employees\" ON (\"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee') WHERE \"employees\".\"id\" IS NOT NULL"
          )

          query.size.should eq(1)
          query.first!.name.should eq("Employee picture")
        end
      end

      it "where.missing with has_many through join table" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          post = Post.create! title: "Post 1", user_id: user.id
          tag_with_post = Tag.create! name: "used"
          tag_without_post = Tag.create! name: "orphan"
          PostTag.create! post_id: post.id, tag_id: tag_with_post.id

          query = Tag.query.where.missing(:post_tags)
          query.to_sql.should eq(
            "SELECT \"tags\".* FROM \"tags\" LEFT JOIN \"post_tags\" ON (\"post_tags\".\"tag_id\" = \"tags\".\"id\") WHERE \"post_tags\".\"id\" IS NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(tag_without_post.id)
        end
      end

      it "where.associated with has_many through join table" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          post = Post.create! title: "Post 1", user_id: user.id
          tag_with_post = Tag.create! name: "used"
          tag_without_post = Tag.create! name: "orphan"
          PostTag.create! post_id: post.id, tag_id: tag_with_post.id

          query = Tag.query.where.associated(:post_tags)
          query.to_sql.should eq(
            "SELECT \"tags\".* FROM \"tags\" INNER JOIN \"post_tags\" ON (\"post_tags\".\"tag_id\" = \"tags\".\"id\") WHERE \"post_tags\".\"id\" IS NOT NULL"
          )

          query.size.should eq(1)
          query.first!.id.should eq(tag_with_post.id)
        end
      end

      it "with_count with has_many association" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1"
          user2 = User.create! first_name: "user2"

          Post.create! title: "Post 1", user_id: user1.id
          Post.create! title: "Post 2", user_id: user1.id
          Post.create! title: "Post 3", user_id: user2.id

          query = User.query.with_count(:posts)
          query.to_sql.should eq(
            "SELECT \"users\".*, (SELECT COUNT(*) FROM \"posts\" WHERE \"posts\".\"user_id\" = \"users\".\"id\") AS posts_count FROM \"users\""
          )

          query.count.should eq(2)

          result = query.first!(fetch_columns: true)
          result.attributes["posts_count"].should eq(2)
        end
      end

      it "eager loads associations when ordering by a with_count alias" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1", active: true
          user2 = User.create! first_name: "user2", active: true
          user3 = User.create! first_name: "user3", active: false

          Post.create! title: "Post 1", user_id: user1.id
          Post.create! title: "Post 2", user_id: user1.id
          Post.create! title: "Post 3", user_id: user2.id
          Post.create! title: "Post 4", user_id: user3.id

          users = User.query
            .with_count(:posts, alias_name: "computed_posts_count")
            .with_posts
            .where(active: true)
            .order_by("computed_posts_count", :desc)
            .limit(1)
            .offset(1)

          users.ids.should eq([user2.id])
          users.first!.posts.size.should eq(1)
        end
      end

      it "eager loads has_many through associations when ordering by a with_count alias" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1"
          user2 = User.create! first_name: "user2"
          category1 = Category.create! name: "category1"
          category2 = Category.create! name: "category2"

          Post.create! title: "Post 1", user_id: user1.id, category_id: category1.id
          Post.create! title: "Post 2", user_id: user1.id, category_id: category2.id
          Post.create! title: "Post 3", user_id: user2.id, category_id: category1.id

          users = User.query
            .with_count(:posts, alias_name: "computed_posts_count")
            .with_categories
            .order_by("computed_posts_count", :desc)
            .limit(1)

          users.map(&.id).should eq([user1.id])
          users.first!.categories.map(&.id).sort!.should eq([category1.id, category2.id].sort)
        end
      end

      it "eager loads has_one associations when ordering by a with_count alias" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1"
          user2 = User.create! first_name: "user2"
          info1 = UserInfo.create! user_id: user1.id, registration_number: 1
          UserInfo.create! user_id: user2.id, registration_number: 2

          Post.create! title: "Post 1", user_id: user1.id
          Post.create! title: "Post 2", user_id: user1.id
          Post.create! title: "Post 3", user_id: user2.id

          users = User.query
            .with_count(:posts, alias_name: "computed_posts_count")
            .with_info
            .order_by("computed_posts_count", :desc)
            .limit(1)

          users.map(&.id).should eq([user1.id])
          users.first!.info!.id.should eq(info1.id)
        end
      end

      it "eager loads belongs_to associations when ordering by a with_count alias" do
        temporary do
          reinit_example_models

          user1 = User.create! first_name: "user1"
          user2 = User.create! first_name: "user2"
          post1 = Post.create! title: "Post 1", user_id: user1.id
          post2 = Post.create! title: "Post 2", user_id: user2.id
          tag1 = Tag.create! name: "tag1"
          tag2 = Tag.create! name: "tag2"

          PostTag.create! post_id: post1.id, tag_id: tag1.id
          PostTag.create! post_id: post1.id, tag_id: tag2.id
          PostTag.create! post_id: post2.id, tag_id: tag1.id

          posts = Post.query
            .with_count(:post_tags, alias_name: "computed_tags_count")
            .with_user
            .order_by("computed_tags_count", :desc)
            .limit(1)

          posts.map(&.id).should eq([post1.id])
          posts.first!.user.id.should eq(user1.id)
        end
      end

      it "with_count raises operation-specific error for unknown association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Unknown association 'unknown_association' for User.*Available associations: categories, comments, dependencies, dependents, info, posts, relationships.*with_count accepts an association name, not a table name/) do
            User.query.with_count(:unknown_association)
          end
        end
      end

      it "with_count with polymorphic has_many association" do
        temporary do
          reinit_example_models

          employee = Employee.create! name: "employee"
          product = Product.create! name: "product"

          employee.id.should eq(product.id)
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"

          query = Employee.query.with_count(:pictures, alias_name: "pictures_count")
          query.to_sql.should eq(
            "SELECT \"employees\".*, (SELECT COUNT(*) FROM \"pictures\" WHERE \"pictures\".\"imageable_id\" = \"employees\".\"id\" AND \"pictures\".\"imageable_type\" = 'Employee') AS pictures_count FROM \"employees\""
          )

          result = query.first!(fetch_columns: true)
          result.attributes["pictures_count"].should eq(0)
        end
      end

      it "raises a clear error when using with_count with polymorphic belongs_to association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Polymorphic association 'imageable' for Picture cannot be used with with_count.*multiple tables/) do
            Picture.query.with_count(:imageable)
          end
        end
      end

      it "with_count with concrete polymorphic belongs_to alias" do
        temporary do
          reinit_example_models

          employee = Employee.create! name: "employee"
          product = Product.create! name: "product"

          employee.id.should eq(product.id)
          Picture.create! name: "Employee picture", imageable_id: employee.id, imageable_type: "Employee"
          Picture.create! name: "Product picture", imageable_id: product.id, imageable_type: "Product"

          query = Picture.query.with_count(:employee, alias_name: "employee_count").order_by(:name)
          query.to_sql.should eq(
            "SELECT \"pictures\".*, (SELECT COUNT(*) FROM \"employees\" WHERE \"employees\".\"id\" = \"pictures\".\"imageable_id\" AND \"pictures\".\"imageable_type\" = 'Employee') AS employee_count FROM \"pictures\" ORDER BY \"name\" ASC"
          )

          results = query.to_a(fetch_columns: true)
          results[0].attributes["employee_count"].should eq(1)
          results[1].attributes["employee_count"].should eq(0)
        end
      end

      it "with_count with has_many through association" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          post = Post.create! title: "Post 1", user_id: user.id
          tag = Tag.create! name: "tag"
          PostTag.create! post_id: post.id, tag_id: tag.id

          query = Tag.query.with_count(:posts, alias_name: "posts_count")
          query.to_sql.should eq(
            "SELECT \"tags\".*, (SELECT COUNT(*) FROM \"post_tags\" WHERE \"post_tags\".\"tag_id\" = \"tags\".\"id\") AS posts_count FROM \"tags\""
          )

          query.count.should eq(1)

          result = query.first!(fetch_columns: true)
          result.attributes["posts_count"].should eq(1)
        end
      end

      it "with_count with has_many through join table" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          post = Post.create! title: "Post 1", user_id: user.id
          tag = Tag.create! name: "tag"
          PostTag.create! post_id: post.id, tag_id: tag.id

          query = Tag.query.with_count(:post_tags, alias_name: "tagging_count")
          query.to_sql.should eq(
            "SELECT \"tags\".*, (SELECT COUNT(*) FROM \"post_tags\" WHERE \"post_tags\".\"tag_id\" = \"tags\".\"id\") AS tagging_count FROM \"tags\""
          )

          query.count.should eq(1)

          result = query.first!(fetch_columns: true)
          result.attributes["tagging_count"].should eq(1)
        end
      end

      it "with_count preserves existing group_by used to deduplicate joins" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          Post.create! title: "Post 1", user_id: user.id
          Post.create! title: "Post 2", user_id: user.id

          query = User.query.join(:posts).group_by("users.id").with_count(:posts)
          query.to_sql.should eq(
            "SELECT \"users\".*, (SELECT COUNT(*) FROM \"posts\" WHERE \"posts\".\"user_id\" = \"users\".\"id\") AS posts_count FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") GROUP BY users.id"
          )

          query.count.should eq(1)

          results = query.to_a(fetch_columns: true)
          results.size.should eq(1)
          results.first.attributes["posts_count"].should eq(2)
        end
      end

      it "with_count deduplicates rows produced by joins" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          Post.create! title: "Post 1", user_id: user.id
          Post.create! title: "Post 2", user_id: user.id

          query = User.query.join(:posts).with_count(:posts)
          query.to_sql.should eq(
            "SELECT \"users\".*, (SELECT COUNT(*) FROM \"posts\" WHERE \"posts\".\"user_id\" = \"users\".\"id\") AS posts_count FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") GROUP BY users.id"
          )

          results = query.to_a(fetch_columns: true)
          results.size.should eq(1)
          results.first.id.should eq(user.id)
          results.all? { |result| result.attributes["posts_count"] == 2 }.should be_true
        end
      end

      it "join works with String association name" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          Post.create! title: "title 1", user_id: user.id

          # Should work with "posts" (String) as well as :posts (Symbol)
          query = User.query.join("posts")
          query.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\")"
          )

          query.size.should eq(1)
        end
      end

      it "join with has_one association" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          info = UserInfo.create! registration_number: 12345, user_id: user.id

          # has_one :info
          query1 = User.query.join(:info)
          query2 = User.query.join(:user_infos) { user_infos.user_id == users.id }

          query1.to_sql.should eq(query2.to_sql)

          query1.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" INNER JOIN \"user_infos\" ON (\"user_infos\".\"user_id\" = \"users\".\"id\")"
          )

          query1.size.should eq(1)
          query1.first!.id.should eq(user.id)
        end
      end

      it "join with has_many through association" do
        temporary do
          reinit_example_models

          user = User.create! first_name: "user"
          post = Post.create! title: "title", user_id: user.id

          category = Category.create! name: "Tech"
          post.update!(category_id: category.id)

          # User has_many :categories, through: Post
          query1 = User.query.join(:categories)

          query2 = User.query
            .join(:posts) { posts.user_id == users.id }
            .join(:categories) { categories.id == posts.category_id }

          query1.to_sql.should eq(query2.to_sql)

          # Should generate TWO joins: posts and categories
          query1.to_sql.should eq(
            "SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\") INNER JOIN \"categories\" ON (\"categories\".\"id\" = \"posts\".\"category_id\")"
          )

          query1.size.should eq(1)
          query1.first!.id.should eq(user.id)
        end
      end

      it "join raises error for unknown association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Unknown association 'unknown_association' for User.*Available associations: categories, comments, dependencies, dependents, info, posts, relationships.*For a table name, use join with a block/) do
            User.query.join(:unknown_association)
          end
        end
      end

      it "association filter raises operation-specific error for unknown association" do
        temporary do
          reinit_example_models

          expect_raises(Exception, /Unknown association 'unknown_association' for User.*Available associations: categories, comments, dependencies, dependents, info, posts, relationships.*Association filters accept an association name, not a table name/) do
            User.query.where.missing(:unknown_association)
          end
        end
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

        Lustra::SQL.truncate("users", cascade: true)

        expect_raises(Lustra::SQL::RecordNotFoundError) do
          User.query.first!
        end

        User.query.first.should be_nil
      end
    end

    it "first does not mutate the query while eager loading nested associations" do
      temporary do
        reinit_example_models

        category = Category.create!(id: 1, name: "Category")
        first_user = User.create!(id: 1, first_name: "First")
        last_user = User.create!(id: 2, first_name: "Last")
        Post.create!(title: "First post", user_id: first_user.id, category_id: category.id)
        Post.create!(title: "Last post", user_id: last_user.id, category_id: category.id)

        eager_sql = nil
        users = User.query.with_posts do |posts|
          eager_sql = posts.to_sql
          posts.with_category
        end.order_by(id: :desc)
        sql = users.to_sql

        user = users.first!

        user.id.should eq(last_user.id)
        user.posts.map(&.title).should eq(["Last post"])
        user.posts.first!.category.name.should eq("Category")
        eager_sql.should_not be_nil
        eager_sql.not_nil!.should contain("LIMIT 1")
        users.to_sql.should eq(sql)
      end
    end

    it "first restores the query after an eager-loading error" do
      temporary do
        reinit_example_models
        User.create!(first_name: "User")

        users = User.query.with_posts { raise "eager-loading error" }.order_by(id: :desc).limit(5)
        sql = users.to_sql

        expect_raises(Exception, "eager-loading error") { users.first }
        users.to_sql.should eq(sql)
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

        Lustra::SQL.truncate(User, cascade: true)

        expect_raises(Lustra::SQL::RecordNotFoundError) do
          User.query.last!
        end

        User.query.last.should be_nil
      end
    end

    it "last does not mutate the query while eager loading nested associations" do
      temporary do
        reinit_example_models

        category = Category.create!(id: 1, name: "Category")
        first_user = User.create!(id: 1, first_name: "First")
        last_user = User.create!(id: 2, first_name: "Last")
        Post.create!(title: "First post", user_id: first_user.id, category_id: category.id)
        Post.create!(title: "Last post", user_id: last_user.id, category_id: category.id)

        eager_sql = nil
        users = User.query.with_posts do |posts|
          eager_sql = posts.to_sql
          posts.with_category
        end.order_by(id: :asc)
        sql = users.to_sql

        user = users.last!

        user.id.should eq(last_user.id)
        user.posts.map(&.title).should eq(["Last post"])
        user.posts.first!.category.name.should eq("Category")
        eager_sql.should_not be_nil
        eager_sql.not_nil!.should contain(%(ORDER BY "id" DESC))
        eager_sql.not_nil!.should contain("LIMIT 1")
        users.to_sql.should eq(sql)
      end
    end

    it "last restores the query after an eager-loading error" do
      temporary do
        reinit_example_models
        User.create!(first_name: "User")

        users = User.query.with_posts { raise "eager-loading error" }.order_by(id: :asc).limit(5)
        sql = users.to_sql

        expect_raises(Exception, "eager-loading error") { users.last }
        users.to_sql.should eq(sql)
      end
    end

    it "delete_all" do
      temporary do
        reinit_example_models

        10.times do |x|
          User.create! first_name: "user #{x}"
        end

        User.query.count.should eq(10)
        User.query.where { id <= 5 }.delete_all.should eq(5)
        User.query.count.should eq(5)
      end
    end
  end
end
