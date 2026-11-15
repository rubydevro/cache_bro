Rails.application.routes.draw do
  root "home#index"
  post "role" => "home#role", as: :role

  # The dashboard shell: CacheBro lives at /bro_hub/cache_bro.
  mount BroHub::Engine => "/bro_hub"
  # A host that mounts CacheBro on its own keeps working (standalone shell with only CacheBro's section).
  mount CacheBro::Engine => "/cache"
end
