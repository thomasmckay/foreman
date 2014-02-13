class ComputeResourcesController < ApplicationController
  include Foreman::Controller::AutoCompleteSearch
  AJAX_REQUESTS = %w{template_selected cluster_selected}
  before_filter :ajax_request, :only => AJAX_REQUESTS

  def index
    @compute_resources = ComputeResource.authorized(:view_compute_resources).search_for(params[:search], :order => params[:order]).paginate :page => params[:page]
  end

  def new
    @compute_resource = ComputeResource.new
  end

  def show
    @compute_resource = find_by_id
  end

  def create
    if params[:compute_resource].present? && params[:compute_resource][:provider].present?
      @compute_resource = ComputeResource.new_provider params[:compute_resource]
      if @compute_resource.save
        # Add the new compute resource to the user's filters
        @compute_resource.users << User.current
        process_success :success_redirect => @compute_resource
      else
        process_error
      end
    else
      @compute_resource = ComputeResource.new params[:compute_resource]
      @compute_resource.valid?
      process_error
    end
  end

  def edit
    @compute_resource = find_by_id(:edit_compute_resources)
  end

  def associate
    @compute_resource = find_by_id(:edit_compute_resources)
    count = 0
    if @compute_resource.respond_to?(:associated_host)
      @compute_resource.vms(:eager_loading => true).each do |vm|
        if Host.where(:uuid => vm.identity).empty?
          host = @compute_resource.associated_host(vm)
          if host.present?
            host.uuid = vm.identity
            host.compute_resource_id = @compute_resource.id
            host.save!(:validate => false) # don't want to trigger callbacks
            count += 1
          end
        end
      end
    end
    process_success(:success_msg => n_("%s VM associated to a host", "%s VMs associated to hosts", count) % count)
  end

  def update
    @compute_resource = find_by_id(:edit_compute_resources)
    params[:compute_resource].except!(:password) if params[:compute_resource][:password].blank?
    if @compute_resource.update_attributes(params[:compute_resource])
      process_success
    else
      process_error
    end
  end

  def destroy
    @compute_resource = find_by_id(:destroy_compute_resources)
    if @compute_resource.destroy
      process_success
    else
      process_error
    end
  end

  #ajax methods
  def provider_selected
    @compute_resource = ComputeResource.new_provider :provider => params[:provider]
    render :partial => "compute_resources/form", :locals => { :compute_resource => @compute_resource }
  end

  def ping
    @compute_resource = find_by_id
    respond_to do |format|
      format.json {render :json => errors_hash(@compute_resource.ping)}
    end
  end

  def test_connection
    # cr_id is posted from AJAX function. cr_id is nil if new
    Rails.logger.info "CR_ID IS #{params[:cr_id]}"
    if params[:cr_id].present? && params[:cr_id] != 'null'
      @compute_resource = ComputeResource.authorized(:edit_compute_resources).find(params[:cr_id])
      params[:compute_resource].delete(:password) if params[:compute_resource][:password].blank?
      @compute_resource.attributes = params[:compute_resource]
    else
      @compute_resource = ComputeResource.new_provider(params[:compute_resource])
    end
    @compute_resource.test_connection :force => true
    render :partial => "compute_resources/form", :locals => { :compute_resource => @compute_resource }
  end

  def template_selected
    @compute_resource = find_by_id
    compute = @compute_resource.template(params[:template_id])
    compute.interfaces
    compute.volumes
    respond_to do |format|
      format.json { render :json => compute }
    end
  end

  def cluster_selected
    @compute_resource = find_by_id
    networks = @compute_resource.networks(:cluster_id => params[:cluster_id])
    respond_to do |format|
      format.json { render :json => networks }
    end
  end

  private

  def find_by_id(permission = :view_compute_resources)
    compute_resource = ComputeResource.authorized(permission).find(params[:id])
    not_found and return unless compute_resource
    compute_resource
  end
end
