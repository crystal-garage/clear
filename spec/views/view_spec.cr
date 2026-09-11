require "../spec_helper"

module ViewSpec
  describe "Lustra::View" do
    it "recreates an existing chain of dependent views" do
      temporary do
        Lustra::View.register :view_recreation_leaf do |view|
          view.require(:view_recreation_middle)
          view.query "SELECT value FROM public.view_recreation_middle"
        end
        Lustra::View.register :view_recreation_middle do |view|
          view.require(:view_recreation_root)
          view.query "SELECT value FROM public.view_recreation_root"
        end
        Lustra::View.register :view_recreation_root do |view|
          view.query "SELECT 42 AS value"
        end

        Lustra::View.apply(:create)
        Lustra::SQL.select("value").from("public.view_recreation_leaf").scalar(Int32).should eq(42)

        Lustra::View.apply(:drop)
        Lustra::View.apply(:create)

        Lustra::SQL.select("value").from("public.view_recreation_leaf").scalar(Int32).should eq(42)
      end
    ensure
      Lustra::View.clear
    end

    it "drops shared dependencies after all dependents regardless of registration order" do
      temporary do
        Lustra::View.register :view_recreation_root do |view|
          view.query "SELECT 42 AS value"
        end
        Lustra::View.register :view_recreation_left do |view|
          view.require(:view_recreation_root)
          view.query "SELECT value FROM public.view_recreation_root"
        end
        Lustra::View.register :view_recreation_right do |view|
          view.require(:view_recreation_root)
          view.query "SELECT value FROM public.view_recreation_root"
        end

        Lustra::View.apply(:create)
        Lustra::View.apply(:drop)
        Lustra::View.apply(:create)

        Lustra::SQL.select("value").from("public.view_recreation_left").scalar(Int32).should eq(42)
        Lustra::SQL.select("value").from("public.view_recreation_right").scalar(Int32).should eq(42)
      end
    ensure
      Lustra::View.clear
    end

    it "reports cyclic dependencies before recursing indefinitely" do
      Lustra::View.register :view_recreation_left do |view|
        view.require(:view_recreation_right)
        view.query "SELECT 1 AS value"
      end
      Lustra::View.register :view_recreation_right do |view|
        view.require(:view_recreation_left)
        view.query "SELECT 1 AS value"
      end

      {:create, :drop}.each do |direction|
        expect_raises(ArgumentError, /Cyclic view dependency/) do
          Lustra::View.apply(direction)
        end
      end
    ensure
      Lustra::View.clear
    end

    it "drops a custom-schema view without dropping a same-named public view" do
      temporary do
        Lustra::SQL.execute("SET LOCAL search_path TO public")
        Lustra::SQL.execute("CREATE SCHEMA view_recreation_schema")
        Lustra::SQL.execute("CREATE VIEW public.view_recreation_shared AS SELECT 1 AS value")
        Lustra::View.register :view_recreation_shared do |view|
          view.schema(:view_recreation_schema)
          view.query "SELECT 2 AS value"
        end
        Lustra::View.apply(:create)

        Lustra::View.apply(:drop)

        public_exists = Lustra::SQL.select("to_regclass('public.view_recreation_shared') IS NOT NULL").scalar(Bool)
        custom_exists = Lustra::SQL.select("to_regclass('view_recreation_schema.view_recreation_shared') IS NOT NULL").scalar(Bool)
        {public_exists, custom_exists}.should eq({true, false})
      end
    ensure
      Lustra::View.clear
    end

    it "creates a registered materialized view" do
      temporary do
        Lustra::View.register :view_recreation_materialized do |view|
          view.materialized(true)
          view.query "SELECT 42 AS value"
        end

        Lustra::View.apply(:create)

        Lustra::SQL.select("value").from("public.view_recreation_materialized").scalar(Int32).should eq(42)
        Lustra::View.apply(:drop)
        Lustra::View.apply(:create)
        Lustra::SQL.select("value").from("public.view_recreation_materialized").scalar(Int32).should eq(42)
      end
    ensure
      Lustra::View.clear
    end

    it "drops a registered materialized view" do
      temporary do
        # Create directly so this spec tests dropping independently of the creation bug.
        Lustra::SQL.execute("CREATE MATERIALIZED VIEW public.view_recreation_materialized AS SELECT 42 AS value")
        Lustra::View.register :view_recreation_materialized do |view|
          view.materialized(true)
          view.query "SELECT 42 AS value"
        end

        Lustra::View.apply(:drop)

        Lustra::SQL.select("to_regclass('public.view_recreation_materialized') IS NULL").scalar(Bool).should be_true
      end
    ensure
      Lustra::View.clear
    end

    it "recreate the views on migration" do
      temporary do
        Lustra::View.register :room_per_days do |view|
          view.require(:rooms, :year_days)

          view.query <<-SQL
            SELECT room_id, day
            FROM year_days
            CROSS JOIN rooms
            SQL
        end

        Lustra::View.register :rooms do |view|
          view.query <<-SQL
            SELECT room.id AS room_id
            FROM generate_series(1, 4) AS room(id)
            SQL
        end

        Lustra::View.register :year_days do |view|
          view.query <<-SQL
            SELECT date.day::date AS day
            FROM   generate_series(
              date_trunc('day', NOW()),
              date_trunc('day', NOW() + INTERVAL '364 days'),
              INTERVAL '1 day'
            ) AS date(day)
            SQL
        end

        Lustra::Migration::Manager.instance.reinit!
        Lustra::Migration::Manager.instance.apply_all

        # Ensure that the view is loaded and working properly.
        Lustra::SQL.select.from("room_per_days").agg("COUNT(day)", Int64).should eq(4*365)
        Lustra::View.clear
      end
    end
  end
end
