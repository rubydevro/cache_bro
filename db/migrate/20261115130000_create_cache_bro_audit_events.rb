class CreateCacheBroAuditEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :cache_bro_audit_events do |t|
      t.string :event, null: false
      t.string :user_label
      t.string :environment, null: false
      t.string :store, null: false

      # The key (reveal, delete) or the pattern (purge). Empty for a flush.
      t.text :target
      # How many keys the action touched.
      t.integer :count
      t.text :reason

      # No column default: MySQL rejects defaults on JSON columns. Audit.record always sets it.
      t.json :details, null: false

      t.datetime :created_at, null: false
    end

    add_index :cache_bro_audit_events, :created_at
    add_index :cache_bro_audit_events, [ :event, :created_at ]
    add_index :cache_bro_audit_events, [ :user_label, :created_at ]
  end
end
