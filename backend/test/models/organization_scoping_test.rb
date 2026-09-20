require "test_helper"

class OrganizationScopingTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(name: "Group A")
    @other = Organization.create!(name: "Group B")
    @user = User.create!(organization: @org, name: "Inspector", email: "scope@example.com", password: "password123", role: "inspector")
    @store = @org.stores.create!(name: "Store", store_code: "SC-1")
    @template = @org.inspection_templates.create!(name: "T")
  end

  test "users, stores and inspections need an organization" do
    assert_not User.new(name: "X", email: "x@example.com", password: "password123", role: "admin").valid?
    assert_not Store.new(name: "X", store_code: "X-1").valid?
    assert_not Inspection.new(store: @store, user: @user, status: "in_progress").valid?
  end

  test "the database refuses rows without an organization even when validations are skipped" do
    assert_raises(ActiveRecord::NotNullViolation) do
      User.new(name: "X", email: "x@example.com", password: "password123", role: "admin").save!(validate: false)
    end
    assert_raises(ActiveRecord::NotNullViolation) { Store.new(name: "X", store_code: "X-1").save!(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) do
      Inspection.new(store: @store, user: @user, status: "in_progress").save!(validate: false)
    end
  end

  test "an inspection cannot point at another organization's store, template or people" do
    foreign_store = @other.stores.create!(name: "Theirs", store_code: "TH-1")
    foreign_template = @other.inspection_templates.create!(name: "Theirs")
    foreign_user = User.create!(organization: @other, name: "Them", email: "them@example.com", password: "password123", role: "inspector")

    {
      store: { store: foreign_store },
      inspection_template: { inspection_template: foreign_template },
      user: { user: foreign_user },
      inspector: { inspector: foreign_user }
    }.each do |field, override|
      inspection = Inspection.new({ organization: @org, store: @store, inspection_template: @template, user: @user, inspector: @user, status: "in_progress" }.merge(override))

      assert_not inspection.valid?, "#{field} from another organization was accepted"
      assert_includes inspection.errors[field], "must belong to the same organization"
    end
  end

  test "an inspection made of its own organization's parts is valid" do
    inspection = Inspection.new(organization: @org, store: @store, inspection_template: @template, user: @user, inspector: @user, status: "in_progress")

    assert inspection.valid?
  end
end
