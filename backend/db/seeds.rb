organization = Organization.find_or_create_by!(name: "Demo Bakery Group")

admin = User.find_or_create_by!(email: "admin@bakery-inspection.test") do |user|
  user.organization = organization
  user.name = "HQ Admin"
  user.role = "admin"
  user.password = "password123"
end

inspector = User.find_or_create_by!(email: "inspector@bakery-inspection.test") do |user|
  user.organization = organization
  user.name = "Inspector A"
  user.role = "inspector"
  user.password = "password123"
end

manager = User.find_or_create_by!(email: "manager@bakery-inspection.test") do |user|
  user.organization = organization
  user.name = "Downtown Manager"
  user.role = "store_manager"
  user.password = "password123"
end

[
  [ "Downtown Bakery", "DT-BKY", "101 Main Street", "555-0101" ],
  [ "Midtown Bakery", "MT-BKY", "22 Center Avenue", "555-0102" ],
  [ "Airport Bakery", "AP-BKY", "3 Terminal Road", "555-0103" ]
].each do |name, store_code, address, phone|
  organization.stores.find_or_create_by!(store_code: store_code) do |store|
    store.name = name
    store.address = address
    store.phone = phone
    store.active = true
  end
end

template = organization.inspection_templates.find_or_create_by!(name: "Bakery Standard Inspection") do |inspection_template|
  inspection_template.description = "Bakery Standard Inspection v1"
  inspection_template.version = 1
  inspection_template.active = true
end

category_data = {
  "Cleanliness" => {
    weight: 30,
    questions: [
      "Floor cleanliness",
      "Counter cleanliness",
      "Equipment cleanliness",
      "Display case cleanliness",
      "Employee hygiene"
    ]
  },
  "Product Quality" => {
    weight: 30,
    questions: [
      "Bread appearance",
      "Freshness",
      "Display quality",
      "Product availability",
      "Packaging"
    ]
  },
  "Service" => {
    weight: 25,
    questions: [
      "Customer greeting",
      "Service speed",
      "Staff attitude",
      "Product knowledge",
      "Line handling"
    ]
  },
  "Facility" => {
    weight: 15,
    questions: [
      "Lighting",
      "Furniture condition",
      "Signage",
      "Restroom",
      "Safety"
    ]
  }
}

category_data.each_with_index do |(name, data), category_index|
  category = template.inspection_categories.find_or_create_by!(name: name) do |inspection_category|
    inspection_category.weight = data[:weight]
    inspection_category.position = category_index + 1
  end

  data[:questions].each_with_index do |title, question_index|
    category.inspection_questions.find_or_create_by!(title: title) do |question|
      question.description = "#{title} meets Demo Bakery Group standards."
      question.max_score = 5
      question.weight = 1
      question.required = true
      question.photo_required = question_index.zero?
      question.comment_required = question_index == 1
      question.position = question_index + 1
    end
  end
end

puts "Seeded #{Organization.count} organization, #{User.count} users, #{Store.count} stores, #{InspectionTemplate.count} templates, #{InspectionQuestion.count} questions."
