require "test_helper"

class CalculatorControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get calculator_index_url
    assert_response :success
  end

  test "should get calculate" do
    get calculator_calculate_url
    assert_response :success
  end
end
