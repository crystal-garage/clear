require "../spec_helper"
require "../data/example_models"

# Monkey patch of QueryCache
# For adding statistics
# during spec
class Lustra::Model::QueryCache
  class_getter cache_hitted : Int32 = 0

  def hit(relation_name, relation_value, klass : T.class) : Array(T) forall T
    @@cache_hitted += 1
    previous_def
  end

  def self.reset_counter
    @@cache_hitted = 0
  end
end

module CacheSpec
  def self.reinit
    reinit_example_models

    User.create! id: 101, first_name: "User 1"
    User.create! id: 102, first_name: "User 2"

    Category.create! id: 201, name: "Test"
    Category.create! id: 202, name: "Test 2"

    Post.create! id: 301, title: "post 301", published: true, user_id: 101, category_id: 201, content: "Lorem ipsum"
    Post.create! id: 302, title: "post 302", published: true, user_id: 102, category_id: 201, content: "Lorem ipsum"
    Post.create! id: 303, title: "post 303", published: true, user_id: 102, category_id: 202, content: "Lorem ipsum"
    Post.create! id: 304, title: "post 304", published: true, user_id: 101, category_id: 202, content: "Lorem ipsum"
  end

  describe "Lustra::Model" do
    context "cache system" do
      it "eager loads associations for each filtered duplicate" do
        temporary do
          reinit
          base = User.query.with_posts
          first = base.dup.where(id: 101).to_a
          second = base.dup.where(id: 102).to_a

          first.map(&.id).should eq([101])
          second.map(&.id).should eq([102])
          first.first.cache.not_nil!.hit("posts", 102_i64, Post).should be_empty
          second.first.cache.not_nil!.hit("posts", 101_i64, Post).should be_empty
          Lustra::Model::QueryCache.reset_counter

          first.first.posts.map(&.id).sort.should eq([301, 304])
          second.first.posts.map(&.id).sort.should eq([302, 303])
          Lustra::Model::QueryCache.cache_hitted.should eq(2)
        end
      end

      it "preserves belongs_to, has_one, and through eager loading on duplicates" do
        temporary do
          reinit
          UserInfo.create!(user_id: 101, registration_number: 123)

          post = Post.query.with_user.dup.where(id: 301).to_a.first
          user = User.query.with_info.dup.where(id: 101).to_a.first
          category = Category.query.with_users.dup.where(id: 201).to_a.first
          Lustra::Model::QueryCache.reset_counter

          post.user.id.should eq(101)
          user.info!.registration_number.should eq(123)
          category.users.map(&.id).sort.should eq([101, 102])
          Lustra::Model::QueryCache.cache_hitted.should eq(3)
        end
      end

      it "preserves polymorphic belongs_to eager loading on duplicates" do
        temporary do
          reinit_example_models
          employee = Employee.create!(id: 101, name: "Employee")
          product = Product.create!(id: 101, name: "Product")
          Picture.create!(name: "employee", imageable_id: employee.id, imageable_type: "Employee")
          Picture.create!(name: "product", imageable_id: product.id, imageable_type: "Product")

          pictures = Picture.query.with_imageable.dup.order_by(:name).to_a
          Lustra::Model::QueryCache.reset_counter

          pictures.first.imageable.as(Employee).id.should eq(employee.id)
          pictures.last.imageable.as(Product).id.should eq(product.id)
          Lustra::Model::QueryCache.cache_hitted.should eq(2)
        end
      end

      it "manage has_many relations" do
        temporary do
          reinit
          Lustra::Model::QueryCache.reset_counter
          # relations has_many
          User.query.first!.posts.count.should eq(2)
          User.query.with_posts(&.published.with_category).each do |user|
            Lustra::Model::QueryCache.reset_counter
            user.posts.count.should eq(2)
            Lustra::Model::QueryCache.cache_hitted.should eq(1)
          end
        end
      end

      it "be chained" do
        temporary do
          reinit
          Lustra::Model::QueryCache.reset_counter
          User.query.with_posts(&.with_category).each do |user|
            user.posts.each do |p|
              case p.id
              when 301, 302
                p.category.id.should eq 201
              when 303, 304
                p.category.id.should eq 202
              end
            end
          end
        end
      end

      it "be called in chain on the through relations" do
        temporary do
          reinit
          # Relation belongs_to
          Lustra::Model::QueryCache.reset_counter
          Post.query.with_user.each do |post|
            post.user.should_not be_nil
          end
          Lustra::Model::QueryCache.cache_hitted.should eq(4) # Number of posts

          Category.query.with_users(&.order_by("users.id", :asc)).order_by("id", :asc).each do |c|
            c.id.should_not be_nil
            c.users.each do |user|
              user.id.should_not be_nil
            end
          end
        end
      end

      it "manage polymorphic belongs_to relations" do
        temporary do
          reinit_example_models

          employee = Employee.create!(id: 101, name: "Employee")
          product = Product.create!(id: 101, name: "Product")

          Picture.create!(
            name: "employee picture",
            imageable_id: employee.id,
            imageable_type: "Employee"
          )
          Picture.create!(
            name: "product picture",
            imageable_id: product.id,
            imageable_type: "Product"
          )

          Lustra::Model::QueryCache.reset_counter

          Picture.query.with_imageable.order_by(:name).each do |picture|
            case picture.imageable_type
            when "Employee"
              picture.imageable.as(Employee).id.should eq(employee.id)
            when "Product"
              picture.imageable.as(Product).id.should eq(product.id)
            end
          end

          Lustra::Model::QueryCache.cache_hitted.should eq(2)
        end
      end
    end
  end
end
