class CalculatorController < ApplicationController
  def index
    if request.post?
      expression = params[:expression]

      if expression.gsub(/[0-9+\/*%().\s^,-]/, '').empty?
        begin
          safe_expr = expression.gsub('^', '**')
          @result = eval(safe_expr)
          @result = @result.round(4) if @result.is_a?(Float)
        rescue ZeroDivisionError
          @result = "Error: Division by zero"
        rescue => e
          @result = "Error: #{e.message}"
        end
      else
        @result = "Invalid characters in input."
      end
    end
  end
end


