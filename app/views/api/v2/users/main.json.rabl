object @user

extends "api/v2/users/base"

attributes :firstname, :lastname, :mail, :admin, :auth_source_id, :auth_source_name, :last_login_on, :created_at, :updated_at

child :organizations => :organizations do
     attributes :id, :name
end

child :locations => :locations do
     attributes :id, :name
end

child :roles => :roles do
     attributes :id, :name
end
