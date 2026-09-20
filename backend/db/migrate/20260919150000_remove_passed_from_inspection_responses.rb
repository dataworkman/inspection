# "Passed" used to be a switch the inspector flipped independently of the score,
# so a 5/5 item could read "Review". It is now derived from the score
# (InspectionResponse#passed), so the stored flag goes away.
class RemovePassedFromInspectionResponses < ActiveRecord::Migration[8.1]
  def change
    remove_column :inspection_responses, :passed, :boolean
  end
end
