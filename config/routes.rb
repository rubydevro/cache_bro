CacheBro::Engine.routes.draw do
  root "keys#index"

  # Keys can contain slashes, so they travel as a parameter, not in the path.
  get "key" => "keys#show", as: :key
  post "key/reveal" => "keys#reveal", as: :reveal_key
  delete "key" => "keys#destroy"

  get "purge" => "purges#new", as: :purge
  post "purge/preview" => "purges#preview", as: :purge_preview
  post "purge" => "purges#create"

  get "flush" => "flushes#new", as: :flush
  post "flush" => "flushes#create"

  get "audit" => "audit_events#index", as: :audit
  get "audit/:id" => "audit_events#show", as: :audit_event
end
