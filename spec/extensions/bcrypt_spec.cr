require "../spec_helper"

module BCryptSpec
  extend self

  class EncryptedPasswordMigration57632
    include Clear::Migration

    def change(dir)
      create_table(:bcrypt_users, id: :uuid) do |t|
        t.column "encrypted_password", "string"
      end
    end
  end

  class User
    include Clear::Model

    primary_key :id, type: :uuid

    self.table = "bcrypt_users"

    column encrypted_password : Crypto::Bcrypt::Password
  end

  def self.reinit!
    reinit_migration_manager

    EncryptedPasswordMigration57632.new.apply
  end

  describe "Clear::Migration::CreateEnum" do
    it "create bcrypt password" do
      temporary do
        reinit!

        User.create!({encrypted_password: Crypto::Bcrypt::Password.create("abcd")})

        User.query.count.should eq 1
        User.query.first!.encrypted_password.verify("abcd").should be_true
        User.query.first!.encrypted_password.verify("abce").should be_false

        usr = User.query.first!

        usr.encrypted_password = Crypto::Bcrypt::Password.create("lorem.ipsum")
        usr.save!

        User.query.first!.encrypted_password.verify("abcd").should be_false
        User.query.first!.encrypted_password.verify("lorem.ipsum").should be_true
      end
    end

    it "create bcrypt password with cquery" do
      temporary do
        reinit!

        User.query.create!(encrypted_password: Crypto::Bcrypt::Password.create("abcd"))

        User.query.count.should eq 1
        User.query.first!.encrypted_password.verify("abcd").should be_true
        User.query.first!.encrypted_password.verify("abce").should be_false
      end
    end

    it "assign bcrypt password" do
      temporary do
        reinit!

        old_password = "foo"
        new_password = "bar"

        User.create!({encrypted_password: Crypto::Bcrypt::Password.create(old_password)})

        User.query.count.should eq 1

        usr = User.query.first!

        usr.encrypted_password = Crypto::Bcrypt::Password.create(new_password)
        usr.save!

        User.query.first!.encrypted_password.verify(old_password).should be_false
        User.query.first!.encrypted_password.verify(new_password).should be_true
      end
    end

    it "export to json" do
      temporary do
        reinit!

        User.query.create!({encrypted_password: Crypto::Bcrypt::Password.create("abcd")})
        u = User.query.first!
        u.to_json.should contain %<,"encrypted_password":">
      end
    end
  end
end
