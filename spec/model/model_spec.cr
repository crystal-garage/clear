require "../spec_helper"
require "../data/example_models"

module ModelSpec
  describe "Clear::Model" do
    context "fields management" do
      it "can load from tuple" do
        temporary do
          reinit_example_models
          u = User.new({id: 123})
          u.id.should eq 123
          u.persisted?.should be_false
        end
      end

      it "can load link string <-> varchar" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", middle_name: "William")

          User.query.each do |u|
            u.middle_name.should eq "William"
          end
        end
      end

      it "can pluck" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", middle_name: "William")
          User.create!(id: 2, first_name: "Hans", middle_name: "Zimmer")

          User.query.pluck("first_name", "middle_name").should eq [{"John", "William"}, {"Hans", "Zimmer"}]
          User.query.limit(1).pluck_col("first_name").should eq(["John"])
          User.query.limit(1).pluck_col("first_name", String).should eq(["John"])
          User.query.order_by("id").pluck_col("CASE WHEN id % 2 = 0 THEN id ELSE NULL END AS id").should eq([2_i64, nil])
          User.query.pluck("first_name": String, "UPPER(middle_name)": String).should eq [{"John", "WILLIAM"}, {"Hans", "ZIMMER"}]
        end
      end

      it "can detect persistence" do
        temporary do
          reinit_example_models
          u = User.new({id: 1}, persisted: true)
          u.persisted?.should be_true
        end
      end

      it "can detect change in fields" do
        temporary do
          reinit_example_models
          u = User.new({id: 1})
          u.id = 2
          u.update_h.should eq({"id" => 2})
          u.id = 1
          u.update_h.should eq({} of String => ::DB::Any) # no more change, because id is back to the same !
        end
      end

      it "can deal with boolean nullable" do # Specific bug with converter already fixed
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x", active: nil})
          u.save!
          u2 = User.query.first!
          u2.active.should eq(nil)
        end
      end

      it "should not try to update the model if there's nothing to update" do
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x"})
          u.save!
          u.id = 2
          u.update_h.should eq({"id" => 2})
          u.id = 1
          u.update_h.should eq({} of String => ::DB::Any) # no more change, because id is back to the same !
          u.save!                                         # Nothing should happens
        end
      end

      it "can save the model" do
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x"})
          u.notification_preferences = JSON.parse("{}")
          u.id = 2 # Force the change!
          u.save!
          User.query.count.should eq 1
        end
      end

      it "can update the model" do
        temporary do
          reinit_example_models

          u = User.create!({id: 1, first_name: "x"})
          u.update!(first_name: "Malcom")

          User.query.first!.first_name.should eq "Malcom"
        end
      end

      it "can reload the model" do
        temporary do
          reinit_example_models

          u = User.create!({id: 1, first_name: "x"})

          # Low level update
          User.query.where { id == 1 }.to_update.set(first_name: "Malcom").execute

          u.first_name = "Danny"
          u.changed?.should be_true

          # reload the model now
          u.reload.first_name.should eq "Malcom"
          u.changed?.should be_false

          u2 = User.create!({id: 2, first_name: "y"})

          p = Post.create! user: u, title: "Reload testing post"

          p.user.id.should eq(1)
          p.user = u2            # Change the user, DO NOT SAVE.
          p.reload               # Reload the model now:
          p.user.id.should eq(1) # Cache should be invalidated
        end
      end

      it "can import a number of models" do
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x"})
          u2 = User.new({id: 2, first_name: "y"})
          u3 = User.new({id: 3, first_name: "z"})

          o = User.import([u, u2, u3])

          o[0].id.should eq 1
          o[0].first_name.should eq "x"
          o[2].id.should eq 3
          o[2].first_name.should eq "z"

          User.query.count.should eq 3
        end
      end

      it "can save with conflict resolution" do
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "John"})
          u.save! # Create a new user

          expect_raises(Exception, /duplicate key/) do
            u2 = User.new({id: 1, first_name: "Louis"})
            u2.save!
          end
        end

        temporary do
          reinit_example_models

          u = User.new({id: 1, first_name: "John"})
          u.save! # Create a new user

          u2 = User.new({id: 1, first_name: "Louis"})
          u2.save! { |qry|
            qry.on_conflict("(id)").do_update { |up|
              up.set("first_name = excluded.first_name")
                .where { users.id == excluded.id }
            }
          }

          User.query.count.should eq 1
          User.query.first!.first_name.should eq("Louis")
        end
      end

      it "save in good order the belongs_to models" do
        temporary do
          reinit_example_models
          u = User.new
          p = Post.new({title: "some post"})
          p.user = u
          p.save.should eq(false) # < Must save the user first. but user is missing is first name !

          p.user.first_name = "I fix the issue!" # < Fix the issue

          p.save.should eq(true) # Should save now

          u.id.should eq(1)      # Should be set
          p.user.id.should eq(1) # And should be set
        end
      end

      it "save in good order the belongs_to models2" do
        temporary do
          reinit_example_models

          u = User.new({first_name: "John"})
          post = Post.new({user: u, title: "some post"})

          u.save!
          post.save! # Exception

          post.user_id.should eq(u.id)
        end
      end

      it "does not set persisted on failed insert" do
        temporary do
          reinit_example_models
          # There's no user_id = 999
          user_info = UserInfo.new({registration_number: 123, user_id: 999})

          expect_raises(Exception) do
            user_info.save! # Should raise exception
          end

          user_info.persisted?.should be_false
        end

        temporary do
          reinit_example_models

          User.create!({id: 999, first_name: "Test"})
          user_info = UserInfo.new({registration_number: 123, user_id: 999})

          user_info.save.should be_true
          user_info.persisted?.should be_true
        end
      end

      it "can save persisted model" do
        temporary do
          reinit_example_models
          u = User.new
          u.persisted?.should eq false
          u.first_name = "hello"
          u.last_name = "world"
          u.save!

          u.persisted?.should eq true
          u.id.should eq 1
        end
      end

      it "can use set to setup multiple fields at once" do
        temporary do
          reinit_example_models

          # Set from tuple
          u = User.new
          u.set first_name: "hello", last_name: "world"
          u.save!
          u.persisted?.should be_true
          u.first_name.should eq "hello"
          u.changed?.should be_false

          # Set from hash
          u = User.new
          u.set({"first_name" => "hello", "last_name" => "world"})
          u.save!
          u.persisted?.should be_true
          u.first_name.should eq "hello"
          u.changed?.should be_false

          # Set from json
          u = User.new
          u.set(JSON.parse(%<{"first_name": "hello", "last_name": "world"}>))
          u.save!
          u.persisted?.should be_true
          u.first_name.should eq "hello"
          u.changed?.should be_false
        end
      end

      it "can load models" do
        temporary do
          reinit_example_models
          User.create
          User.query.each do |u|
            u.id.should_not eq nil
          end
        end
      end

      it "can read through cursor" do
        temporary do
          reinit_example_models
          User.create
          User.query.each_with_cursor(batch: 50) do |u|
            u.id.should_not eq nil
          end
        end
      end

      it "can fetch computed column" do
        temporary do
          reinit_example_models
          User.create({first_name: "a", last_name: "b"})

          u = User.query.select({full_name: "first_name || ' ' || last_name"}).first!(fetch_columns: true)
          u["full_name"].should eq "a b"
        end
      end

      it "can create a model using virtual fields" do
        temporary do
          reinit_example_models
          User.create!(full_name: "Hello World")

          u = User.query.first!
          u.first_name.should eq "Hello"
          u.last_name.should eq "World"
        end
      end

      it "define constraints on has_many to build object" do
        temporary do
          reinit_example_models
          User.create({first_name: "x"})
          u = User.query.first!
          p = User.query.first!.posts.build

          p.user_id.should eq(u.id)
        end
      end

      it "works on date fields with different timezone" do
        now = Time.local

        temporary do
          reinit_example_models

          u = User.new

          u.first_name = "A"
          u.last_name = "B"
          u.created_at = now

          u.save!
          u.id.should_not eq nil

          u = User.find! u.id
          u.created_at.to_unix.should be_close(now.to_unix, 1)
        end
      end

      it "can count using offset and limit" do
        temporary do
          reinit_example_models

          9.times do |x|
            User.create!({first_name: "user#{x}"})
          end

          User.query.limit(5).count.should eq(5)
          User.query.limit(5).offset(5).count(Int32).should eq(4)
        end
      end

      it "can count using group_by" do
        temporary do
          reinit_example_models
          9.times do |x|
            User.create!({first_name: "user#{x}", last_name: "Doe"})
          end

          User.query.group_by("last_name").count.should eq(1)
        end
      end

      it "can find_or_create" do
        temporary do
          reinit_example_models

          u = User.query.find_or_create(last_name: "Henry") do |user|
            user.first_name = "Thierry"
            user.save
          end

          u.first_name.should eq("Thierry")
          u.last_name.should eq("Henry")
          u.id.should eq(1)

          u = User.query.find_or_create(last_name: "Henry") do |user|
            user.first_name = "King" # << This should not be triggered since we found the row
          end
          u.first_name.should eq("Thierry")
          u.last_name.should eq("Henry")
          u.id.should eq(1)
        end
      end

      it "raises a RecordNotFoundError for an empty find!" do
        temporary do
          reinit_example_models

          expect_raises(Clear::SQL::RecordNotFoundError) do
            User.find!(1)
          end
        end
      end

      it "can set back a field to nil" do
        temporary do
          reinit_example_models

          u = User.create({first_name: "Rudolf"})

          ui = UserInfo.create({registration_number: 123, user_id: u.id})

          ui.user_id = nil # Remove user_id, just to see what's going on !
          ui.save!
        end
      end

      it "can read and write jsonb" do
        temporary do
          reinit_example_models
          u = User.new

          u.first_name = "Yacine"
          u.last_name = "Petitprez"
          u.save.should eq true

          u.notification_preferences = JSON.parse(JSON.build do |json|
            json.object do
              json.field "email", true
            end
          end)
          u.save.should eq true
          u.persisted?.should eq true
        end
      end

      it "can query the last model" do
        temporary do
          reinit_example_models
          User.create({first_name: "Yacine"})
          User.create({first_name: "Joan"})
          User.create({first_name: "Mary"})
          User.create({first_name: "Lianna"})

          x = User.query.order_by("first_name").last!
          x.first_name.should eq("Yacine")
        end
      end

      it "raises a RecordNotFoundError without first" do
        temporary do
          reinit_example_models

          expect_raises(Clear::SQL::RecordNotFoundError) do
            User.query.first!
          end
        end
      end

      it "raises a RecordNotFoundError without last" do
        temporary do
          reinit_example_models

          expect_raises(Clear::SQL::RecordNotFoundError) do
            User.query.last!
          end
        end
      end

      it "can delete a model" do
        temporary do
          reinit_example_models

          User.create({first_name: "Malcom", last_name: "X"})

          u = User.new
          u.first_name = "LeBron"
          u.last_name = "James"
          u.save.should eq true

          User.query.count.should eq 2
          u.persisted?.should eq true

          u.delete.should eq true
          u.persisted?.should eq false
          User.query.count.should eq 1
        end
      end

      it "can touch model" do
        temporary do
          reinit_example_models

          c = Category.create!({name: "Nature"})
          updated_at = c.updated_at
          c.touch
          c.updated_at.should_not eq(updated_at)
        end
      end
    end

    it "can create a model by generating an uuid primary key" do
      temporary do
        reinit_example_models
        m = ModelWithUUID.create!
        m.id.should_not eq Nil
      end
    end

    it "can create a model with a predefined uuid primary key" do
      temporary do
        reinit_example_models
        some_uuid = UUID.new("5ca27508-f2ce-441b-b2cf-41134793e7a1")
        m = ModelWithUUID.create!({id: some_uuid})
        m.id.should eq some_uuid
      end
    end

    it "can load a column of type Array" do
      temporary do
        reinit_example_models

        u = User.create!({first_name: "John"})
        p = Post.create!({title: "A post", user_id: u.id})

        p.tags = ["a", "b", "c"]
        p.flags = [11_234_212_343_543_i64, 11_234_212_343_543_i64, -12_928_394_059_603_i64, 12_038_493_029_484_i64]
        p.save!

        p = Post.query.first!
        p.tags.should eq ["a", "b", "c"]
        p.flags.should eq [11_234_212_343_543_i64, 11_234_212_343_543_i64, -12_928_394_059_603_i64, 12_038_493_029_484_i64]

        # Test insertion of empty array
        Post.create!({title: "A post", user_id: u.id, tags: [] of String})
      end
    end

    context "with self-reference and has_many through" do
      it "can assign self-reference has_many through" do
        temporary do
          reinit_example_models

          user1 = User.create!({first_name: "John"})
          user2 = User.create!({first_name: "Jane"})

          user1.dependencies << user2

          user1.dependencies.count.should eq(1)
          user2.dependents.count.should eq(1)

          dependencies_first_names = [] of String
          user1.dependencies.each { |u| dependencies_first_names << u.first_name }
          dependencies_first_names.should eq(["Jane"])

          dependents_first_names = [] of String
          user2.dependents.each { |u| dependents_first_names << u.first_name }
          dependents_first_names.should eq(["John"])
        end
      end

      it "can create self-reference has_many through" do
        temporary do
          reinit_example_models

          user1 = User.create!({first_name: "John"})
          user2 = User.create!({first_name: "Jane"})

          Relationship.create!({master: user1, dependency: user2})

          user1.dependencies.count.should eq(1)
          user2.dependents.count.should eq(1)
        end
      end

      it "can unlink self-reference has_many through" do
        temporary do
          reinit_example_models

          user1 = User.create!({first_name: "John"})
          user2 = User.create!({first_name: "Jane"})

          user1.dependencies << user2

          user1.dependencies.count.should eq(1)
          user2.dependents.count.should eq(1)

          user1.dependencies.unlink(User.query.find!({first_name: "Jane"}))

          user1.dependencies.count.should eq(0)
          user2.dependents.count.should eq(0)
        end
      end
    end

    context "with has_many through relation" do
      it "can query has_many through" do
        temporary do
          reinit_example_models

          u = User.create!({first_name: "John"})

          c = Category.create!({name: "Nature"})
          Post.create!({title: "Post about Poneys", user_id: u.id, category_id: c.id})

          # Create a second post, with same category.
          Post.create!({title: "Post about Dogs", user_id: u.id, category_id: c.id})

          # Categories should return 1, as we remove duplicate
          u.categories.to_sql.should eq "SELECT DISTINCT ON (\"categories\".\"id\") \"categories\".* " +
                                        "FROM \"categories\" " +
                                        "INNER JOIN \"posts\" ON " +
                                        "(\"posts\".\"category_id\" = \"categories\".\"id\") " +
                                        "WHERE (\"posts\".\"user_id\" = 1)"

          # Test addition in has_many relation
          u.posts << Post.new({title: "a title", category_id: c.id})
          u.categories.count.should eq(1)

          # Test addition in has_many through relation
          p = Post.query.first!

          p.tag_relations.count.should eq(0)

          p.tag_relations << Tag.new({name: "Awesome"})
          p.tag_relations << Tag.new({name: "Why not"})

          p.tag_relations.count.should eq(2)
          p.tag_relations.first!.name.should eq("Awesome")
          p.tag_relations.offset(1).first!.name.should eq("Why not")
        end
      end

      it "can unlink has_many through" do
        temporary do
          reinit_example_models

          u = User.create!({first_name: "John"})
          c = Category.create!({name: "Nature"})
          p = Post.create!({title: "Post about Poneys", user_id: u.id, category_id: c.id})

          p.tag_relations << Tag.new({name: "Awesome"})
          p.tag_relations << Tag.new({name: "Why not"})

          p.tag_relations.count.should eq(2)
          p.tag_relations.unlink(Tag.query.find!({name: "Awesome"}))
          p.tag_relations.count.should eq(1)
        end
      end
    end

    context "with join" do
      it "resolves by default ambiguous columns in joins" do
        temporary do
          reinit_example_models

          u = User.create!({first_name: "Join User"})

          Post.create!({title: "A Post", user_id: u.id})

          Post.query.join(:users) { posts.user_id == users.id }.to_sql
            .should eq "SELECT \"posts\".* FROM \"posts\" INNER JOIN \"users\" " +
                       "ON (\"posts\".\"user_id\" = \"users\".\"id\")"
        end
      end

      it "resolve ambiguous columns in with_* methods" do
        temporary do
          reinit_example_models
          u = User.create!({first_name: "Join User"})
          Post.create!({title: "A Post", user_id: u.id})

          user_with_a_post_minimum = User.query.distinct.join(:posts) { posts.user_id == users.id }

          user_with_a_post_minimum.to_sql.should eq \
            "SELECT DISTINCT \"users\".* FROM \"users\" INNER JOIN " +
            "\"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\")"

          user_with_a_post_minimum.with_posts.each { } # Should just execute
        end
      end

      it "should wildcard with default model only if no select is made (before OR after)" do
        temporary do
          reinit_example_models
          u = User.create!({first_name: "Join User"})
          Post.create!({title: "A Post", user_id: u.id})

          user_with_a_post_minimum = User.query.distinct
            .join(:posts) { posts.user_id == users.id }
            .select(:first_name, :last_name)

          user_with_a_post_minimum.to_sql.should eq \
            "SELECT DISTINCT \"first_name\", \"last_name\" FROM \"users\" INNER JOIN " +
            "\"posts\" ON (\"posts\".\"user_id\" = \"users\".\"id\")"

          user_with_a_post_minimum.with_posts.each { } # Should just execute
        end
      end
    end

    context "with pagination" do
      it "test array" do
      end

      it "can pull the next 5 users from page 2" do
        temporary do
          reinit_example_models

          15.times do |x|
            User.create!({first_name: "user#{x}"})
          end

          users = User.query.paginate(page: 2, per_page: 5)
          users.map(&.first_name).should eq ["user5", "user6", "user7", "user8", "user9"]
          users.total_entries.should eq 15
        end
      end

      it "can export to json" do
        temporary do
          reinit_example_models
          u = User.new({first_name: "Hello", last_name: "World"})
          u.to_json.should eq %({"first_name":"Hello","last_name":"World"})

          u.to_json(emit_nulls: true).should eq(
            %({"id":null,"first_name":"Hello","last_name":"World","middle_name":null,"active":null,"notification_preferences":null,"updated_at":null,"created_at":null}))
        end
      end

      it "can paginate with where clause" do
        temporary do
          reinit_example_models
          last_names = ["smith", "jones"]
          15.times do |x|
            last_name = last_names[x % 2]?
            User.create!({first_name: "user#{x}", last_name: last_name})
          end

          users = User.query.where { last_name == "smith" }.paginate(page: 1, per_page: 5)
          users.map(&.first_name).should eq ["user0", "user2", "user4", "user6", "user8"]
          users.total_entries.should eq 8
        end
      end
    end

    describe "Clear::Model::JSONDeserialize" do
      it "can create a model json IO" do
        user_body = {first_name: "foo"}
        io = IO::Memory.new user_body.to_json
        user = User.from_json(io)
        user.first_name.should eq user_body["first_name"]
      end

      it "can create a new model instance from json" do
        user_body = {first_name: "Steve"}
        user = User.from_json(user_body.to_json)
        user.first_name.should eq(user_body["first_name"])
      end

      it "sets fields from json" do
        user_body = {first_name: "Steve"}
        update_body = {first_name: "stevo"}
        user = User.new(user_body)
        user.set_from_json(update_body.to_json)
        user.first_name.should eq update_body["first_name"]
      end

      it "sets nillable fields to nil" do
        user = User.new({first_name: "Foo", last_name: "Bar"})
        user.set_from_json({last_name: nil}.to_json)
        user.last_name.should be_nil
      end

      it "does not set unnillable fields to nil" do
        user_body = {first_name: "Foo"}
        user = User.new(user_body)
        user.set_from_json({first_name: nil}.to_json)
        user.first_name.should eq user_body["first_name"]
      end

      it "create and update a model from json" do
        temporary do
          reinit_example_models

          u1_body = {first_name: "George"}
          u1 = User.create_from_json(u1_body.to_json)
          u1.first_name.should eq u1_body["first_name"]

          u2_body = {first_name: "Eliza"}
          u2 = User.create_from_json!(u2_body.to_json)
          u2.first_name.should eq(u2_body["first_name"])

          u3_body = {first_name: "Angelica"}
          u3 = u2.update_from_json(u3_body.to_json)
          u3.first_name.should eq(u3_body["first_name"])

          u4_body = {first_name: "Aaron"}
          u4 = u3.update_from_json!(u4_body.to_json)
          u4.first_name.should eq(u4_body["first_name"])
        end
      end
    end

    describe "Clear::Model::HasColumns mass_assign" do
      it "should do mass_assignment" do
        temporary do
          reinit_example_models

          u1_body = {first_name: "George", last_name: "Dream", middle_name: "Sapnap"}
          u1 = User.create_from_json(u1_body.to_json, trusted: true)
          u1.first_name.should eq u1_body["first_name"]
          u1.last_name.should eq u1_body["last_name"]
          u1.middle_name.should eq u1_body["middle_name"]
        end
      end

      it "should not do mass_assignment" do
        temporary do
          reinit_example_models

          u1_body = {first_name: "George", last_name: "Dream", middle_name: "Sapnap"}
          u1 = User.create_from_json(u1_body.to_json)
          u1.first_name.should eq u1_body["first_name"]
          u1.last_name.should eq u1_body["last_name"]
          u1.middle_name.should be_nil
        end
      end
    end

    describe "Access to custom fields" do
      it "should be able to access custom fields" do
        temporary do
          reinit_example_models

          u1_body = {first_name: "George", last_name: "Dream", middle_name: "Sapnap"}
          User.create_from_json(u1_body.to_json)

          usr = User.query.where { first_name == "George" }.select("first_name, 'example' as custom_field").first!(fetch_columns: true)
          usr["custom_field"].should eq "example"

          json = {
            custom_field: usr["custom_field"],
          }.to_json

          json.should eq %({"custom_field":"example"})
        end
      end
    end

    describe "BigDecimal / Numeric column in Migration" do
      it "should create a new model with BigDecimal fields" do
        temporary do
          reinit_example_models

          data = BigDecimalData.new({num1: 42.0123, num2: "42_42_42_24.0123_456_789", num3: "-102938719.2083710928371092837019283701982370918237"})
          data.num1.should eq(BigDecimal.new(BigInt.new(420123), 4))
          data.num2.should eq(BigDecimal.new(BigInt.new(424242240123456789), 10))
          data.num3.should eq(BigDecimal.new(BigInt.new("-1029387192083710928371092837019283701982370918237".to_big_i), 40))

          data.save!

          data.num1.should eq(BigDecimal.new(BigInt.new(420123), 4))
          data.num2.should eq(42424224.01234568)
          data.num3.should eq(BigDecimal.new(BigInt.new("-1029387192083710928371092837019283701982370918237".to_big_i), 40).trunc)

          # Clear::SQL::Error:numeric field overflow
          data.num4 = BigDecimal.new(BigInt.new("-1029387192083710928371092837019283701982370918237".to_big_i), 40)

          expect_raises(Clear::SQL::Error) do
            data.save!
          end
        end
      end
    end
  end
end
