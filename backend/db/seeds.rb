User.find_or_create_by!(email: "admin@storepilot.test") do |user|
  user.name = "Admin User"
  user.role = "admin"
  user.password = "password123"
end

User.find_or_create_by!(email: "inspector@storepilot.test") do |user|
  user.name = "Field Inspector"
  user.role = "inspector"
  user.password = "password123"
end

[
  [ "Downtown Market", "DT-001", "101 Main Street" ],
  [ "Riverside Store", "RV-002", "22 River Road" ],
  [ "Uptown Express", "UP-003", "88 North Avenue" ]
].each do |name, code, address|
  Store.find_or_create_by!(code: code) do |store|
    store.name = name
    store.address = address
    store.active = true
  end
end

template = ChecklistTemplate.find_or_create_by!(title: "MVP Store Inspection") do |checklist_template|
  checklist_template.active = true
end

[
  [ "Exterior", "Entrance, signage, and windows are clean", 2 ],
  [ "Food Safety", "Cold holding temperatures are logged", 4 ],
  [ "Food Safety", "Open products are labeled and dated", 4 ],
  [ "Operations", "Checkout area is stocked and clear", 2 ],
  [ "Operations", "Back room walkways are clear", 2 ],
  [ "Customer Experience", "Restrooms are clean and supplied", 3 ],
  [ "Customer Experience", "Promotional displays match current plan", 1 ]
].each_with_index do |(category, title, weight), index|
  ChecklistItem.find_or_create_by!(checklist_template: template, title: title) do |item|
    item.category = category
    item.weight = weight
    item.position = index + 1
  end
end

puts "Seeded #{User.count} users, #{Store.count} stores, and #{ChecklistItem.count} checklist items."
