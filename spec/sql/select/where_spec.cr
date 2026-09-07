require "../../spec_helper"

module WhereSpec
  def self.complex_query
    Lustra::SQL.select.from(:users)
      .join(:role_users) { var("role_users", "user_id") == users.id }
      .join(:roles) { var("role_users", "role_id") == var("roles", "id") }
      .where({role: ["admin", "superadmin"]})
      .order_by({priority: :desc, name: :asc})
      .limit(50)
      .offset(50)
  end

  describe Lustra::SQL::Query::Where do
    it "accepts simple string as parameter" do
      r = Lustra::SQL.select.from(:users).where("a = b")
      r.to_sql.should eq %(SELECT * FROM "users" WHERE a = b)
    end

    it "accepts NamedTuple argument" do
      # tuple as argument
      q = Lustra::SQL.select.from(:users).where({user_id: 1})
      q.to_sql.should eq %(SELECT * FROM "users" WHERE ("user_id" = 1))

      # splatted tuple
      q = Lustra::SQL.select.from(:users).where(user_id: 2)
      q.to_sql.should eq %(SELECT * FROM "users" WHERE ("user_id" = 2))
    end

    it "transforms Nil to NULL" do
      q = Lustra::SQL.select.from(:users).where({user_id: nil})
      q.to_sql.should eq %(SELECT * FROM "users" WHERE ("user_id" IS NULL))
    end

    it "uses IN operator if an array is found" do
      q = Lustra::SQL.select.from(:users).where({user_id: [1, 2, 3, 4, "hello"]})
      q.to_sql.should eq %(SELECT * FROM "users" WHERE "user_id" IN (1, 2, 3, 4, 'hello'))
    end

    it "accepts ranges as tuple value and transform them" do
      Lustra::SQL.select.from(:users).where({x: 1..4}).to_sql
        .should eq %(SELECT * FROM "users" WHERE ("x" >= 1 AND "x" <= 4))
      Lustra::SQL.select.from(:users).where({x: 1...4}).to_sql
        .should eq %(SELECT * FROM "users" WHERE ("x" >= 1 AND "x" < 4))
      Lustra::SQL.select.from(:users).where({x: 1..}).to_sql
        .should eq %(SELECT * FROM "users" WHERE ("x" >= 1))
      Lustra::SQL.select.from(:users).where({x: ..10}).to_sql
        .should eq %(SELECT * FROM "users" WHERE ("x" <= 10))
      Lustra::SQL.select.from(:users).where({x: ...10}).to_sql
        .should eq %(SELECT * FROM "users" WHERE ("x" < 10))
    end

    it "allows prepared query" do
      r = Lustra::SQL.select.from(:users).where("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE a LIKE 'hello'"

      r = Lustra::SQL.select.from(:users).where("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE a LIKE 'hello'"
    end

    it "manages ranges" do
      Lustra::SQL.select.from(:users).where({x: 1..4}).to_sql
        .should eq "SELECT * FROM \"users\" WHERE (\"x\" >= 1 AND \"x\" <= 4)"

      Lustra::SQL.select.from(:users).where({x: 1...4}).to_sql
        .should eq "SELECT * FROM \"users\" WHERE (\"x\" >= 1 AND \"x\" < 4)"
    end

    it "prepare query" do
      r = Lustra::SQL.select.from(:users).where("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE a LIKE 'hello'"
    end

    it "raises exception with prepared query" do
      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).where("a LIKE ? AND b = ?", "hello")
      end
    end

    it "prepare query with tuple" do
      r = Lustra::SQL.select.from(:users).where("a LIKE :hello AND b LIKE :world",
        hello: "h", world: "w")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE a LIKE 'h' AND b LIKE 'w'"

      # check escaping `::`
      r = Lustra::SQL.select.from(:users).where("a::text LIKE :hello", hello: "h")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE a::text LIKE 'h'"

      # check escaping the first character because of the regexp solution I used
      r = Lustra::SQL.select.from(:users).where(":text", text: "ok")
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE 'ok'"
    end

    it "raises exception if a tuple element is not found" do
      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).where("a LIKE :halo AND b LIKE :world", hello: "h", world: "w")
      end

      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).where.or("a LIKE :halo AND b LIKE :world", hello: "h", world: "w")
      end
    end

    it "prepare group by query" do
      Lustra::SQL.select.select("role").from(:users).group_by(:role).order_by(:role).to_sql.should eq \
        "SELECT role FROM \"users\" GROUP BY \"role\" ORDER BY \"role\" ASC"
    end

    it "use different comparison and arithmetic operators" do
      r = Lustra::SQL.select.from(:users).where { users.id > 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" > 1)"
      r = Lustra::SQL.select.from(:users).where { users.id < 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" < 1)"
      r = Lustra::SQL.select.from(:users).where { users.id >= 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" >= 1)"
      r = Lustra::SQL.select.from(:users).where { users.id <= 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" <= 1)"
      r = Lustra::SQL.select.from(:users).where { users.id * 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE ((\"users\".\"id\" * 2) = 1)"
      r = Lustra::SQL.select.from(:users).where { users.id / 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE ((\"users\".\"id\" / 2) = 1)"
      r = Lustra::SQL.select.from(:users).where { users.id + 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE ((\"users\".\"id\" + 2) = 1)"
      r = Lustra::SQL.select.from(:users).where { users.id - 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE ((\"users\".\"id\" - 2) = 1)"
      r = Lustra::SQL.select.from(:users).where { -users.id < -1000 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (-\"users\".\"id\" < -1000)"
    end

    it "use expression engine equal" do
      r = Lustra::SQL.select.from(:users).where { users.id == var("test") }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" = \"test\")"
    end

    it "use expression engine not equals" do
      r = Lustra::SQL.select.from(:users).where { users.id != 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" <> 1)"
    end

    it "use expression engine not null" do
      r = Lustra::SQL.select.from(:users).where { users.id != nil }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" IS NOT NULL)"
    end

    it "use expression engine null" do
      r = Lustra::SQL.select.from(:users).where { users.id == nil }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" IS NULL)"
    end

    it "use expression engine null?" do
      r = Lustra::SQL.select.from(:users).where { users.id.null? }
      r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" IS NULL)"
    end

    describe "where expressions" do
      it "where.where" do
        now = Time.local
        r = Lustra::SQL.select.from(:users)
          .where { users.id == nil }
          .where { var("users", "updated_at") >= now }

        r.to_sql.should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" IS NULL) " +
                           "AND (\"users\".\"updated_at\" >= #{Lustra::Expression[now]})"
      end

      it "where.or" do
        now = Time.local
        r = Lustra::SQL.select.from(:users)
          .where { users.id == nil }
          .or { var("users", "updated_at") >= now }

        r.to_sql.should eq "SELECT * FROM \"users\" WHERE ((\"users\".\"id\" IS NULL) " +
                           "OR (\"users\".\"updated_at\" >= #{Lustra::Expression[now]}))"
      end

      it "op(:&)/op(:|)" do
        r = Lustra::SQL.select.from(:users).where do
          ((raw("users.id") > 100) & (raw("users.visible") == true)) |
            (raw("users.role") == "superadmin")
        end

        r.to_sql.should eq "SELECT * FROM \"users\" WHERE (((users.id > 100) " +
                           "AND (users.visible = TRUE)) OR (users.role = 'superadmin'))"
      end

      it "between?(a, b)" do
        Lustra::SQL.select.where { x.between?(1, 2) }
          .to_sql.should eq(%(SELECT * WHERE ("x" BETWEEN 1 AND 2)))

        Lustra::SQL.select.where { not(x.between?(1, 2)) }
          .to_sql.should eq(%(SELECT * WHERE NOT ("x" BETWEEN 1 AND 2)))
      end

      it "between?(a, b) with Time values" do
        time_start = Time.utc(2025, 1, 1, 12, 0, 0)
        time_end = Time.utc(2025, 1, 1, 15, 0, 0)

        Lustra::SQL.select.from(:users).where { created_at.between?(time_start, time_end) }
          .to_sql.should eq("SELECT * FROM \"users\" WHERE (\"created_at\" BETWEEN " +
                            "#{Lustra::Expression[time_start]} AND #{Lustra::Expression[time_end]})")

        Lustra::SQL.select.from(:users).where { not(created_at.between?(time_start, time_end)) }
          .to_sql.should eq("SELECT * FROM \"users\" WHERE NOT (\"created_at\" BETWEEN " +
                            "#{Lustra::Expression[time_start]} AND #{Lustra::Expression[time_end]})")
      end

      it "custom functions" do
        Lustra::SQL.select.where { ops_transform(x, "string", raw("INTERVAL '2 seconds'")) }
          .to_sql.should eq(%(SELECT * WHERE ops_transform("x", 'string', INTERVAL '2 seconds')))
      end

      it "in?(array)" do
        Lustra::SQL.select.where { x.in?([1, 2, 3, 4]) }
          .to_sql.should eq(%(SELECT * WHERE "x" IN (1, 2, 3, 4)))

        Lustra::SQL.select.where { x.in?({1, 2, 3, 4}) }
          .to_sql.should eq(%(SELECT * WHERE "x" IN (1, 2, 3, 4)))
      end

      it "in?(range)" do
        # Simple number
        Lustra::SQL.select.from(:users).where { users.id.in?(1..3) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" >= 1 AND \"users\".\"id\" <= 3)"

        # Date range.
        range = 2.day.ago..1.day.ago

        Lustra::SQL.select.from(:users).where { created_at.in?(range) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" >= #{Lustra::Expression[range.begin]} AND" +
                     " \"created_at\" <= #{Lustra::Expression[range.end]})"

        # Exclusive range
        Lustra::SQL.select.from(:users).where { users.id.in?(1...3) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" >= 1" +
                     " AND \"users\".\"id\" < 3)"

        # Endless range
        Lustra::SQL.select.from(:users).where { users.id.in?(10..) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" >= 10)"

        # Beginless range (inclusive)
        Lustra::SQL.select.from(:users).where { users.id.in?(..100) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" <= 100)"

        # Beginless range (exclusive)
        Lustra::SQL.select.from(:users).where { users.id.in?(...100) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE (\"users\".\"id\" < 100)"

        # Full range (...) - matches all values
        Lustra::SQL.select.from(:users).where { users.id.in?(...) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE TRUE"
      end

      it "in?(range) with Time values" do
        time_start = Time.utc(2025, 1, 1, 12, 0, 0)
        time_end = Time.utc(2025, 1, 1, 15, 0, 0)

        # Normal time range
        Lustra::SQL.select.from(:users).where { created_at.in?(time_start..time_end) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" >= #{Lustra::Expression[time_start]} AND" +
                     " \"created_at\" <= #{Lustra::Expression[time_end]})"

        # Exclusive time range
        Lustra::SQL.select.from(:users).where { created_at.in?(time_start...time_end) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" >= #{Lustra::Expression[time_start]} AND" +
                     " \"created_at\" < #{Lustra::Expression[time_end]})"

        # Endless time range
        Lustra::SQL.select.from(:users).where { created_at.in?(time_start..) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" >= #{Lustra::Expression[time_start]})"

        # Beginless time range (inclusive)
        Lustra::SQL.select.from(:users).where { created_at.in?(..time_end) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" <= #{Lustra::Expression[time_end]})"

        # Beginless time range (exclusive)
        Lustra::SQL.select.from(:users).where { created_at.in?(...time_end) }.to_sql
          .should eq "SELECT * FROM \"users\" WHERE " +
                     "(\"created_at\" < #{Lustra::Expression[time_end]})"
      end

      it "in?(sub_query)" do
        sub_query = Lustra::SQL.select("id").from("users")
        Lustra::SQL.select.where { x.in?(sub_query) }
          .to_sql.should eq(%(SELECT * WHERE "x" IN (SELECT id FROM users)))
      end

      it "unary minus" do
        Lustra::SQL.select.where { -x > 2 }
          .to_sql.should eq(%(SELECT * WHERE (-"x" > 2)))
      end

      it "not()" do
        Lustra::SQL.select.where { not(raw("TRUE")) }
          .to_sql.should eq(%(SELECT * WHERE NOT TRUE))

        Lustra::SQL.select.where { ~(raw("TRUE")) }
          .to_sql.should eq(%(SELECT * WHERE NOT TRUE))
      end

      it "nil" do
        Lustra::SQL.select.where { x == nil }
          .to_sql.should eq(%(SELECT * WHERE ("x" IS NULL)))
        Lustra::SQL.select.where { x != nil }
          .to_sql.should eq(%(SELECT * WHERE ("x" IS NOT NULL)))
      end

      it "raw()" do
        Lustra::SQL.select.where { raw("Anything") }
          .to_sql.should eq(%(SELECT * WHERE Anything))

        Lustra::SQL.select.where { raw("x > ?", 1) }
          .to_sql.should eq(%(SELECT * WHERE x > 1))

        Lustra::SQL.select.where { raw("x > :num", num: 2) }
          .to_sql.should eq(%(SELECT * WHERE x > 2))
      end

      it "var()" do
        Lustra::SQL.select.where { var("public", "users", "id") < 1000 }
          .to_sql.should eq(%(SELECT * WHERE ("public"."users"."id" < 1000)))
      end
    end

    describe "like and ilike operators" do
      it "supports like operator in DSL" do
        r = Lustra::SQL.select.from(:users).where { users.email.like("%@gmail.com") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" LIKE '%@gmail.com'))
      end

      it "supports ilike operator in DSL" do
        r = Lustra::SQL.select.from(:users).where { users.email.ilike("%@gmail.com") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" ILIKE '%@gmail.com'))
      end

      it "supports like with case sensitive pattern" do
        r = Lustra::SQL.select.from(:users).where { users.name.like("John%") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."name" LIKE 'John%'))
      end

      it "supports ilike with case insensitive pattern" do
        r = Lustra::SQL.select.from(:users).where { users.name.ilike("john%") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."name" ILIKE 'john%'))
      end

      it "supports like with complex patterns" do
        r = Lustra::SQL.select.from(:users).where { users.email.like("user%@%.com") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" LIKE 'user%@%.com'))
      end

      it "supports ilike with complex patterns" do
        r = Lustra::SQL.select.from(:users).where { users.email.ilike("user%@%.com") }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" ILIKE 'user%@%.com'))
      end
    end

    describe "regex operators" do
      it "supports =~ operator with Node" do
        r = Lustra::SQL.select.from(:users).where { users.email =~ users.pattern }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" ~ "users"."pattern"))
      end

      it "supports !~ operator with Node" do
        r = Lustra::SQL.select.from(:users).where { users.email !~ users.pattern }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" !~ "users"."pattern"))
      end

      it "supports =~ operator with Regex (case sensitive)" do
        r = Lustra::SQL.select.from(:users).where { users.email =~ /^[a-z]+@/ }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" ~ '^[a-z]+@'))
      end

      it "supports =~ operator with Regex (case insensitive)" do
        r = Lustra::SQL.select.from(:users).where { users.email =~ /^[a-z]+@/i }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" ~* '^[a-z]+@'))
      end

      it "supports !~ operator with Regex (case sensitive)" do
        r = Lustra::SQL.select.from(:users).where { users.email !~ /^[a-z]+@/ }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" !~ '^[a-z]+@'))
      end

      it "supports !~ operator with Regex (case insensitive)" do
        r = Lustra::SQL.select.from(:users).where { users.email !~ /^[a-z]+@/i }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."email" !~* '^[a-z]+@'))
      end
    end

    describe "unary operators" do
      it "supports unary NOT operator" do
        r = Lustra::SQL.select.from(:users).where { ~users.active }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT "users"."active")
      end

      it "supports unary NOT with complex expressions" do
        r = Lustra::SQL.select.from(:users).where { ~(users.id > 100) }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT ("users"."id" > 100))
      end
    end

    describe "where.not syntax" do
      it "supports where.not with block syntax" do
        r = Lustra::SQL.select.from(:users).where.not { users.id == 1 }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT ("users"."id" = 1))
      end

      it "supports where.not with named tuple" do
        r = Lustra::SQL.select.from(:users).where.not({active: true})
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT ("active" = TRUE))
      end

      it "supports where.not with template string" do
        r = Lustra::SQL.select.from(:users).where.not("id = ?", 1)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT id = 1)
      end

      it "supports where.not with template string and named parameters" do
        r = Lustra::SQL.select.from(:users).where.not("id = :id", id: 1)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT id = 1)
      end

      it "supports where.not with array conditions" do
        r = Lustra::SQL.select.from(:users).where.not({id: [1, 2, 3]})
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT "id" IN (1, 2, 3))
      end

      it "supports where.not with NULL conditions" do
        r = Lustra::SQL.select.from(:users).where.not({email: nil})
        r.to_sql.should eq %(SELECT * FROM "users" WHERE NOT ("email" IS NULL))
      end
    end

    describe "where.or syntax" do
      it "supports where.or with block syntax" do
        r = Lustra::SQL.select.from(:users).where { users.id == 1 }.or { users.id == 2 }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR ("users"."id" = 2)))
      end

      it "supports where.or with named tuple" do
        r = Lustra::SQL.select.from(:users).where { users.id == 1 }.or(active: true)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR ("active" = TRUE)))
      end

      it "supports where.or with template string" do
        r = Lustra::SQL.select.from(:users).where { users.id == 1 }.or("status = ?", "active")
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR (status = 'active')))
      end

      it "supports where.or with template string and named parameters" do
        r = Lustra::SQL.select.from(:users).where { users.id == 1 }.or("status = :status", status: "active")
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR (status = 'active')))
      end

      it "supports where.or with array conditions" do
        r = Lustra::SQL.select.from(:users).where { users.active == true }.or({id: [1, 2, 3]})
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."active" = TRUE) OR "id" IN (1, 2, 3)))
      end

      it "supports where.or chaining multiple times" do
        r = Lustra::SQL.select.from(:users).where { users.id == 1 }.or { users.id == 2 }.or { users.id == 3 }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR ("users"."id" = 2) OR ("users"."id" = 3)))
      end

      it "supports where.or when starting with empty where" do
        r = Lustra::SQL.select.from(:users).where.or { users.id == 1 }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ("users"."id" = 1))
      end

      it "supports complex chaining with where and where.or" do
        r = Lustra::SQL.select.from(:users)
          .where { users.role == "admin" }
          .or { users.role == "superadmin" }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."role" = 'admin') OR ("users"."role" = 'superadmin')))
      end

      it "supports where.or with multiple conditions in named tuple" do
        r = Lustra::SQL.select.from(:users)
          .where { users.id == 1 }
          .or(active: true, verified: true)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR (("active" = TRUE) AND ("verified" = TRUE))))
      end

      it "supports mixing where, where.or, and where again" do
        r = Lustra::SQL.select.from(:users)
          .where { users.active == true }
          .or { users.verified == true }
          .where { users.id > 100 }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."active" = TRUE) OR ("users"."verified" = TRUE)) AND ("users"."id" > 100))
      end

      it "supports where.or with range conditions" do
        r = Lustra::SQL.select.from(:users)
          .where { users.id == 1 }
          .or(age: 18..65)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR ("age" >= 18 AND "age" <= 65)))
      end

      it "supports where.or with NULL conditions" do
        r = Lustra::SQL.select.from(:users)
          .where { users.active == true }
          .or(deleted_at: nil)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."active" = TRUE) OR ("deleted_at" IS NULL)))
      end

      it "supports complex OR chains with different condition types" do
        r = Lustra::SQL.select.from(:users)
          .where { users.id == 1 }
          .or(role: "admin")
          .or { users.verified == true }
          .or("status = ?", "premium")
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."id" = 1) OR ("role" = 'admin') OR ("users"."verified" = TRUE) OR (status = 'premium')))
      end

      it "supports where.or combining with where.not" do
        r = Lustra::SQL.select.from(:users)
          .where { users.active == true }
          .or { users.verified == true }
          .where.not(banned: true)
        r.to_sql.should eq %(SELECT * FROM "users" WHERE (("users"."active" = TRUE) OR ("users"."verified" = TRUE)) AND NOT ("banned" = TRUE))
      end

      it "supports nested OR conditions with AND" do
        r = Lustra::SQL.select.from(:users)
          .where { (users.active == true) & (users.verified == true) }
          .or { (users.role == "admin") & (users.premium == true) }
        r.to_sql.should eq %(SELECT * FROM "users" WHERE ((("users"."active" = TRUE) AND ("users"."verified" = TRUE)) OR (("users"."role" = 'admin') AND ("users"."premium" = TRUE))))
      end
    end
  end
end
