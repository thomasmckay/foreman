class AddTaxonomySearchesToFilter < ActiveRecord::Migration
  def self.up
    add_column :filters, :taxonomy_search, :text
    # to precache taxonomy search on all existing filters
    Filter.reset_column_information
    Filter.all.each(&:save!)
  end

  def self.down
  end
end
