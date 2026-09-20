require "test_helper"

class ApiV1PhotoSecurityTest < ActionDispatch::IntegrationTest
  PNG_1PX = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  setup do
    @org = Organization.create!(name: "Photo Group")
    @inspector = User.create!(organization: @org, name: "Inspector", email: "photo-inspector@example.com", password: "password123", role: "inspector")
    store = @org.stores.create!(name: "Store", store_code: "PH-1")
    template = @org.inspection_templates.create!(name: "T")
    template.inspection_categories.create!(name: "C", weight: 1).inspection_questions.create!(title: "Q", max_score: 5, weight: 1)
    @token = login
    post "/api/v1/inspections", headers: bearer, params: { inspection: { store_id: store.id, inspection_template_id: template.id } }
    inspection = response.parsed_body.fetch("inspection")
    @inspection_id = inspection.fetch("id")
    @response_id = inspection.fetch("responses").first.fetch("id")
  end

  test "real images are accepted" do
    upload(original: fixture_file_upload("sample.jpg", "image/jpeg"))
    assert_response :created

    upload(original: upload_of(PNG_1PX, "shot.png", "image/png"), annotated: upload_of(PNG_1PX, "shot-annotated.png", "image/png"))
    assert_response :created
  end

  test "an image is accepted even when the client sends no content type" do
    upload(original: upload_of(PNG_1PX, "shot.png", "application/octet-stream"))

    assert_response :created
  end

  test "text or markup pretending to be an image is rejected" do
    upload(original: upload_of("just some text, not a picture", "photo.jpg", "image/jpeg"))
    assert_response :unprocessable_content
    assert_match(/image/i, response.parsed_body["error"])

    upload(original: upload_of('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "photo.png", "image/png"))
    assert_response :unprocessable_content

    upload(original: upload_of("<html><script>alert(1)</script></html>", "photo.jpeg", "image/jpeg"))
    assert_response :unprocessable_content
  end

  test "the annotated image is checked too" do
    upload(original: upload_of(PNG_1PX, "shot.png", "image/png"), annotated: upload_of("not an image", "shot-annotated.png", "image/png"))

    assert_response :unprocessable_content
  end

  test "nothing is stored for a rejected upload" do
    assert_no_difference [ "InspectionPhoto.count", "ActiveStorage::Blob.count" ] do
      upload(original: upload_of("not an image", "photo.jpg", "image/jpeg"))
    end
  end

  test "images over the size limit are rejected" do
    with_env("PHOTO_MAX_MB", "0.00001") do
      upload(original: upload_of(PNG_1PX, "shot.png", "image/png"))
    end

    assert_response :unprocessable_content
    assert_match(/too large/, response.parsed_body["error"])
  end

  test "annotation data must be a small JSON object" do
    upload(original: upload_of(PNG_1PX, "a.png", "image/png"), annotation: "not json")
    assert_response :unprocessable_content

    upload(original: upload_of(PNG_1PX, "a.png", "image/png"), annotation: "[1,2,3]")
    assert_response :unprocessable_content

    upload(original: upload_of(PNG_1PX, "a.png", "image/png"), annotation: { marks: [ { note: "x" * 300_000 } ] }.to_json)
    assert_response :unprocessable_content

    upload(original: upload_of(PNG_1PX, "a.png", "image/png"), annotation: { marks: [ { x: 0.1, y: 0.2 } ] }.to_json)
    assert_response :created
  end

  test "image links expire and cannot be forged" do
    upload(original: upload_of(PNG_1PX, "shot.png", "image/png"))
    url = response.parsed_body.dig("photo", "original_image_url")

    get url
    assert_response :redirect
    assert_match(%r{/rails/active_storage/disk/}, response.location)
    get response.location
    assert_response :success
    assert_equal PNG_1PX, response.body.b

    # A fresh payload has a working link again, the old one has stopped.
    travel 2.hours do
      get url
      assert_response :not_found

      get "/api/v1/inspections/#{@inspection_id}", headers: bearer
      fresh = response.parsed_body.dig("inspection", "responses", 0, "photos", 0, "original_image_url")
      assert_not_equal url, fresh
      get fresh
      assert_response :redirect
    end

    forged = url.sub(/redirect\/[^\/]+/, "redirect/forged")
    get forged
    assert_response :not_found
  end

  private

  def upload(original:, annotated: nil, annotation: "{}")
    photo = { comment: "evidence", annotation_data: annotation, original_image: original }
    photo[:annotated_image] = annotated if annotated
    post "/api/v1/inspection_responses/#{@response_id}/photos", headers: bearer, params: { photo: photo }
  end

  def upload_of(content, filename, content_type)
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ], binmode: true)
    file.write(content)
    file.rewind
    (@tempfiles ||= []) << file
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end

  def login
    post "/api/v1/auth/login", params: { auth: { email: @inspector.email, password: "password123" } }
    response.parsed_body.fetch("token")
  end

  def bearer
    { "Authorization" => "Bearer #{@token}" }
  end
end
