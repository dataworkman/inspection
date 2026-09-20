# Every user, store and inspection belongs to an organization. The columns were
# added later as nullable, and the application only guarded against nil at
# request time; enforce it in the database instead.
class RequireOrganizationOnCoreTables < ActiveRecord::Migration[8.1]
  TABLES = %i[users stores inspections].freeze

  def up
    TABLES.each do |table|
      orphans = select_value("SELECT COUNT(*) FROM #{table} WHERE organization_id IS NULL").to_i
      next if orphans.zero?

      raise "Cannot require organization_id on #{table}: #{orphans} row(s) have none. " \
            "Assign them to an organization (or remove them) first."
    end

    TABLES.each { |table| change_column_null table, :organization_id, false }
  end

  def down
    TABLES.each { |table| change_column_null table, :organization_id, true }
  end
end
