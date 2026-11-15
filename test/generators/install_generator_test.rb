require "test_helper"
require "generators/cache_bro/install/install_generator"

class CacheBro::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests CacheBro::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup do
    prepare_destination
    FileUtils.mkdir_p File.join(destination_root, "config")
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "creates the initializer with everything denied" do
    run_install
    assert_file "config/initializers/cache_bro.rb" do |content|
      %w[ view_keys view_values delete purge flush audit ].each do |permission|
        assert_match(/config\.can_#{permission} = ->\(user\) \{ false \}/, content)
      end
    end
  end

  test "keeps an initializer that is already there" do
    FileUtils.mkdir_p File.join(destination_root, "config/initializers")
    File.write(File.join(destination_root, "config/initializers/cache_bro.rb"), "# mine\n")
    run_install
    assert_file "config/initializers/cache_bro.rb", /\A# mine\n\z/
  end

  test "sets up BroHub instead of mounting CacheBro itself" do
    run_install
    assert_file "config/initializers/bro_hub.rb"
    assert_file "config/routes.rb" do |content|
      assert_match %r{mount BroHub::Engine => "/bro_hub"}, content
      assert_no_match(/CacheBro::Engine/, content)
    end
  end

  test "says where CacheBro ended up" do
    output = run_install "--mount-path=/ops/bro"
    assert_match %r{/ops/bro/cache_bro}, output
  end

  private
    # Migrations are copied by the engine's rake task, which needs a real host app.
    def run_install(*args)
      install = generator([], args, destination_root: destination_root)
      def install.copy_migrations; end
      capture(:stdout) { install.invoke_all }
    end
end
