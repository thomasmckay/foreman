class MigratePermissions < ActiveRecord::Migration
  def self.up
    if old_permissions_present
      migrate_roles
      migrate_user_filters
    else
      say 'Skipping migration of permissions, since old permissions are not present'
    end
  end

  # STEP 1 - migrate roles
  # for all role permissions we'll create unlimited filters
  # we'll group permissions into filters by their resource
  def self.migrate_roles
    roles = Role.all
    roles.each do |role|

      # role without permissions? nothing to do then
      if role.attributes['permissions'].nil?
        say "no old permissions found for role '#{role.name}', skipping"
        next
      end

      # permissions assigned to role which we want to migrate
      permission_names = YAML.load(role.attributes['permissions'])

      # role without permissions but with YAML record
      if permission_names.blank?
        clear_old_permission(role)
        next
      end

      # filter out unknown permissions, this could be leftovers from an old plugin.
      role_permissions = Permission.where(:name => permission_names)

      # we group permissions by resource the belong to
      # then create a filter per resource
      # and create a new relation between mapped permission and this filter
      role_permissions.group_by(&:resource_type).each do |resource, permissions|
        filter      = Filter.new
        filter.role = role
        filter.save!
        say "Created an unlimited filter for role '#{role.name}'"

        permissions.each do |permission|
          filtering            = Filtering.new
          filtering.filter     = filter
          filtering.permission = Permission.find_by_name(permission.name)
          filtering.save!
          say "... with permission '#{permission.name}'"
        end
      end

      # finally we clear old permissions from role so
      clear_old_permission(role)
    end
  end

  def self.clear_old_permission(role)
    say "Clearing old permissions for role '#{role.name}'"
    if Role.update_all("permissions = NULL", "id = #{role.id}") == 1
      say "... OK"
    else
      raise "could not clear old permissions for role '#{role.name}'"
    end
  end

  # STEP 2 - migrate user filters
  # for every user having a filter we make copy of all his roles and add filtering scoped searches
  # to corresponding filters
  def self.migrate_user_filters
    users = User.all
    users.each do |user|
      unless filtered?(user)
        say "no filters found for user '#{user.login}', skipping"
        next
      end

      say "Migrating user '#{user.login}'"
      say "... cloning all roles"
      clones     = user.roles.builtin(false).map { |r| clone_role(r, user) }
      user.roles = clones + user.roles.builtin(true)
      say "... done"

      filters                     = Hash.new { |h, k| h[k] = '' }

      # compute resources
      filters[:compute_resrouces] = search = user.compute_resources.uniq.map { |cr| "id = #{cr.id}" }.join(' or ')
      affected                    = clones.map(&:filters).flatten.select { |f| f.resource_type == 'ComputeResource' }
      affected.each do |filter|
        filter.update_attributes :search => search unless search.blank?
      end
      say "... compute resource filters applied"

      # domains were not limited in old system, to keep it compatible, we don't convert it and use just search string
      # later for hosts
      filters[:domains]    = user.domains.uniq.map { |cr| "id = #{cr.id}" }.join(' or ')

      # host groups
      filters[:hostgroups] = search = user.hostgroups.uniq.map { |cr| "id = #{cr.id}" }.join(' or ')
      affected             = clones.map(&:filters).flatten.select { |f| f.resource_type == 'Hostgroup' }
      affected.each do |filter|
        filter.update_attributes :search => search unless search.blank?
      end
      say "... hostgroups filters applied"

      # fact_values for hosts scope
      filters[:facts] = user.user_facts.uniq.map { |uf| "facts.#{uf.fact_name.name} #{uf.operator} #{uf.criteria}" }.join(' or ')

      search = convert_filters_to_search(filters, user)

      affected = clones.map(&:filters).flatten.select { |f| f.resource_type == 'Host' }
      affected.each do |filter|
        filter.update_attributes :search => search unless search.blank?
      end
      say "... all other filters applied"

      say "Removing old filter"
      user.domains           = []
      user.compute_resources = []
      user.hostgroups        = []
      user.facts             = []
      user.filter_on_owner   = false
      user.save!
      say "... done"
    end
  end

  def self.convert_filters_to_search(filters, user)
    search = ''

    # owner_type
    if user.filter_on_owner
      user_cond = "owner_id = #{user.id} and owner_type = User"
      group_cond = user.cached_usergroups.uniq.map { |g| "owner_id = #{g.id}" }.join(' or ')
      search = "(#{user_cond})"
      search += " or ((#{group_cond}) and owner_type = Usergroup)" unless group_cond.blank?
    end

    # normal filters - domains, compute resource, hostgroup, facts
    filter = filters[:domains].gsub('id', 'domain_id')
    search = "(#{search}) #{user.domains_andor} (#{filter})" unless filter.blank?
    filter = filters[:compute_resources].gsub('id', 'compute_resource_id')
    search = "(#{search}) #{user.compute_resources_andor} (#{filter})" unless filter.blank?
    filter = filters[:hostgroups].gsub('id', 'hostgroup_id')
    search = "(#{search}) #{user.hostgroups_andor} (#{filter})" unless filter.blank?
    filter = filters[:facts]
    search = "(#{search}) #{user.facts_andor} (#{filter})" unless filter.blank?

    # taxonomies
    if SETTINGS[:organizations_enabled]
      filter = user.organizations.map { |o| "organization_id = #{o.id}" }.join(' or ')
      search = "(#{search}) #{user.organizations_andor} (#{filter})" unless filter.blank?
    end
    if SETTINGS[:locations_enabled]
      filter = user.locations.map { |o| "location_id = #{o.id}" }.join(' or ')
      search = "(#{search}) #{user.locations_andor} (#{filter})" unless filter.blank?
    end

    # fix first and/or that could appear
    search = search.sub(/^\s*(and|or)\s*/, '')
    search
  end

  def self.filtered?(user)
    user.compute_resources.present? ||
        user.domains.present? ||
        user.hostgroups.present? ||
        user.facts.present? ||
        user.filter_on_owner
  end

  def self.clone_role(role, user)
    clone      = role.dup
    clone.name = role.name + "_#{user.login}"
    clone.save!

    role.filters.each { |f| clone_filter(f, clone) }

    clone.reload
  end

  def self.clone_filter(filter, role)
    clone             = filter.dup
    clone.permissions = filter.permissions
    clone.role        = role
    clone.save!
  end


  def self.old_permissions_present
    user = User.new
    Role.column_names.include?('permissions') &&
        user.respond_to?(:compute_resources) &&
        user.respond_to?(:domains) &&
        user.respond_to?(:hostgroups) &&
        user.respond_to?(:facts) &&
        user.respond_to?(:filter_on_owner)
  end

  def self.down

  end
end
