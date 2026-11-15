# Stand-in for the host app's user model.
class User
  PERMISSIONS = {
    "viewer" => %i[ view_keys ],
    "developer" => %i[ view_keys view_values delete ],
    "lead" => %i[ purge ],
    "admin" => %i[ flush audit ],
    "auditor" => %i[ audit ]
  }.freeze
  ROLES = PERMISSIONS.keys.freeze

  attr_reader :role

  def self.for_role(role)
    new(role) if ROLES.include?(role)
  end

  def initialize(role)
    @role = role
  end

  def email
    "#{role}@example.com"
  end

  def can?(permission)
    PERMISSIONS.fetch(role).include?(permission)
  end
end
