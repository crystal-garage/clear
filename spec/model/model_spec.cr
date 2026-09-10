require "../spec_helper"
require "../data/example_models"

module ModelSpec
  class ModelWithoutPrimaryKey
    include Lustra::Model

    column name : String
  end

  describe "Lustra::Model" do
    context "fields management" do
      it "raises helpful error when primary key is missing" do
        expect_raises(Exception, /ModelWithoutPrimaryKey` does not define a primary key\.\s+Add\s+`primary_key`, or mark a column with `primary: true`\./) do
          ModelWithoutPrimaryKey.new.__pkey__
        end
      end

      it "load from tuple" do
        temporary do
          reinit_example_models
          u = User.new({id: 123})
          u.id.should eq 123
          u.persisted?.should be_false
        end
      end

      it "load link string <-> varchar" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", middle_name: "William")

          User.query.each do |u|
            u.middle_name.should eq "William"
          end
        end
      end

      it "pluck" do
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

      it "pluck does not mutate selected columns" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", middle_name: "William")

          users = User.query.where(id: 1)
          sql = users.to_sql

          users.pluck_col("first_name").should eq(["John"])
          users.to_sql.should eq(sql)
          users.each(&.first_name.should(eq("John")))
        end
      end

      it "pluck does not run eager loading hooks" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John")

          hook_called = false
          users = User.query.with_posts { hook_called = true }

          users.pluck_col("first_name").should eq(["John"])
          hook_called.should be_false

          users.each { }
          hook_called.should be_true
        end
      end

      it "low-level fetch_first restores its limit while running hooks on the constrained query" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John")

          query = Lustra::SQL.select.from("users").limit(5)
          sql = query.to_sql
          hook_sql = nil
          query.before_query { hook_sql = query.to_sql }

          query.fetch_first.should_not be_nil
          hook_sql.not_nil!.should contain("LIMIT 1")
          query.to_sql.should eq(sql)
        end
      end

      it "low-level fetch_first restores its limit after a hook error" do
        query = Lustra::SQL.select.from("users").limit(5)
        sql = query.to_sql
        query.before_query { raise "query hook error" }

        expect_raises(Exception, "query hook error") { query.fetch_first }
        query.to_sql.should eq(sql)
      end

      it "exists?" do
        temporary do
          reinit_example_models

          # Empty table should return false
          User.query.exists?.should be_false

          # Create a user
          User.create!(id: 1, first_name: "John")
          User.query.exists?.should be_true

          # Test with conditions
          User.query.where { first_name == "John" }.exists?.should be_true
          User.query.where { first_name == "Jane" }.exists?.should be_false

          # Test with NamedTuple conditions
          User.query.where(first_name: "John").exists?.should be_true
          User.query.where(first_name: "Jane").exists?.should be_false
        end
      end

      it "empty? does not mutate selected columns" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John")

          users = User.query.where(id: 1)
          sql = users.to_sql

          users.empty?.should be_false
          users.to_sql.should eq(sql)
          users.each(&.first_name.should(eq("John")))
        end
      end

      it "find with array of IDs" do
        temporary do
          reinit_example_models

          # Create test users
          User.create!(id: 1, first_name: "John")
          User.create!(id: 2, first_name: "Jane")
          User.create!(id: 3, first_name: "Bob")
          User.create!(id: 4, first_name: "Alice")

          # Test finding multiple users by array of IDs
          users = User.find([1, 2, 3])
          users.size.should eq(3)
          users.map(&.id).sort!.should eq([1, 2, 3])
          users.map(&.first_name).sort!.should eq(["Bob", "Jane", "John"])

          # Test with empty array
          users = User.find([] of Int64)
          users.size.should eq(0)

          # Test with single ID in array
          users = User.find([2])
          users.size.should eq(1)
          users.first.id.should eq(2)
          users.first.first_name.should eq("Jane")

          # Test with some non-existent IDs (should only return existing ones)
          users = User.find([1, 99, 3, 100])
          users.size.should eq(2)
          users.map(&.id).sort!.should eq([1, 3])

          # Test with all non-existent IDs
          users = User.find([99, 100, 101])
          users.size.should eq(0)

          # Test find! with valid IDs
          users = User.find!([1, 2, 3])
          users.size.should eq(3)
          users.map(&.id).sort!.should eq([1, 2, 3])

          # Test find! raises error when some IDs not found
          expect_raises(Lustra::SQL::RecordNotFoundError, /Couldn't find all records/) do
            User.find!([1, 2, 99])
          end

          # Test find! raises error when all IDs not found
          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.find!([99, 100])
          end

          # Test find! with empty array
          users = User.find!([] of Int64)
          users.size.should eq(0)
        end
      end

      it "find_by" do
        temporary do
          reinit_example_models

          # Create test users
          User.create!(id: 1, first_name: "John", last_name: "Doe", active: true)
          User.create!(id: 2, first_name: "Jane", last_name: "Smith", active: false)
          User.create!(id: 3, first_name: "Bob", last_name: "Doe", active: true)

          # Test basic find_by with single condition
          user = User.find_by(first_name: "John")
          user.should_not be_nil
          if u = user
            u.id.should eq(1)
            u.last_name.should eq("Doe")
          end

          # Test find_by with multiple conditions
          user = User.find_by(first_name: "Bob", last_name: "Doe")
          user.should_not be_nil
          user.try(&.id).should eq(3)

          # Test find_by returns nil when not found
          user = User.find_by(first_name: "NonExistent")
          user.should be_nil

          # Test find_by! raises error when not found
          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.find_by!(first_name: "NonExistent")
          end

          # Test find_by! returns model when found
          user = User.find_by!(first_name: "Jane")
          user.id.should eq(2)
          user.last_name.should eq("Smith")

          # Test find_by on collection (with chaining)
          user = User.query.where { active.true? }.find_by(last_name: "Doe")
          user.should_not be_nil
          # Should return John or Bob (both active with last_name Doe)
          # find_by returns first match
          if u = user
            ["John", "Bob"].should contain(u.first_name)
          end

          # Test find_by with NamedTuple
          tuple = {first_name: "Jane", active: false}
          user = User.find_by(tuple)
          user.should_not be_nil
          user.try(&.id).should eq(2)
        end
      end

      it "update_column and update_columns" do
        temporary do
          reinit_example_models

          # Create test user
          user = User.create!(first_name: "John", last_name: "Doe", active: true, posts_count: 5)
          original_updated_at = user.updated_at

          # Test update_column with single field
          sleep 0.01.seconds
          user.update_column(:first_name, "Jane")
          user.first_name.should eq("Jane")

          # Verify it was saved to DB
          user.reload
          user.first_name.should eq("Jane")

          # Verify updated_at was NOT changed (bypasses timestamps)
          user.updated_at.should eq(original_updated_at)

          # Test update_column with different types
          user.update_column(:posts_count, 10)
          user.posts_count.should eq(10)
          user.reload.posts_count.should eq(10)

          user.update_column(:active, false)
          user.active.should be_false
          user.reload.active.should be_false

          # Test update_columns with multiple fields
          sleep 0.01.seconds
          user.update_columns(first_name: "Bob", last_name: "Smith", posts_count: 20)
          user.first_name.should eq("Bob")
          user.last_name.should eq("Smith")
          user.posts_count.should eq(20)

          # Verify saved to DB
          user.reload
          user.first_name.should eq("Bob")
          user.last_name.should eq("Smith")
          user.posts_count.should eq(20)

          # Verify updated_at still not changed
          user.updated_at.should eq(original_updated_at)

          # Test update_columns with NamedTuple
          tuple = {first_name: "Alice", active: true}
          user.update_columns(tuple)
          user.reload
          user.first_name.should eq("Alice")
          user.active.should be_true

          # Test update_columns with Hash
          hash = {"last_name" => "Johnson", "posts_count" => 15} of String => Lustra::SQL::Any
          user.update_columns(hash)
          user.reload
          user.last_name.should eq("Johnson")
          user.posts_count.should eq(15)

          # Test that it raises error on non-persisted model
          new_user = User.new({first_name: "Test"})
          expect_raises(Exception, /must be persisted/) do
            new_user.update_column(:first_name, "Fail")
          end

          expect_raises(Exception, /must be persisted/) do
            new_user.update_columns(first_name: "Fail")
          end
        end
      end

      it "increment and decrement" do
        temporary do
          reinit_example_models

          # Create test user with posts_count
          user = User.create!(first_name: "John", posts_count: 5)
          user.posts_count.should eq(5)

          # Test increment! (saves to DB immediately)
          user.increment!(:posts_count)
          user.posts_count.should eq(6)
          # Verify it was saved to DB
          user.reload.posts_count.should eq(6)

          # Test increment! with custom amount
          user.increment!(:posts_count, 3)
          user.posts_count.should eq(9)
          user.reload.posts_count.should eq(9)

          # Test decrement!
          user.decrement!(:posts_count)
          user.posts_count.should eq(8)
          user.reload.posts_count.should eq(8)

          # Test decrement! with custom amount
          user.decrement!(:posts_count, 3)
          user.posts_count.should eq(5)
          user.reload.posts_count.should eq(5)

          # Test increment without save (just in-memory)
          user.increment(:posts_count, 2)
          user.posts_count.should eq(7)
          # Should NOT be saved to DB yet
          User.find!(user.id).posts_count.should eq(5)
          # Save and verify
          user.save!
          user.reload.posts_count.should eq(7)

          # Test decrement without save
          user.decrement(:posts_count, 2)
          user.posts_count.should eq(5)
          # Should NOT be saved to DB yet
          User.find!(user.id).posts_count.should eq(7)
          # Save and verify
          user.save!
          user.reload.posts_count.should eq(5)

          # Test that increment! bypasses callbacks (no timestamp update)
          original_updated_at = user.updated_at
          sleep 0.01.seconds
          user.increment!(:posts_count)
          user.reload
          user.updated_at.should eq(original_updated_at)
        end
      end

      it "increments and decrements the current in-memory value" do
        temporary do
          reinit_example_models

          user = User.create!(first_name: "John", posts_count: 5)
          user.posts_count = 100

          user.increment(:posts_count, 2)
          user.posts_count.should eq(102)
          User.find!(user.id).posts_count.should eq(5)

          user.decrement(:posts_count, 3)
          user.posts_count.should eq(99)
          User.find!(user.id).posts_count.should eq(5)

          new_user = User.new({id: 10_i64, first_name: "Jane", posts_count: 10})
          new_user.increment(:posts_count, 2)
          new_user.posts_count.should eq(12)
          new_user.increment(:id, 2)
          new_user.id.should eq(12_i64)
          new_user.persisted?.should be_false
        end
      end

      it "increments and decrements in-memory floating-point values" do
        float_data = FloatData.new({price: 1.5_f32, latitude: 2.5_f64})

        float_data.increment(:price, 0.5)
        float_data.price.should eq(2.0_f32)

        float_data.decrement(:latitude, 0.5)
        float_data.latitude.should eq(2.0_f64)
      end

      it "update_all" do
        temporary do
          reinit_example_models

          # Create test users
          user1 = User.create!(id: 1, first_name: "John", active: true)
          user2 = User.create!(id: 2, first_name: "Jane", active: false)
          user3 = User.create!(id: 3, first_name: "Bob", active: false)
          user4 = User.create!(id: 4, first_name: "Alice", active: true)

          # Test basic update_all with single field
          affected = User.query.where { active == false }.update_all(active: true)
          affected.should eq(2)

          # Verify the update worked
          User.query.where { active == true }.count.should eq(4)
          User.query.where { active == false }.count.should eq(0)

          # Test update_all with multiple fields
          affected = User.query.where { id.in?([1, 2]) }.update_all(
            first_name: "Updated",
            last_name: "User"
          )
          affected.should eq(2)

          # Verify multiple field update
          user1.reload
          user2.reload
          user1.first_name.should eq("Updated")
          user1.last_name.should eq("User")
          user2.first_name.should eq("Updated")
          user2.last_name.should eq("User")

          # Test update_all with no matching records
          affected = User.query.where { id == 999 }.update_all(active: false)
          affected.should eq(0)

          # Test update_all with all records
          affected = User.query.update_all(active: false)
          affected.should eq(4)
          User.query.where { active == false }.count.should eq(4)

          # Test that update_all bypasses validations and callbacks
          # (we can verify this by checking it doesn't trigger timestamp updates)
          original_updated_at = user1.reload.updated_at
          sleep 0.01.seconds # Small delay to ensure timestamp would change if it were updated
          User.query.where { id == 1 }.update_all(first_name: "DirectUpdate")
          user1.reload
          user1.first_name.should eq("DirectUpdate")
          # updated_at should NOT change because update_all bypasses the model
          user1.updated_at.should eq(original_updated_at)
        end
      end

      it "returns typed columns from update_all" do
        temporary do
          reinit_example_models

          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: false)

          updated = User.query.where { active == false }.update_all(
            {active: true},
            returning: {id: Int64, first_name: String}
          )

          updated.sort_by(&.[0]).should eq([
            {2, "Jane"},
            {3, "Bob"},
          ])

          User.query.where { active == false }.update_all(
            {active: true},
            returning: {id: Int64, first_name: String}
          ).should be_empty

          fields = {} of String => Lustra::SQL::Any
          fields["active"] = false
          User.query.where { id == 1 }.update_all(
            fields,
            returning: {id: Int64}
          ).should eq([{1_i64}])
        end
      end

      it "fetches rows from a low-level update returning clause" do
        temporary do
          reinit_example_models

          User.create!(id: 1, first_name: "John", active: false)

          returned = [] of Hash(String, Lustra::SQL::Any)
          User.query.where { id == 1 }
            .to_update
            .set(active: true)
            .returning("id, first_name")
            .fetch { |row| returned << row.dup }

          returned.should eq([{
            "id"         => 1_i64,
            "first_name" => "John",
          }])
        end
      end

      it "counter cache functionality" do
        temporary do
          reinit_example_models

          # Create users
          user1 = User.create!(first_name: "John", last_name: "Doe")
          user2 = User.create!(first_name: "Jane", last_name: "Doe")

          user1.posts_count.should eq(0)
          user2.posts_count.should eq(0)

          # Create posts - counter should increment
          post1 = Post.create!(title: "First Post", content: "Content 1", user: user1)
          user1.reload
          user1.posts_count.should eq(1)
          user2.posts_count.should eq(0)

          post2 = Post.create!(title: "Second Post", content: "Content 2", user: user1)
          user1.reload
          user1.posts_count.should eq(2)

          # Destroy a post - counter should decrement
          post1.destroy
          user1.reload
          user1.posts_count.should eq(1)

          # Destroy another post - counter should decrement
          post2.destroy
          user1.reload
          user1.posts_count.should eq(0)
        end
      end

      it "reset_counters method" do
        temporary do
          reinit_example_models

          # Create user
          user = User.create!(first_name: "John", last_name: "Doe")
          user.posts_count.should eq(0)

          # Create posts normally - counter should increment
          post1 = Post.create!(title: "First Post", content: "Content 1", user: user)
          post2 = Post.create!(title: "Second Post", content: "Content 2", user: user)
          user.reload
          user.posts_count.should eq(2)

          # Manually insert a post directly into database (bypassing counter cache)
          Lustra::SQL.execute("INSERT INTO posts (title, content, user_id) VALUES ('Direct Post', 'Direct Content', #{user.id})")

          # Counter is now out of sync
          user.reload
          user.posts_count.should eq(2) # Still shows 2, but there are actually 3 posts

          # Use reset_counters to fix the counter (class method)
          User.reset_counters(user.id, Post)
          user.reload
          user.posts_count.should eq(3) # Now correctly shows 3

          # Test instance method version
          # Manually insert another post to make counter out of sync again
          Lustra::SQL.execute("INSERT INTO posts (title, content, user_id) VALUES ('Another Direct Post', 'Another Direct Content', #{user.id})")

          # Counter is out of sync again
          user.reload
          user.posts_count.should eq(3) # Still shows 3, but there are actually 4 posts

          # Use instance method to fix the counter
          user.reset_counters(Post)
          user.posts_count.should eq(4) # Now correctly shows 4
        end
      end

      it "detect persistence" do
        temporary do
          reinit_example_models
          u = User.new({id: 1}, persisted: true)
          u.persisted?.should be_true
        end
      end

      it "detect change in fields" do
        temporary do
          reinit_example_models
          u = User.new({id: 1})
          u.id = 2
          u.update_h.should eq({"id" => 2})
          u.id = 1
          u.update_h.should eq({} of String => ::DB::Any) # no more change, because id is back to the same !
        end
      end

      it "detect whether a model requires persistence" do
        new_user = User.new({id: 1, first_name: "John"})
        new_user.changed?.should be_false
        new_user.modified?.should be_true

        persisted_user = User.new({id: 1, first_name: "John"}, persisted: true)
        persisted_user.modified?.should be_false

        persisted_user.first_name = "Jane"
        persisted_user.modified?.should be_true

        persisted_user.first_name = "John"
        persisted_user.modified?.should be_false
      end

      it "deal with boolean nullable" do # Specific bug with converter already fixed
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x", active: nil})
          u.save!
          u2 = User.query.first!
          u2.active.should be_nil
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

      it "save the model" do
        temporary do
          reinit_example_models
          u = User.new({id: 1, first_name: "x"})
          u.notification_preferences = JSON.parse("{}")
          u.id = 2 # Force the change!
          u.save!
          User.query.count.should eq 1
        end
      end

      it "converts a hash assigned to a JSON::Any column" do
        temporary do
          reinit_example_models
          preferences = {"topics" => ["crystal", "postgresql"]}

          user = User.create!(first_name: "x", notification_preferences: preferences)

          User.find!(user.id).notification_preferences.should eq(JSON.parse(preferences.to_json))
        end
      end

      it "update the model" do
        temporary do
          reinit_example_models

          u = User.create!({id: 1, first_name: "x"})
          u.update!(first_name: "Malcom")

          User.query.first!.first_name.should eq "Malcom"
        end
      end

      it "reload the model" do
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

      it "import a number of models" do
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

      it "inserts one row without instantiating a model" do
        temporary do
          reinit_example_models

          affected = Tag.insert({name: "crystal"})

          affected.should eq 1
          Tag.query.count.should eq 1
          Tag.query.where(name: "crystal").count.should eq 1
        end
      end

      it "returns zero when insert skips a duplicate" do
        temporary do
          reinit_example_models

          Tag.create!({name: "existing"})

          affected = Tag.insert({name: "existing"}, unique_by: :name)

          affected.should eq 0
          Tag.insert(
            {name: "existing"},
            unique_by: :name,
            returning: {id: Int32, name: String}
          ).should be_nil
          Tag.query.count.should eq 1
        end
      end

      it "returns typed columns from insert" do
        temporary do
          reinit_example_models

          inserted = Tag.insert(
            {name: "crystal"},
            returning: {id: Int32, name: String}
          )

          inserted.should eq({1, "crystal"})
        end
      end

      it "inserts many rows without instantiating models" do
        temporary do
          reinit_example_models

          affected = Tag.insert_all([
            {name: "crystal"},
            {name: "orm"},
          ])

          affected.should eq 2
          Tag.query.count.should eq 2
          Tag.query.where(name: "crystal").count.should eq 1
          Tag.query.where(name: "orm").count.should eq 1
        end
      end

      it "skips duplicates during insert_all by unique key" do
        temporary do
          reinit_example_models

          Tag.create!({name: "existing"})

          inserted = Tag.insert_all([
            {name: "existing"},
            {name: "imported"},
          ], unique_by: :name, returning: {id: Int32, name: String})

          inserted.size.should eq 1
          inserted.first[1].should eq "imported"
          Tag.query.count.should eq 2
          Tag.query.where(name: "existing").count.should eq 1
          Tag.query.where(name: "imported").count.should eq 1
        end
      end

      it "handles empty insert batches" do
        temporary do
          reinit_example_models

          rows = [] of NamedTuple(name: String)

          Tag.insert_all(rows).should eq 0
          Tag.insert_all(
            rows,
            returning: {id: Int32, name: String}
          ).should be_empty
        end
      end

      it "upserts a row by primary key" do
        temporary do
          reinit_example_models

          User.upsert({id: 1, first_name: "John"}).should eq 1

          updated = User.upsert(
            {id: 1, first_name: "Louis"},
            unique_by: [:id],
            returning: {id: Int64, first_name: String}
          )
          updated.should eq({1_i64, "Louis"})

          User.query.count.should eq 1
          User.query.find!(1).first_name.should eq "Louis"
        end
      end

      it "upserts many rows by primary key" do
        temporary do
          reinit_example_models

          User.create!({id: 1, first_name: "John"})

          affected = User.upsert_all([
            {id: 1, first_name: "Louis"},
            {id: 2, first_name: "Jane"},
          ])

          affected.should eq 2
          User.query.count.should eq 2
          User.query.find!(1).first_name.should eq "Louis"
          User.query.find!(2).first_name.should eq "Jane"
        end
      end

      it "skips duplicates during upsert" do
        temporary do
          reinit_example_models

          User.create!({id: 1, first_name: "John"})

          User.upsert({id: 1, first_name: "Louis"}, on_duplicate: :skip).should eq 0
          User.upsert(
            {id: 1, first_name: "Louis"},
            on_duplicate: :skip,
            returning: {id: Int64, first_name: String}
          ).should be_nil

          users = User.upsert_all([
            {id: 1, first_name: "Ignored"},
            {id: 2, first_name: "Jane"},
          ], on_duplicate: :skip, returning: {id: Int64, first_name: String})

          users.should eq([{2_i64, "Jane"}])
          User.query.count.should eq 2
          User.query.find!(1).first_name.should eq "John"
          User.query.find!(2).first_name.should eq "Jane"
        end
      end

      it "skips duplicates by a non-primary unique key during upsert" do
        temporary do
          reinit_example_models

          Tag.create!({name: "existing"})

          tags = Tag.upsert_all([
            {name: "existing"},
            {name: "imported"},
          ], unique_by: :name, on_duplicate: :skip, returning: {id: Int32, name: String})

          tags.size.should eq 1
          tags.first[1].should eq "imported"
          Tag.query.count.should eq 2
          Tag.query.where(name: "existing").count.should eq 1
          Tag.query.where(name: "imported").count.should eq 1
        end
      end

      it "upserts only selected columns" do
        temporary do
          reinit_example_models

          User.create!({id: 1, first_name: "John", last_name: "Doe"})

          User.upsert(
            {id: 1, first_name: "Louis", last_name: "Ignored"},
            update_only: ["first_name"]
          )

          user = User.query.find!(1)
          user.first_name.should eq "Louis"
          user.last_name.should eq "Doe"
        end
      end

      it "upserts with a custom conflict update" do
        temporary do
          reinit_example_models

          User.upsert({id: 1, first_name: "John", posts_count: 2}).should eq 1

          affected = User.upsert(
            {id: 1, first_name: "Ignored", posts_count: 3},
            on_duplicate: Lustra::SQL.unsafe(%("posts_count" = "users"."posts_count" + excluded."posts_count"))
          )

          affected.should eq 1
          user = User.query.find!(1)
          user.first_name.should eq "John"
          user.posts_count.should eq 5
        end
      end

      it "handles empty upsert batches" do
        rows = [] of NamedTuple(id: Int64, first_name: String)

        User.upsert_all(rows).should eq 0
        User.upsert_all(
          rows,
          returning: {id: Int64, first_name: String}
        ).should be_empty
      end

      it "rejects update_only with a custom conflict update" do
        expect_raises(ArgumentError, /mutually exclusive/) do
          User.upsert(
            {id: 1, first_name: "John"},
            on_duplicate: Lustra::SQL.unsafe(%("first_name" = excluded."first_name")),
            update_only: [:first_name]
          )
        end
      end

      it "save with conflict resolution" do
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
          u2.save! do |qry|
            qry.on_conflict("(id)").do_update do |up|
              up.set("first_name = excluded.first_name")
                .where { users.id == excluded.id }
            end
          end

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
          p.save.should be_false # < Must save the user first. but user is missing is first name !

          p.user.first_name = "I fix the issue!" # < Fix the issue

          p.save.should be_true # Should save now

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

      it "save persisted model" do
        temporary do
          reinit_example_models
          u = User.new
          u.persisted?.should be_false
          u.first_name = "hello"
          u.last_name = "world"
          u.save!

          u.persisted?.should be_true
          u.id.should eq 1
        end
      end

      it "use set to setup multiple fields at once" do
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
          u.set(JSON.parse(%({"first_name": "hello", "last_name": "world"})))
          u.save!
          u.persisted?.should be_true
          u.first_name.should eq "hello"
          u.changed?.should be_false
        end
      end

      it "load models" do
        temporary do
          reinit_example_models
          User.create
          User.query.each do |u|
            u.id.should_not be_nil
          end
        end
      end

      it "read through cursor" do
        temporary do
          reinit_example_models
          User.create
          User.query.each_with_cursor(batch: 50) do |u|
            u.id.should_not be_nil
          end
        end
      end

      it "fetch computed column" do
        temporary do
          reinit_example_models
          User.create({first_name: "a", last_name: "b"})

          u = User.query.select({full_name: "first_name || ' ' || last_name"}).first!(fetch_columns: true)
          u["full_name"].should eq "a b"
        end
      end

      it "create a model using virtual fields" do
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
          u.id.should_not be_nil

          u = User.find! u.id
          u.created_at.to_unix.should be_close(now.to_unix, 1)
        end
      end

      it "count using offset and limit" do
        temporary do
          reinit_example_models

          9.times do |x|
            User.create!({first_name: "user#{x}"})
          end

          User.query.limit(5).count.should eq(5)
          User.query.limit(5).offset(5).count(Int32).should eq(4)
        end
      end

      it "count using group_by" do
        temporary do
          reinit_example_models
          9.times do |x|
            User.create!({first_name: "user#{x}", last_name: "Doe"})
          end

          User.query.group_by("last_name").count.should eq(1)
        end
      end

      it "find_or_create" do
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

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.find!(1)
          end
        end
      end

      it "set back a field to nil" do
        temporary do
          reinit_example_models

          u = User.create({first_name: "Rudolf"})

          ui = UserInfo.create({registration_number: 123, user_id: u.id})

          ui.user_id = nil # Remove user_id, just to see what's going on !
          ui.save!
        end
      end

      it "read and write jsonb" do
        temporary do
          reinit_example_models
          u = User.new

          u.first_name = "Yacine"
          u.last_name = "Petitprez"
          u.save.should be_true

          u.notification_preferences = JSON.parse(JSON.build do |json|
            json.object do
              json.field "email", true
            end
          end)
          u.save.should be_true
          u.persisted?.should be_true
        end
      end

      it "query the last model" do
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

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.first!
          end
        end
      end

      it "raises a RecordNotFoundError without last" do
        temporary do
          reinit_example_models

          expect_raises(Lustra::SQL::RecordNotFoundError) do
            User.query.last!
          end
        end
      end

      it "delete a model" do
        temporary do
          reinit_example_models

          User.create({first_name: "Malcom", last_name: "X"})

          u = User.new
          u.first_name = "LeBron"
          u.last_name = "James"
          u.save.should be_true

          User.query.count.should eq 2
          u.persisted?.should be_true

          u.delete.should be_true
          u.persisted?.should be_false
          User.query.count.should eq 1
        end
      end

      context "delete vs destroy" do
        it "delete removes record without callbacks" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})
            user_id = user.id

            # Track if callback was called
            callback_called = false
            User.before(:destroy) do |_|
              callback_called = true
            end

            # delete should NOT trigger callbacks
            user.delete.should be_true
            callback_called.should be_false

            # User should be gone from database
            User.find(user_id).should be_nil
            user.persisted?.should be_false
          end
        end

        it "destroy removes record with callbacks" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})
            user_id = user.id

            # Track if callback was called
            callback_called = false
            User.before(:destroy) do |_|
              callback_called = true
            end

            # destroy SHOULD trigger callbacks
            user.destroy.should be_true
            callback_called.should be_true

            # User should be gone from database
            User.find(user_id).should be_nil
            user.persisted?.should be_false
          end
        end

        it "delete_all bulk deletes without callbacks" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John", last_name: "Doe"})
            User.create!({first_name: "Jane", last_name: "Doe"})
            User.create!({first_name: "Bob", last_name: "Smith"})

            # Track if callback was called
            callback_count = 0
            User.before(:destroy) do |_|
              callback_count += 1
            end

            # delete_all should NOT trigger callbacks
            User.query.where(last_name: "Doe").delete_all.should eq(2)
            callback_count.should eq(0)

            # Only Bob should remain
            User.query.count.should eq(1)
            User.query.first!.first_name.should eq("Bob")
          end
        end

        it "returns typed columns from delete_all" do
          temporary do
            reinit_example_models

            User.create!(id: 1, first_name: "John", last_name: "Doe")
            User.create!(id: 2, first_name: "Jane", last_name: "Doe")
            User.create!(id: 3, first_name: "Bob", last_name: "Smith")

            deleted = User.query.where(last_name: "Doe").delete_all(
              returning: {id: Int64, first_name: String}
            )

            deleted.sort_by(&.[0]).should eq([
              {1_i64, "John"},
              {2_i64, "Jane"},
            ])

            User.query.where(last_name: "Doe").delete_all(
              returning: {id: Int64, first_name: String}
            ).should be_empty
          end
        end

        it "fetches rows from a low-level delete returning clause" do
          temporary do
            reinit_example_models

            User.create!(id: 1, first_name: "John")

            returned = [] of Hash(String, Lustra::SQL::Any)
            User.query.where { id == 1 }
              .to_delete
              .returning("id, first_name")
              .fetch { |row| returned << row.dup }

            returned.should eq([{
              "id"         => 1_i64,
              "first_name" => "John",
            }])
          end
        end

        it "destroy_all loads and destroys with callbacks" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John", last_name: "Doe"})
            User.create!({first_name: "Jane", last_name: "Doe"})
            User.create!({first_name: "Bob", last_name: "Smith"})

            # Track if callback was called
            callback_count = 0
            User.before(:destroy) do |_|
              callback_count += 1
            end

            # destroy_all SHOULD trigger callbacks for each record
            User.query.where(last_name: "Doe").destroy_all
            callback_count.should eq(2)

            # Only Bob should remain
            User.query.count.should eq(1)
            User.query.first!.first_name.should eq("Bob")
          end
        end
      end

      context "ids method" do
        it "returns array of primary key values" do
          temporary do
            reinit_example_models

            user1 = User.create!({first_name: "John"})
            user2 = User.create!({first_name: "Jane"})
            user3 = User.create!({first_name: "Bob"})

            # Get all IDs
            all_ids = User.query.ids
            all_ids.should eq([user1.id, user2.id, user3.id])
          end
        end

        it "works with where clauses" do
          temporary do
            reinit_example_models

            user1 = User.create!({first_name: "John", last_name: "Doe"})
            user2 = User.create!({first_name: "Jane", last_name: "Doe"})
            user3 = User.create!({first_name: "Bob", last_name: "Smith"})

            # Get IDs with filter
            doe_ids = User.query.where(last_name: "Doe").ids
            doe_ids.should eq([user1.id, user2.id])
          end
        end

        it "returns empty array when no records" do
          temporary do
            reinit_example_models

            User.query.where(first_name: "NonExistent").ids.should be_empty
          end
        end

        it "is chainable with other query methods" do
          temporary do
            reinit_example_models

            5.times { |i| User.create!({first_name: "User#{i}"}) }

            # Chain with limit and order
            ids = User.query.order_by(:id, :desc).limit(3).ids
            ids.size.should eq(3)
          end
        end
      end

      context "explain and explain_analyze" do
        it "explain returns query execution plan" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John"})
            User.create!({first_name: "Jane"})

            plan = User.query.where { first_name == "John" }.explain

            # Verify it returns a non-empty string with EXPLAIN output
            plan.should_not be_empty
            # Should contain some kind of scan or plan node
            (plan.includes?("Scan") || plan.includes?("Index") || plan.includes?("cost")).should be_true
          end
        end

        it "explain works with complex queries" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John"})
            Post.create!({title: "Post 1", user: user})

            plan = User.query.join(:posts).where { first_name == "John" }.explain

            plan.should_not be_empty
            # Should mention tables or have execution plan
            plan.should_not be_empty
          end
        end

        it "explain_analyze returns actual execution statistics" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John"})
            User.create!({first_name: "Jane"})

            plan = User.query.where { first_name == "John" }.explain_analyze

            # Verify it contains actual execution details
            plan.should_not be_empty
            (plan.includes?("actual time") || plan.includes?("rows=")).should be_true
          end
        end

        it "explain does not execute the query" do
          temporary do
            reinit_example_models

            # explain should not actually delete anything
            plan = User.query.where { first_name == "Test" }.to_delete.explain

            plan.should_not be_empty
            (plan.includes?("Delete") || plan.includes?("Scan")).should be_true
          end
        end

        it "explain_analyze does execute the query" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "Test"})
            initial_count = User.query.count

            # explain_analyze will actually execute the delete
            # So we wrap in transaction to test safely
            Lustra::SQL.transaction do
              plan = User.query.where(first_name: "Test").to_delete.explain_analyze
              plan.should contain("actual time")

              # Rollback to prevent actual deletion in test
              raise Lustra::SQL::RollbackError.new
            end

            # Verify rollback worked
            User.query.count.should eq(initial_count)
          end
        end

        it "safe pattern for explain_analyze with write operations" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John", last_name: "Doe"})
            User.create!({first_name: "Jane", last_name: "Smith"})
            initial_count = User.query.count

            # Safe pattern: Wrap in transaction and rollback
            plan = ""
            Lustra::SQL.transaction do
              # This will actually UPDATE the records
              plan = User.query.where(last_name: "Doe").to_update.set(active: true).explain_analyze

              # Force rollback to undo the changes
              raise Lustra::SQL::RollbackError.new
            end

            # Verify the plan was captured
            plan.should_not be_empty
            (plan.includes?("actual time") || plan.includes?("Update")).should be_true

            # Verify no data was permanently modified
            User.query.count.should eq(initial_count)
            User.query.where(active: true).count.should eq(0)
          end
        end

        it "explain_analyze with SELECT is safe to use directly" do
          temporary do
            reinit_example_models

            User.create!({first_name: "John"})
            User.create!({first_name: "Jane"})

            # For SELECT queries, explain_analyze is safe - doesn't modify data
            plan = User.query.where { first_name == "John" }.explain_analyze

            plan.should_not be_empty
            plan.should contain("actual time")

            # Data is unchanged
            User.query.count.should eq(2)
          end
        end
      end

      context "attribute change tracking" do
        it "preserves pending edits when increment! writes another column" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John", posts_count: 5)
            user.first_name = "Jane"

            user.increment!(:posts_count)
            user.posts_count_column.changed?.should be_false
            User.find!(user.id).posts_count.should eq(6)
            User.find!(user.id).first_name.should eq("John")
            pending_change = user.first_name_column.change

            user.save!

            User.find!(user.id).first_name.should eq("Jane")
            pending_change.should eq({"John", "Jane"})
            user.reload.posts_count.should eq(6)
          end
        end

        it "preserves pending edits when update_column writes another column" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John", posts_count: 5)
            user.first_name = "Jane"

            user.update_column(:posts_count, 10)
            user.posts_count_column.changed?.should be_false
            User.find!(user.id).posts_count.should eq(10)
            User.find!(user.id).first_name.should eq("John")
            pending_change = user.first_name_column.change

            user.save!

            User.find!(user.id).first_name.should eq("Jane")
            pending_change.should eq({"John", "Jane"})
            user.reload.posts_count.should eq(10)
          end
        end

        it "preserves pending edits when update_columns writes other columns" do
          temporary do
            reinit_example_models

            user = User.create!(first_name: "John", posts_count: 5, active: false)
            user.first_name = "Jane"

            user.update_columns(posts_count: 10, active: true)
            user.posts_count_column.changed?.should be_false
            user.active_column.changed?.should be_false
            persisted = User.find!(user.id)
            persisted.posts_count.should eq(10)
            persisted.active.should be_true
            persisted.first_name.should eq("John")
            pending_change = user.first_name_column.change

            user.save!

            User.find!(user.id).first_name.should eq("Jane")
            pending_change.should eq({"John", "Jane"})
            user.reload.posts_count.should eq(10)
            user.active.should be_true
          end
        end

        it "returns change tuple with column.change" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})

            # No changes yet
            user.first_name_column.change.should be_nil
            user.last_name_column.change.should be_nil

            # Make change
            user.first_name = "Jane"

            # Get change tuple {old, new}
            if change = user.first_name_column.change
              change[0].should eq("John")
              change[1].should eq("Jane")
            else
              fail "Expected first_name_column.change to return a tuple"
            end

            # Unchanged attribute returns nil
            user.last_name_column.change.should be_nil
          end
        end

        it "returns all changes with changes method" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})

            # No changes initially
            user.changes.should eq({} of String => Tuple(Lustra::SQL::Any, Lustra::SQL::Any))

            # Make multiple changes
            user.first_name = "Jane"
            user.last_name = "Smith"

            # Get all changes
            changes = user.changes
            changes.size.should eq(2)
            changes["first_name"].should eq({"John", "Jane"})
            changes["last_name"].should eq({"Doe", "Smith"})
          end
        end

        it "returns changed attribute names with changed method" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})

            # No changes initially
            user.changed.should eq([] of String)

            # Make changes
            user.first_name = "Jane"
            user.last_name = "Smith"

            # Get list of changed attributes
            user.changed.should contain("first_name")
            user.changed.should contain("last_name")
            user.changed.size.should eq(2)
          end
        end

        it "resets tracking after save" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_name: "Doe"})

            user.first_name = "Jane"
            user.first_name_column.changed?.should be_true

            user.save!

            # After save, changes are cleared
            user.first_name_column.changed?.should be_false
            user.changes.should eq({} of String => Tuple(Lustra::SQL::Any, Lustra::SQL::Any))
            user.changed.should eq([] of String)
          end
        end

        it "can be used in callbacks for conditional logic" do
          temporary do
            reinit_example_models

            # Track what happened in callback
            last_name_changed_in_callback = false
            first_name_changed_in_callback = false

            User.before(:save) do |model|
              user = model.as(User)

              # Check if specific field changed
              if user.last_name_column.changed?
                last_name_changed_in_callback = true
              end

              # Get the actual change
              if change = user.first_name_column.change
                old_name, new_name = change
                first_name_changed_in_callback = true if old_name != new_name
              end
            end

            user = User.create!({first_name: "John", last_name: "Doe"})

            # Change last_name only
            user.last_name = "Smith"
            user.save!

            last_name_changed_in_callback.should be_true
            first_name_changed_in_callback.should be_false
          end
        end

        it "shows all changes for auditing in callbacks" do
          temporary do
            reinit_example_models

            audit_log = {} of String => Tuple(Lustra::SQL::Any, Lustra::SQL::Any)

            User.before(:save) do |model|
              user = model.as(User)
              audit_log = user.changes
            end

            user = User.create!({first_name: "John", last_name: "Doe"})
            user.first_name = "Jane"
            user.last_name = "Smith"
            user.save!

            # Callback captured all changes
            audit_log.size.should eq(2)
            audit_log["first_name"].should eq({"John", "Jane"})
            audit_log["last_name"].should eq({"Doe", "Smith"})
          end
        end
      end

      context "touch" do
        it "updates updated_at timestamp" do
          temporary do
            reinit_example_models

            c = Category.create!({name: "Nature"})
            updated_at = c.updated_at
            c.touch
            c.updated_at.should_not eq(updated_at)
          end
        end

        it "updates specific column" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_comment_at: 1.minutes.ago})
            updated_at = user.updated_at
            last_comment_at = user.last_comment_at

            user.touch(:last_comment_at)
            user.updated_at.should_not eq(updated_at)
            user.last_comment_at.should_not eq(last_comment_at)
          end
        end

        it "updates specific column with time" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_comment_at: 1.minutes.ago})

            time = 30.seconds.ago
            user.touch(:last_comment_at, time)
            user.updated_at.should eq(time)
          end
        end

        it "updates multiple columns" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_comment_at: 1.minutes.ago})
            updated_at = user.updated_at
            last_comment_at = user.last_comment_at

            user.touch([:last_comment_at, :updated_at])
            user.touch(:last_comment_at, :updated_at)
            user.updated_at.should_not eq(updated_at)
            user.last_comment_at.should_not eq(last_comment_at)
          end
        end

        it "updates multiple columns with time" do
          temporary do
            reinit_example_models

            user = User.create!({first_name: "John", last_comment_at: 1.minutes.ago})
            time = 30.seconds.ago

            user.touch(:last_comment_at, :updated_at, time: time)
            user.updated_at.should eq(time)
            user.last_comment_at.should eq(time)
          end
        end

        it "bypasses validations and callbacks" do
          temporary do
            reinit_example_models

            # Create a user with valid data
            user = User.create!({first_name: "John", last_name: "Doe"})
            user_id = user.id
            original_updated_at = user.updated_at

            # Make the user invalid by setting first_name to empty string using direct SQL
            Lustra::SQL::ConnectionPool.with_connection("default") do |cnx|
              cnx.exec("UPDATE users SET first_name = '' WHERE id = $1", user_id)
            end

            # Reload the user - it now has invalid data
            user = User.find!(user_id)
            user.first_name.should eq("")

            # Attempting to save! would fail validation, but touch should work
            # because it bypasses validations
            user.touch

            # Verify updated_at was changed from the original
            user.updated_at.should_not eq(original_updated_at)
          end
        end

        it "raises error when model is not persisted" do
          temporary do
            reinit_example_models

            user = User.new({first_name: "John", last_name: "Doe"})
            user.persisted?.should be_false

            expect_raises(Lustra::Model::Error, "Model must be persisted before touching") do
              user.touch
            end
          end
        end
      end
    end

    it "load a column of type Array" do
      temporary do
        reinit_example_models

        u = User.create!({first_name: "John"})
        p = Post.create!({title: "A post", user_id: u.id})

        p.tags_list = ["a", "b", "c"]
        p.flags = [11_234_212_343_543_i64, 11_234_212_343_543_i64, -12_928_394_059_603_i64, 12_038_493_029_484_i64]
        p.save!

        p = Post.query.first!
        p.tags_list.should eq ["a", "b", "c"]
        p.flags.should eq [11_234_212_343_543_i64, 11_234_212_343_543_i64, -12_928_394_059_603_i64, 12_038_493_029_484_i64]

        # Test insertion of empty array
        Post.create!({title: "A post", user_id: u.id, tags_list: [] of String})
      end
    end

    it "queries array columns with PostgreSQL array operators" do
      temporary do
        reinit_example_models

        user = User.create!({first_name: "John"})
        Post.create!({title: "Crystal ORM", user_id: user.id, tags_list: ["crystal", "orm"]})
        Post.create!({title: "ORM only", user_id: user.id, tags_list: ["orm", "orm"]})
        Post.create!({title: "PostgreSQL", user_id: user.id, tags_list: ["postgres", "sql"]})

        Post.query
          .where { raw("? = ANY(tags_list)", "orm") }
          .order_by(:title)
          .pluck_col("title", String)
          .should eq(["Crystal ORM", "ORM only"])

        Post.query
          .where { raw("? = ALL(tags_list)", "orm") }
          .pluck_col("title", String)
          .should eq(["ORM only"])

        Post.query
          .where { raw("tags_list @> ARRAY[?]::text[]", "crystal") }
          .pluck_col("title", String)
          .should eq(["Crystal ORM"])

        Post.query
          .where { raw("tags_list <@ ARRAY[?, ?]::text[]", "orm", "crystal") }
          .order_by(:title)
          .pluck_col("title", String)
          .should eq(["Crystal ORM", "ORM only"])

        Post.query
          .where { raw("tags_list && ARRAY[?, ?]::text[]", "sql", "crystal") }
          .order_by(:title)
          .pluck_col("title", String)
          .should eq(["Crystal ORM", "PostgreSQL"])
      end
    end

    context "with self-reference and has_many through" do
      it "assign self-reference has_many through" do
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

      it "create self-reference has_many through" do
        temporary do
          reinit_example_models

          user1 = User.create!({first_name: "John"})
          user2 = User.create!({first_name: "Jane"})

          Relationship.create!({master: user1, dependency: user2})

          user1.dependencies.count.should eq(1)
          user2.dependents.count.should eq(1)
        end
      end

      it "unlink self-reference has_many through" do
        temporary do
          reinit_example_models

          user1 = User.create!({first_name: "John"})
          user2 = User.create!({first_name: "Jane"})

          user1.dependencies << user2

          user1.dependencies.count.should eq(1)
          user2.dependents.count.should eq(1)

          user1.dependencies.unlink(User.query.find_by!({first_name: "Jane"}))

          user1.dependencies.count.should eq(0)
          user2.dependents.count.should eq(0)
        end
      end
    end

    context "with has_many through relation" do
      it "query has_many through" do
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

          p.tags.count.should eq(0)

          p.tags << Tag.new({name: "Awesome"})
          p.tags << Tag.new({name: "Why not"})

          p.tags.count.should eq(2)
          p.tags.first!.name.should eq("Awesome")
          p.tags.offset(1).first!.name.should eq("Why not")
        end
      end

      it "unlink has_many through" do
        temporary do
          reinit_example_models

          u = User.create!({first_name: "John"})
          c = Category.create!({name: "Nature"})
          p = Post.create!({title: "Post about Poneys", user_id: u.id, category_id: c.id})

          p.tags << Tag.new({name: "Awesome"})
          p.tags << Tag.new({name: "Why not"})

          p.tags.count.should eq(2)
          p.tags.unlink(Tag.query.find_by!({name: "Awesome"}))
          p.tags.count.should eq(1)
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

      it "pull the next 5 users from page 2" do
        temporary do
          reinit_example_models

          15.times do |x|
            User.create!({first_name: "user#{x}"})
          end

          users = User.query.paginate(page: 2, per_page: 5)
          users.map(&.first_name).should eq ["user5", "user6", "user7", "user8", "user9"]
          users.total_entries.should eq 15
          users.total_pages.should eq 3
          users.current_page.should eq 2
          users.per_page.should eq 5
        end
      end

      it "export to json" do
        temporary do
          reinit_example_models
          u = User.new({first_name: "Hello", last_name: "World"})
          u.to_json.should eq %({"first_name":"Hello","last_name":"World"})

          u.to_json(emit_nulls: true).should eq(
            %({"id":null,"first_name":"Hello","last_name":"World","middle_name":null,"gender":null,"active":null,"posts_count":null,"notification_preferences":null,"last_comment_at":null,"updated_at":null,"created_at":null}))
        end
      end

      it "paginate with where clause" do
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

    describe "Lustra::Model::JSONDeserialize" do
      it "create a model json IO" do
        user_body = {first_name: "foo"}
        io = IO::Memory.new user_body.to_json
        user = User.from_json(io)
        user.first_name.should eq user_body["first_name"]
      end

      it "create a new model instance from json" do
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

    describe "Lustra::Model::HasColumns mass_assign" do
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
          data.num2.should eq(BigDecimal.new("42424224.01234568"))
          data.num3.should eq(BigDecimal.new(BigInt.new("-1029387192083710928371092837019283701982370918237".to_big_i), 40).trunc)

          # Lustra::SQL::Error:numeric field overflow
          data.num4 = BigDecimal.new(BigInt.new("-1029387192083710928371092837019283701982370918237".to_big_i), 40)

          expect_raises(Lustra::SQL::Error) do
            data.save!
          end
        end
      end
    end
  end
end
