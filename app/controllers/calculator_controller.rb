class CalculatorController < ApplicationController
  def index
    if request.post?
      num1 = params[:num1].to_f
      num2 = params[:num2].to_f
      operation = params[:operation]

      @result = case operation
                when '+'
                  num1 + num2
                when '-'
                  num1 - num2
                when '*'
                  num1 * num2
                when '/'
                  num2 != 0 ? num1 / num2 : 'Error: Division by zero'
                else
                  'Invalid operation'
                end
      Rails.logger.debug "Params received: #{params.inspect}"
      Rails.logger.debug "Calculated result: #{@result.inspect}"
    end
  end
end
