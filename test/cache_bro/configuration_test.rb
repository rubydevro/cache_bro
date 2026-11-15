require "test_helper"

class CacheBro::ConfigurationTest < ActiveSupport::TestCase
  setup { @config = CacheBro::Configuration.new }

  def user_with(*permissions)
    @config.can_view_keys = ->(_) { permissions.include?(:view_keys) }
    @config.can_view_values = ->(_) { permissions.include?(:view_values) }
    @config.can_delete = ->(_) { permissions.include?(:delete) }
    @config.can_purge = ->(_) { permissions.include?(:purge) }
    @config.can_flush = ->(_) { permissions.include?(:flush) }
    @config.can_audit = ->(_) { permissions.include?(:audit) }
    Object.new
  end

  test "everything is denied by default" do
    user = Object.new
    CacheBro::Configuration::PERMISSIONS.each { |permission| assert_not @config.allows?(user, permission), permission.to_s }
  end

  test "nobody signed in has no permissions" do
    user_with(*CacheBro::Configuration::PERMISSIONS)
    CacheBro::Configuration::PERMISSIONS.each { |permission| assert_not @config.allows?(nil, permission) }
  end

  test "higher permissions include the lower ones" do
    assert @config.allows?(user_with(:flush), :purge)
    assert @config.allows?(user_with(:flush), :delete)
    assert @config.allows?(user_with(:flush), :view_keys)
    assert @config.allows?(user_with(:purge), :delete)
    assert @config.allows?(user_with(:purge), :view_keys)
    assert @config.allows?(user_with(:delete), :view_keys)
    assert @config.allows?(user_with(:view_values), :view_keys)
  end

  test "lower permissions don't include the higher ones" do
    assert_not @config.allows?(user_with(:delete), :purge)
    assert_not @config.allows?(user_with(:purge), :flush)
    assert_not @config.allows?(user_with(:view_keys), :delete)
  end

  test "revealing values and auditing stand alone" do
    assert_not @config.allows?(user_with(:flush), :view_values)
    assert_not @config.allows?(user_with(:purge), :view_values)
    assert_not @config.allows?(user_with(:flush), :audit)
    assert_not @config.allows?(user_with(:audit), :view_keys)
    assert_not @config.allows?(user_with(:view_values), :delete)
  end

  test "an unknown permission is a mistake, not a denial" do
    assert_raises(ArgumentError) { @config.allows?(Object.new, :explode) }
  end

  test "purge and flush need a reason by default" do
    assert @config.reason_required?(:purge)
    assert @config.reason_required?(:flush)
    assert_not @config.reason_required?(:delete)
    assert_not @config.reason_required?(:reveal)
  end

  test "the default store is Rails.cache" do
    assert_equal [ "Rails.cache" ], @config.store_names
  end
end
