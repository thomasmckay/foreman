class HostgroupsController < ApplicationController
  include Foreman::Controller::HostDetails
  include Foreman::Controller::AutoCompleteSearch

  def index
    @hostgroups = Hostgroup.authorized(:view_hostgroups).my_groups.search_for(params[:search], :order => params[:order]).paginate(:page => params[:page])
  end

  def new
    @hostgroup = Hostgroup.new
  end

  def nest
    @parent = @hostgroup = find_hostgroup
    @hostgroup = @parent.dup
    #overwrite parent_id and name
    @hostgroup.parent_id = params[:id]
    @hostgroup.name = ""

    load_vars_for_ajax
    @hostgroup.puppetclasses = @parent.puppetclasses
    @hostgroup.locations = @parent.locations
    @hostgroup.organizations = @parent.organizations
    # Clone any parameters as well
    @hostgroup.group_parameters.each{|param| @parent.group_parameters << param.dup}
    render :action => :new
  end

  # Clone the hostgroup
  def clone
    @hostgroup = find_hostgroup
    new = @hostgroup.dup
    load_vars_for_ajax
    new.puppetclasses = @hostgroup.puppetclasses
    new.locations = @hostgroup.locations
    new.organizations = @hostgroup.organizations
    # Clone any parameters as well
    @hostgroup.group_parameters.each{|param| new.group_parameters << param.dup}
    new.name = ""
    new.valid?
    @hostgroup = new
    notice _("The following fields would need reviewing")
    render :action => :new
  end

  def create
    @hostgroup = Hostgroup.new(params[:hostgroup])
    if @hostgroup.save
      # Add the new hostgroup to the user's filters
      @hostgroup.users << User.current unless User.current.admin? or @hostgroup.users.include?(User.current)
      @hostgroup.users << subscribed_users
      @hostgroup.users << users_in_ancestors
      process_success
    else
      load_vars_for_ajax
      process_error
    end
  end

  def edit
    @hostgroup = find_hostgroup(:edit_hostgroups)
    load_vars_for_ajax
  end

  def update
    @hostgroup = find_hostgroup(:edit_hostgroups)
    # remove from hash :root_pass if blank?
    params[:hostgroup].except!(:root_pass) if params[:hostgroup][:root_pass].blank?
    if @hostgroup.update_attributes(params[:hostgroup])
      process_success
    else
      load_vars_for_ajax
      process_error
    end
  end

  def destroy
    @hostgroup = find_hostgroup(:destroy_hostgroups)
    begin
      if @hostgroup.destroy
        process_success
      else
        load_vars_for_ajax
        process_error
      end
    rescue Ancestry::AncestryException
      flash[:error] = _("Cannot delete group %{current} because it has nested groups.") % { :current => @hostgroup.label }
      process_error
    end
  end

  def environment_selected
    return not_found unless (@environment = Environment.find(params[:environment_id])) if params[:environment_id].to_i > 0

    @hostgroup ||= Hostgroup.new
    @hostgroup.environment = @environment if @environment
    render :partial => 'puppetclasses/class_selection', :locals => {:obj => (@hostgroup)}
  end

  def process_hostgroup

    @parent = Hostgroup.authorized(:view_hostgroups).find(params[:hostgroup][:parent_id]) if params[:hostgroup][:parent_id].to_i > 0
    return head(:not_found) unless @parent

    @hostgroup = Hostgroup.new(params[:hostgroup])
    @hostgroup.architecture       ||= @parent.architecture
    @hostgroup.operatingsystem    ||= @parent.operatingsystem
    @hostgroup.domain             ||= @parent.domain
    @hostgroup.subnet             ||= @parent.subnet
    @hostgroup.environment        ||= @parent.environment

    load_vars_for_ajax
    render :partial => "form"
  end

  def taxonomy_scope
    @organization = Organization.current if SETTINGS[:organizations_enabled]
    @location     = Location.current     if SETTINGS[:locations_enabled]
  end

  private

  def find_hostgroup(permission = :view_hostgroups)
    Hostgroup.authorized(permission).find(params[:id])
  end

  def load_vars_for_ajax
    return unless @hostgroup
    @architecture    = @hostgroup.architecture
    @operatingsystem = @hostgroup.operatingsystem
    @domain          = @hostgroup.domain
    @subnet          = @hostgroup.subnet
    @environment     = @hostgroup.environment
  end

  def users_in_ancestors
    @hostgroup.ancestors.map do |ancestor|
      ancestor.users.reject { |u| @hostgroup.users.include?(u) }
    end.flatten.uniq
  end

  def subscribed_users
    User.where(:subscribe_to_all_hostgroups => true)
  end

end
