require "test_helper"

class BaseWeekdayRequirementsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get base_weekday_requirements_show_url
    assert_response :success
  end

  test "should get edit" do
    get base_weekday_requirements_edit_url
    assert_response :success
  end
end
