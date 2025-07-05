class CalculatorController < ApplicationController
  def index
    if request.post?
      expression = params[:expression]

      if expression.gsub(/[0-9+\/*%().\s^,-]/, '').empty?
        begin
          safe_expr = preprocess_expression(expression)
          @result = eval(safe_expr)

          if @result.is_a?(Numeric)
            if @result.to_s.length > 100
              @result = "undefined (too large)"
            else
              @result = format_number_with_spaces(@result.round(4))
            end
          end
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

 private
  def format_number_with_spaces(number)
    return number unless number.is_a?(Numeric)

    int_part, dec_part = number.to_s.split('.')
    int_part_with_spaces = int_part.reverse.scan(/.{1,3}/).join(',').reverse

    if dec_part
      "#{int_part_with_spaces}.#{dec_part}"
    else
      int_part_with_spaces
    end
  end

    def preprocess_expression(expr)
    expr = expr.gsub('^', '**')

    expr = expr.gsub(/%(\s*\d)/, '% of\1')

    expr = expr.gsub(/(\d+(\.\d+)?)\s*%\s*of\s*(\d+(\.\d+)?)/i) do
      percent = $1
      base = $3
      "(#{percent} / 100.0) * #{base}"
    end

    expr = expr.gsub(/(\d+(\.\d+)?)\s*%/) do
      "(#{$1} / 100.0)"
    end

    expr
  end
end


