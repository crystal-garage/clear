require "../spec_helper"
require "../data/example_models"

module WhereSpec
  describe "execution of WHERE operators" do
    it "comparison operators" do
      temporary do
        reinit_example_models

        User.create!(first_name: "Alice", posts_count: 5)
        User.create!(first_name: "Bob", posts_count: 10)
        User.create!(first_name: "Charlie", posts_count: 15)
        User.create!(first_name: "Diana", posts_count: 20)

        # Test > operator
        users = User.query.where { posts_count > 10 }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")

        # Test >= operator
        users = User.query.where { posts_count >= 10 }
        users.size.should eq(3)
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")

        # Test < operator
        users = User.query.where { posts_count < 15 }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")

        # Test <= operator
        users = User.query.where { posts_count <= 15 }
        users.size.should eq(3)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")

        # Test != operator
        users = User.query.where { posts_count != 10 }
        users.size.should eq(3)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")
        users.map(&.first_name).should_not contain("Bob")
      end
    end

    it "arithmetic operators" do
      temporary do
        reinit_example_models

        # Create test users with different scores
        User.create!(first_name: "Alice", posts_count: 10)
        User.create!(first_name: "Bob", posts_count: 15)
        User.create!(first_name: "Charlie", posts_count: 20)

        # Test + operator
        users = User.query.where { posts_count + 5 == 15 }
        users.size.should eq(1)
        users.first!.first_name.should eq("Alice") # 10 + 5 = 15

        # Test - operator
        users = User.query.where { posts_count - 5 == 5 }
        users.size.should eq(1)
        users.first!.first_name.should eq("Alice") # 10 - 5 = 5

        # Test * operator
        users = User.query.where { posts_count * 2 == 40 }
        users.size.should eq(1)
        users.first!.first_name.should eq("Charlie") # 20 * 2 = 40

        # Test / operator
        users = User.query.where { posts_count / 2 == 7 }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob") # 15 / 2 = 7 (integer division)
      end
    end

    it "logical operators" do
      temporary do
        reinit_example_models

        # Create test users
        User.create!(first_name: "Alice", active: true, posts_count: 5)
        User.create!(first_name: "Bob", active: false, posts_count: 10)
        User.create!(first_name: "Charlie", active: true, posts_count: 15)
        User.create!(first_name: "Diana", active: false, posts_count: 20)

        # Test & (AND) operator
        users = User.query.where { (active.true? & (posts_count > 10)) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Charlie")

        # Test | (OR) operator
        users = User.query.where { (active.false? | (posts_count < 10)) }
        users.size.should eq(3)
        users.map(&.first_name).should contain("Alice") # active: true, posts_count: 5
        users.map(&.first_name).should contain("Bob")   # active: false
        users.map(&.first_name).should contain("Diana") # active: false
        users.map(&.first_name).should_not contain("Charlie")
      end
    end

    it "pattern matching operators" do
      temporary do
        reinit_example_models

        # Create test users with email-like names
        User.create!(first_name: "john@gmail.com")
        User.create!(first_name: "jane@yahoo.com")
        User.create!(first_name: "bob@company.org")
        User.create!(first_name: "alice@GMAIL.COM")

        # Test like operator (case sensitive)
        users = User.query.where { first_name.like("%@gmail.com") }
        users.size.should eq(1)
        users.first!.first_name.should eq("john@gmail.com")

        # Test ilike operator (case insensitive)
        users = User.query.where { first_name.ilike("%@gmail.com") }
        users.size.should eq(2)
        users.map(&.first_name).should contain("john@gmail.com")
        users.map(&.first_name).should contain("alice@GMAIL.COM")

        # Test like with different patterns
        users = User.query.where { first_name.like("j%") }
        users.size.should eq(2)
        users.map(&.first_name).should contain("john@gmail.com")
        users.map(&.first_name).should contain("jane@yahoo.com")
      end
    end

    it "regex operators" do
      temporary do
        reinit_example_models

        # Create test users with email-like names
        User.create!(first_name: "john@gmail.com")
        User.create!(first_name: "jane@yahoo.com")
        User.create!(first_name: "bob@company.org")
        User.create!(first_name: "alice123@gmail.com")

        # Test =~ operator with regex (case sensitive)
        users = User.query.where { first_name =~ /^[a-z]+@gmail\.com$/ }
        users.size.should eq(1)
        users.first!.first_name.should eq("john@gmail.com")

        # Test =~ operator with regex (case insensitive)
        users = User.query.where { first_name =~ /^[a-z0-9]+@gmail\.com$/i }
        users.size.should eq(2)
        users.map(&.first_name).should contain("john@gmail.com")
        users.map(&.first_name).should contain("alice123@gmail.com")

        # Test !~ operator (does not match)
        users = User.query.where { first_name !~ /@gmail\.com$/ }
        users.size.should eq(2)
        users.map(&.first_name).should contain("jane@yahoo.com")
        users.map(&.first_name).should contain("bob@company.org")
      end
    end

    it "membership operators" do
      temporary do
        reinit_example_models

        # Create test users
        User.create!(first_name: "Alice", posts_count: 5)
        User.create!(first_name: "Bob", posts_count: 10)
        User.create!(first_name: "Charlie", posts_count: 15)
        User.create!(first_name: "Diana", posts_count: 20)

        # Test in? with array
        users = User.query.where { posts_count.in?([5, 15, 25]) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Charlie")

        # Test in? with range
        users = User.query.where { posts_count.in?(10..15) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")

        # Test in? with exclusive range
        users = User.query.where { posts_count.in?(10...15) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob")

        # Test in? with endless range
        users = User.query.where { posts_count.in?(15..) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")

        # Test in? with beginless range (inclusive)
        users = User.query.where { posts_count.in?(..10) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")

        # Test in? with beginless range (exclusive)
        users = User.query.where { posts_count.in?(...10) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Alice")

        # Test in? with full range (...) - matches all values
        users = User.query.where { posts_count.in?(...) }
        users.size.should eq(4)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")

        # Test Range(Time, Time) support
        base_time = Time.utc(2025, 1, 1, 12, 0, 0)

        User.query.delete_all

        user1 = User.create!(first_name: "Alice", posts_count: 5)
        user1.update_column(:created_at, base_time)

        user2 = User.create!(first_name: "Bob", posts_count: 10)
        user2.update_column(:created_at, base_time + 1.hour)

        user3 = User.create!(first_name: "Charlie", posts_count: 15)
        user3.update_column(:created_at, base_time + 2.hours)

        user4 = User.create!(first_name: "Diana", posts_count: 20)
        user4.update_column(:created_at, base_time + 3.hours)

        # Test in? with time range
        time_start = base_time + 1.hour
        time_end = base_time + 2.hours
        users = User.query.where { created_at.in?(time_start..time_end) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")

        # Test in? with exclusive time range
        users = User.query.where { created_at.in?(time_start...time_end) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob")

        # Test in? with endless time range
        users = User.query.where { created_at.in?((base_time + 2.hours)..) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should contain("Diana")

        # Test in? with beginless time range (inclusive)
        users = User.query.where { created_at.in?(..(base_time + 1.hour)) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")

        # Test in? with beginless time range (exclusive)
        users = User.query.where { created_at.in?(...(base_time + 1.hour)) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Alice")
      end
    end

    it "between operator" do
      temporary do
        reinit_example_models

        # Create test users
        User.create!(first_name: "Alice", posts_count: 5)
        User.create!(first_name: "Bob", posts_count: 10)
        User.create!(first_name: "Charlie", posts_count: 15)
        User.create!(first_name: "Diana", posts_count: 20)

        # Test between operator
        users = User.query.where { posts_count.between?(10, 15) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")

        # Test between with edge cases
        users = User.query.where { posts_count.between?(5, 5) }
        users.size.should eq(1)
        users.first!.first_name.should eq("Alice")
      end
    end

    it "unary operators" do
      temporary do
        reinit_example_models

        # Create test users
        User.create!(first_name: "Alice", active: true)
        User.create!(first_name: "Bob", active: false)
        User.create!(first_name: "Charlie", active: true)

        # Test unary NOT operator
        users = User.query.where { ~active }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob")

        # Test unary NOT with complex expressions
        users = User.query.where { ~(posts_count > 0) }
        users.size.should eq(3) # All users have posts_count = 0 (default)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Bob")
        users.map(&.first_name).should contain("Charlie")
      end
    end

    it "NULL handling" do
      temporary do
        reinit_example_models

        # Create test users with some NULL values
        User.create!(first_name: "Alice", last_name: "Smith")
        User.create!(first_name: "Bob", last_name: nil)
        User.create!(first_name: "Charlie", last_name: "Johnson")

        # Test == nil (IS NULL)
        users = User.query.where { last_name == nil }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob")

        # Test != nil (IS NOT NULL)
        users = User.query.where { last_name != nil }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should_not contain("Bob")

        # Test null? (IS NULL)
        users = User.query.where { last_name.null? }
        users.size.should eq(1)
        users.first!.first_name.should eq("Bob")

        # Test ~null? (IS NOT NULL)
        users = User.query.where { ~(last_name.null?) }
        users.size.should eq(2)
        users.map(&.first_name).should contain("Alice")
        users.map(&.first_name).should contain("Charlie")
        users.map(&.first_name).should_not contain("Bob")
      end
    end

    it "complex combinations of operators" do
      temporary do
        reinit_example_models

        # Create test users with various attributes
        User.create!(first_name: "alice@gmail.com", active: true, posts_count: 15)
        User.create!(first_name: "bob@yahoo.com", active: false, posts_count: 5)
        User.create!(first_name: "charlie@gmail.com", active: true, posts_count: 25)
        User.create!(first_name: "diana@company.org", active: true, posts_count: 10)

        # Complex query: active users with gmail addresses and high post counts
        users = User.query.where do
          (active.true?) &
            (first_name.ilike("%@gmail.com")) &
            (posts_count > 10)
        end

        users.size.should eq(2)
        users.map(&.first_name).should contain("alice@gmail.com")
        users.map(&.first_name).should contain("charlie@gmail.com")

        # Complex query with arithmetic and regex
        users = User.query.where do
          (posts_count * 2 > 20) &
            (first_name =~ /^[a-z0-9]+@/)
        end

        users.size.should eq(2)
        users.map(&.first_name).should contain("alice@gmail.com")   # 15 * 2 = 30 > 20
        users.map(&.first_name).should contain("charlie@gmail.com") # 25 * 2 = 50 > 20
      end
    end

    describe "WHERE clauses with JOINs" do
      it "WHERE with INNER JOIN" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John", active: true)
          user2 = User.create!(first_name: "Jane", active: false)
          user3 = User.create!(first_name: "Bob", active: true)

          post1 = Post.create!(title: "John's Post", user_id: user1.id, published: true)
          post2 = Post.create!(title: "Jane's Post", user_id: user2.id, published: true)
          post3 = Post.create!(title: "Bob's Draft", user_id: user3.id, published: false)

          # Test WHERE with INNER JOIN - only posts from active users
          active_user_posts = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { users.active.true? }

          active_user_posts.size.should eq(2)
          active_user_posts.map(&.title).should contain("John's Post")
          active_user_posts.map(&.title).should contain("Bob's Draft")
          active_user_posts.map(&.title).should_not contain("Jane's Post")
        end
      end

      it "WHERE with multiple conditions across JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John", active: true)
          user2 = User.create!(first_name: "Jane", active: true)
          user3 = User.create!(first_name: "Bob", active: false)

          post1 = Post.create!(title: "John's Published Post", user_id: user1.id, published: true)
          post2 = Post.create!(title: "John's Draft", user_id: user1.id, published: false)
          post3 = Post.create!(title: "Jane's Published Post", user_id: user2.id, published: true)
          post4 = Post.create!(title: "Bob's Post", user_id: user3.id, published: true)

          # Test multiple WHERE conditions across JOINed tables
          published_active_posts = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { (users.active == true) & (posts.published == true) }

          published_active_posts.size.should eq(2)
          published_active_posts.map(&.title).should contain("John's Published Post")
          published_active_posts.map(&.title).should contain("Jane's Published Post")
          published_active_posts.map(&.title).should_not contain("John's Draft")
          published_active_posts.map(&.title).should_not contain("Bob's Post")
        end
      end

      it "WHERE with INNER JOIN and NULL handling" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John", last_name: "Doe")
          user2 = User.create!(first_name: "Jane", last_name: nil) # NULL last_name

          post1 = Post.create!(title: "John's Post", user_id: user1.id)
          post2 = Post.create!(title: "Jane's Post", user_id: user2.id)

          # Test WHERE with INNER JOIN and NULL conditions
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { users.last_name == nil }

          results.size.should eq(1)
          results.first!.title.should eq("Jane's Post")
        end
      end

      it "WHERE with complex JOIN conditions" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John", active: true)
          user2 = User.create!(first_name: "Jane", active: true)

          category1 = Category.create!(name: "Technology")
          category2 = Category.create!(name: "Science")

          post1 = Post.create!(title: "Tech Post", user_id: user1.id, category_id: category1.id, published: true)
          post2 = Post.create!(title: "Science Post", user_id: user1.id, category_id: category2.id, published: true)
          post3 = Post.create!(title: "Another Tech Post", user_id: user2.id, category_id: category1.id, published: false)

          # Test complex JOIN with WHERE conditions
          results1 = Post.query
            .inner_join(:users) { posts.user_id == users.id }
            .inner_join(:categories) { posts.category_id == categories.id }
            .where do
              (users.active.true?) &
                (categories.name == "Technology") &
                (posts.published.true?)
            end

          results2 = Post.query
            .inner_join(:user)
            .inner_join(:category)
            .where do
              (users.active.true?) &
                (categories.name == "Technology") &
                (posts.published.true?)
            end

          results1.to_sql.should eq(results2.to_sql)

          results1.to_sql.should eq(
            "SELECT \"posts\".* FROM \"posts\" INNER JOIN \"users\" ON (\"posts\".\"user_id\" = \"users\".\"id\") INNER JOIN \"categories\" ON (\"posts\".\"category_id\" = \"categories\".\"id\") WHERE (((\"users\".\"active\" = TRUE) AND (\"categories\".\"name\" = 'Technology')) AND (\"posts\".\"published\" = TRUE))"
          )

          results1.size.should eq(1)
          results1.first!.title.should eq("Tech Post")
        end
      end

      it "WHERE with pattern matching in JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "john@gmail.com", active: true)
          user2 = User.create!(first_name: "jane@yahoo.com", active: true)
          user3 = User.create!(first_name: "bob@company.org", active: false)

          post1 = Post.create!(title: "Gmail User's Post", user_id: user1.id)
          post2 = Post.create!(title: "Yahoo User's Post", user_id: user2.id)
          post3 = Post.create!(title: "Company User's Post", user_id: user3.id)

          # Test WHERE with pattern matching in JOINed tables
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { (users.first_name.ilike("%@gmail.com")) & (users.active == true) }

          results.size.should eq(1)
          results.first!.title.should eq("Gmail User's Post")
        end
      end

      it "WHERE with regex in JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "john123@gmail.com", active: true)
          user2 = User.create!(first_name: "jane456@yahoo.com", active: true)
          user3 = User.create!(first_name: "bob@company.org", active: true)

          post1 = Post.create!(title: "Gmail User's Post", user_id: user1.id)
          post2 = Post.create!(title: "Yahoo User's Post", user_id: user2.id)
          post3 = Post.create!(title: "Company User's Post", user_id: user3.id)

          # Test WHERE with regex in JOINed tables
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { (users.first_name =~ /^[a-z0-9]+@gmail\.com$/i) & (users.active == true) }

          results.size.should eq(1)
          results.first!.title.should eq("Gmail User's Post")
        end
      end

      it "WHERE with membership operators in JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John", active: true)
          user2 = User.create!(first_name: "Jane", active: false)
          user3 = User.create!(first_name: "Bob", active: true)
          user4 = User.create!(first_name: "Alice", active: false)

          post1 = Post.create!(title: "John's Post", user_id: user1.id)
          post2 = Post.create!(title: "Jane's Post", user_id: user2.id)
          post3 = Post.create!(title: "Bob's Post", user_id: user3.id)
          post4 = Post.create!(title: "Alice's Post", user_id: user4.id)

          # Test WHERE with membership operators in JOINed tables
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { users.active.in?([true, nil]) }

          results.size.should eq(2)
          results.map(&.title).should contain("John's Post")      # active: true
          results.map(&.title).should contain("Bob's Post")       # active: true
          results.map(&.title).should_not contain("Jane's Post")  # active: false
          results.map(&.title).should_not contain("Alice's Post") # active: false
        end
      end

      it "WHERE with between operator in JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "John")
          user2 = User.create!(first_name: "Jane")
          user3 = User.create!(first_name: "Bob")
          user4 = User.create!(first_name: "Alice")

          post1 = Post.create!(title: "John's Post", user_id: user1.id)
          post2 = Post.create!(title: "Jane's Post", user_id: user2.id)
          post3 = Post.create!(title: "Bob's Post", user_id: user3.id)
          post4 = Post.create!(title: "Alice's Post", user_id: user4.id)

          # Test WHERE with between operator in JOINed tables using user IDs
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where { users.id.between?(user2.id, user3.id) }

          results.size.should eq(2)
          results.map(&.title).should contain("Jane's Post")      # user2.id
          results.map(&.title).should contain("Bob's Post")       # user3.id
          results.map(&.title).should_not contain("John's Post")  # user1.id (outside range)
          results.map(&.title).should_not contain("Alice's Post") # user4.id (outside range)
        end
      end

      it "WHERE with complex nested conditions in JOINed tables" do
        temporary do
          reinit_example_models

          user1 = User.create!(first_name: "john@gmail.com", active: true)
          user2 = User.create!(first_name: "jane@yahoo.com", active: true)
          user3 = User.create!(first_name: "bob@gmail.com", active: false)
          user4 = User.create!(first_name: "alice@company.org", active: true)

          post1 = Post.create!(title: "John's Tech Post", user_id: user1.id, published: true)
          post2 = Post.create!(title: "Jane's Post", user_id: user2.id, published: true)
          post3 = Post.create!(title: "Bob's Draft", user_id: user3.id, published: false)
          post4 = Post.create!(title: "Alice's Post", user_id: user4.id, published: true)

          # Test complex nested WHERE conditions in JOINed tables
          results = Post.query
            .inner_join(:users) { users.id == posts.user_id }
            .where do
              ((users.first_name.ilike("%@gmail.com")) & (users.active == true)) |
                ((posts.published == true) & (users.first_name.ilike("%@company.org")))
            end

          results.size.should eq(2)
          results.map(&.title).should contain("John's Tech Post") # gmail + active
          results.map(&.title).should contain("Alice's Post")     # company.org + published
          results.map(&.title).should_not contain("Jane's Post")  # doesn't match either condition
          results.map(&.title).should_not contain("Bob's Draft")  # gmail but inactive + not published
        end
      end
    end

    context "where.not" do
      it "supports basic where.not operations" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)

          # Test with expression engine
          names = User.query.where.not { active == false }.map(&.first_name)
          names.size.should eq(2)
          names.should contain("John")
          names.should contain("Bob")
          names.should_not contain("Jane")

          # Test with NamedTuple
          names = User.query.where.not(active: false).map(&.first_name)
          names.size.should eq(2)
          names.should contain("John")
          names.should contain("Bob")
          names.should_not contain("Jane")

          # Test with array (NOT IN)
          users = User.query.where.not(id: [1, 2])
          users.size.should eq(1)
          users.first!.first_name.should eq("Bob")

          # Test with nil (NOT NULL)
          User.create!(id: 4, first_name: "Alice", active: nil)
          names = User.query.where.not(active: nil).map(&.first_name)
          names.size.should eq(3)
          names.should contain("John")
          names.should contain("Jane")
          names.should contain("Bob")
          names.should_not contain("Alice")
        end
      end

      it "supports chaining with where" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)
          User.create!(id: 4, first_name: "Alice", active: nil)

          # Test chaining where and where.not
          users = User.query
            .where { id > 1 }
            .not { active == false }
            .not(id: [4])

          users.size.should eq(1)
          users.first!.first_name.should eq("Bob")

          # Test another chaining combination
          users = User.query
            .not(id: [1, 2])
            .not { active == nil }

          users.size.should eq(1)
          users.first!.first_name.should eq("Bob")
        end
      end
    end

    context "where.or" do
      it "supports basic where.or operations" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)
          User.create!(id: 4, first_name: "Alice", active: nil)

          # Test basic where.or with expression engine
          names = User.query.where { id == 1 }.or { id == 3 }.map(&.first_name)
          names.size.should eq(2)
          names.sort!.should eq(["Bob", "John"])

          # Test where.or with named tuple
          names = User.query.where { id == 1 }.or(first_name: "Jane").map(&.first_name)
          names.size.should eq(2)
          names.sort!.should eq(["Jane", "John"])

          # Test where.or with array conditions (IN)
          names = User.query.where { active == true }.or({id: [2, 4]}).map(&.first_name)
          names.size.should eq(4) # John, Bob (active=true), Jane (id=2), Alice (id=4)
          names.sort!.should eq(["Alice", "Bob", "Jane", "John"])

          # Test where.or with nil
          names = User.query.where { id == 1 }.or(active: nil).map(&.first_name)
          names.size.should eq(2)
          names.sort!.should eq(["Alice", "John"])
        end
      end

      it "supports chaining multiple times" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John")
          User.create!(id: 2, first_name: "Jane")
          User.create!(id: 3, first_name: "Bob")
          User.create!(id: 4, first_name: "Alice")
          User.create!(id: 5, first_name: "Charlie")

          # Chain multiple or conditions
          users = User.query
            .where { id == 1 }
            .or { id == 2 }
            .or { id == 3 }

          users.size.should eq(3)
          users.map(&.first_name).sort!.should eq(["Bob", "Jane", "John"])
        end
      end

      it "supports complex chaining with where" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)
          User.create!(id: 4, first_name: "Alice", active: false)
          User.create!(id: 5, first_name: "Charlie", active: true)

          # Mix where, or, and where
          users = User.query
            .where { active == true }
            .or { first_name == "Jane" }
            .where { id > 1 }

          users.size.should eq(3) # Bob, Jane, Charlie (active OR Jane, and id > 1)
          users.map(&.first_name).sort!.should eq(["Bob", "Charlie", "Jane"])
        end
      end

      it "combines with where.not" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)
          User.create!(id: 4, first_name: "Alice", active: false)

          # Combine where.or with where.not
          users = User.query
            .where { id == 1 }
            .or { id == 2 }
            .where.not(active: false)

          users.size.should eq(1) # Only John (id=1 OR id=2, but NOT active=false)
          users.first!.first_name.should eq("John")
        end
      end

      it "supports multiple conditions in named tuple" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true, last_name: "Doe")
          User.create!(id: 2, first_name: "Jane", active: false, last_name: "Smith")
          User.create!(id: 3, first_name: "Bob", active: true, last_name: "Johnson")
          User.create!(id: 4, first_name: "Alice", active: false, last_name: "Doe")

          # OR with multiple conditions (they are combined with AND within the OR)
          users = User.query
            .where { id == 1 }
            .or(active: true, last_name: "Johnson")

          users.size.should eq(2) # John (id=1) OR Bob (active=true AND last_name=Johnson)
          users.map(&.first_name).sort!.should eq(["Bob", "John"])
        end
      end

      it "works when starting with empty where" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John")
          User.create!(id: 2, first_name: "Jane")

          # Start with empty where, then or
          users = User.query.where.or { id == 1 }
          users.size.should eq(1)
          users.first!.first_name.should eq("John")
        end
      end

      it "supports template strings" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true)
          User.create!(id: 2, first_name: "Jane", active: false)
          User.create!(id: 3, first_name: "Bob", active: true)

          # Using template string with positional params
          users = User.query
            .where { id == 1 }
            .or("first_name = ?", "Bob")

          users.size.should eq(2)
          users.map(&.first_name).sort!.should eq(["Bob", "John"])

          # Using template string with named params
          users = User.query
            .where { active == true }
            .or("first_name = :name", name: "Jane")

          users.size.should eq(3)
          users.map(&.first_name).sort!.should eq(["Bob", "Jane", "John"])
        end
      end

      it "supports complex nested conditions" do
        temporary do
          reinit_example_models
          User.create!(id: 1, first_name: "John", active: true, last_name: "Admin")
          User.create!(id: 2, first_name: "Jane", active: false, last_name: "User")
          User.create!(id: 3, first_name: "Bob", active: true, last_name: "User")
          User.create!(id: 4, first_name: "Alice", active: false, last_name: "Admin")

          # Nested AND conditions within OR
          users = User.query
            .where { (active == true) & (last_name == "Admin") }
            .or { (active == false) & (first_name == "Jane") }

          users.size.should eq(2) # John (active AND Admin) OR Jane (NOT active AND Jane)
          users.map(&.first_name).sort!.should eq(["Jane", "John"])
        end
      end
    end
  end
end
