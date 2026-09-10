require "../spec_helper"

module MultipleConnectionsSpec
  class Post
    include Lustra::Model

    self.table = "models_posts_two"

    column id : Int32, primary: true, presence: false
    column title : String
  end

  class PostStat
    include Lustra::Model

    self.connection = "secondary"
    self.table = "models_post_stats"

    column id : Int32, primary: true, presence: false
    column post_id : Int32
  end

  class CallbackFailure < Exception; end

  class CallbackPostStat
    include Lustra::Model

    self.connection = "secondary"
    self.table = "models_post_stats"

    column id : Int32, primary: true, presence: false
    column post_id : Int32

    property fail_after : Symbol? = nil

    after(:create) { |model| model.as(CallbackPostStat).fail_callback(:create) }
    after(:update) { |model| model.as(CallbackPostStat).fail_callback(:update) }
    after(:destroy) { |model| model.as(CallbackPostStat).fail_callback(:destroy) }

    def fail_callback(event : Symbol)
      raise CallbackFailure.new("Failed after #{event}") if fail_after == event
    end
  end

  class CounterParent
    include Lustra::Model

    self.connection = "secondary"
    self.table = "secondary_counter_parents"

    column id : Int32, primary: true, presence: false
    column children_count : Int32, presence: false
  end

  class CounterChild
    include Lustra::Model

    self.connection = "secondary"
    self.table = "secondary_counter_children"

    column id : Int32, primary: true, presence: false

    belongs_to owner : CounterParent,
      foreign_key: "parent_id",
      foreign_key_type: Int32,
      counter_cache: :children_count
  end

  class ModelSpecMigration1234
    include Lustra::Migration

    def change(dir)
      create_table "models_posts_two" do |t|
        t.column "title", "string", index: true
      end
    end
  end

  def self.reinit
    reinit_migration_manager
    ModelSpecMigration1234.new.apply
  end

  def self.clear_post_stats
    Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")
  end

  def self.create_counter_tables
    Lustra::SQL.execute("secondary", <<-SQL)
      CREATE TABLE secondary_counter_parents (
        id serial PRIMARY KEY,
        children_count integer NOT NULL DEFAULT 0
      )
      SQL
    Lustra::SQL.execute("secondary", <<-SQL)
      CREATE TABLE secondary_counter_children (
        id serial PRIMARY KEY,
        parent_id integer NOT NULL
      )
      SQL
  end

  def self.drop_counter_tables
    Lustra::SQL.execute("secondary", "DROP TABLE IF EXISTS secondary_counter_children")
    Lustra::SQL.execute("secondary", "DROP TABLE IF EXISTS secondary_counter_parents")
  end

  describe "Lustra::Model" do
    context "multiple connections" do
      it "know about the different connections on models" do
        Post.connection.should eq "default"
        PostStat.connection.should eq "secondary"
      end

      it "load data from the default database" do
        temporary do
          reinit
          p = Post.new({title: "some post"})
          p.save
          p.persisted?.should be_true
        end
      end

      it "insert data into the secondary database" do
        temporary do
          reinit
          p = PostStat.new({post_id: 1})
          p.save
          p.persisted?.should be_true
          p.post_id.should eq(1)
        end
      end

      it "update data on the secondary database" do
        temporary do
          reinit
          p = PostStat.new({post_id: 1})
          p.save

          p = PostStat.query.first!
          p.post_id = 2
          p.save

          p = PostStat.query.first!
          p.post_id.should eq(2)
        end
      end

      it "update data on the secondary database" do
        temporary do
          reinit
          p = PostStat.new({post_id: 1})
          p.save
          p.delete.should be_true
        end
      end

      it "rolls back a secondary insert when its after-create callback fails" do
        clear_post_stats

        begin
          post_stat = CallbackPostStat.new({post_id: 1})
          post_stat.fail_after = :create

          expect_raises(CallbackFailure, "Failed after create") do
            post_stat.save!
          end

          CallbackPostStat.query.count.should eq(0)
        ensure
          clear_post_stats
        end
      end

      it "rolls back a secondary update when its after-update callback fails" do
        clear_post_stats

        begin
          post_stat = CallbackPostStat.create!(post_id: 1)
          post_stat.post_id = 2
          post_stat.fail_after = :update

          expect_raises(CallbackFailure, "Failed after update") do
            post_stat.save!
          end

          CallbackPostStat.query.find!(post_stat.id).post_id.should eq(1)
        ensure
          clear_post_stats
        end
      end

      it "rolls back a secondary delete when its after-destroy callback fails" do
        clear_post_stats

        begin
          post_stat = CallbackPostStat.create!(post_id: 1)
          post_stat.fail_after = :destroy

          expect_raises(CallbackFailure, "Failed after destroy") do
            post_stat.destroy
          end

          CallbackPostStat.query.where(id: post_stat.id).count.should eq(1)
        ensure
          clear_post_stats
        end
      end

      it "fetches with a cursor from the secondary database" do
        clear_post_stats

        begin
          PostStat.create!(post_id: 1)
          PostStat.create!(post_id: 2)

          post_ids = [] of Int32
          PostStat.query.order_by(:id).each_with_cursor(batch: 1) do |post_stat|
            post_ids << post_stat.post_id
          end

          post_ids.should eq([1, 2])
        ensure
          clear_post_stats
        end
      end

      it "bulk updates and deletes on the secondary database" do
        clear_post_stats

        begin
          PostStat.create!(post_id: 1)
          PostStat.create!(post_id: 2)

          PostStat.query.update_all(post_id: 3).should eq(2)
          PostStat.query.where(post_id: 3).count.should eq(2)

          PostStat.query.where(post_id: 3).delete_all.should eq(2)
          PostStat.query.count.should eq(0)
        ensure
          clear_post_stats
        end
      end

      it "runs wrapped aggregates on the secondary database" do
        clear_post_stats

        begin
          PostStat.create!(post_id: 10)
          PostStat.create!(post_id: 20)

          query = PostStat.query.order_by(:id).limit(1)
          query.count.should eq(1)
          query.sum("post_id").should eq(10.0)
        ensure
          clear_post_stats
        end
      end

      it "checks existence on the secondary database" do
        clear_post_stats

        begin
          PostStat.query.exists?.should be_false
          PostStat.create!(post_id: 1)
          PostStat.query.exists?.should be_true
        ensure
          clear_post_stats
        end
      end

      it "reloads an incremented value from the secondary database" do
        clear_post_stats

        begin
          post_stat = PostStat.create!(post_id: 1)
          post_stat.increment!(:post_id)

          post_stat.post_id.should eq(2)
        ensure
          clear_post_stats
        end
      end

      it "updates counter caches on the secondary database" do
        drop_counter_tables
        create_counter_tables

        begin
          parent = CounterParent.create!
          CounterChild.create!(owner: parent)

          parent.reload.children_count.should eq(1)
        ensure
          drop_counter_tables
        end
      end

      it "resets counter caches on the secondary database" do
        drop_counter_tables
        create_counter_tables

        begin
          parent = CounterParent.create!
          Lustra::SQL.insert_into("secondary_counter_children", {parent_id: parent.id}).execute("secondary")

          parent.reset_counters(CounterChild)
          parent.children_count.should eq(1)
        ensure
          drop_counter_tables
        end
      end
    end
  end
end
