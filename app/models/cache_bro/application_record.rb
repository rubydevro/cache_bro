module CacheBro
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = "cache_bro_"
  end
end
