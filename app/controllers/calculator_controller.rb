class CalculatorController < ApplicationController
  def index
    if request.post?
      expression = params[:expression]

      if expression.gsub(/[0-9+\/*%().\s^,-]/, '').empty?
        begin
          safe_expr = preprocess_expression(expression)
          @result = eval(safe_expr)

          if @result.is_a?(Numeric)
            @result = @result.to_s.length > 100 ? "undefined (too large)" : format_number_with_spaces(@result.round(4))
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

  def stats
  end

  def calculate_stats
    input = params[:numbers].to_s.strip.gsub(/\s+/, '')
    numbers = input.split(',').map(&:to_f)

    if numbers.empty? || numbers.all?(&:zero?)
      @error = "Invalid input. Please enter a list of numbers."
      return render :stats
    end

    @mean = numbers.sum / numbers.size rescue numbers.inject(0, :+) / numbers.size.to_f

    sorted = numbers.sort
    len = sorted.size
    @median = len.odd? ? sorted[len / 2] : (sorted[len / 2 - 1] + sorted[len / 2]) / 2.0

    freq = numbers.tally
    max_freq = freq.values.max
    @mode = freq.select { |_, v| v == max_freq }.keys
    @mode = nil if @mode.size == numbers.uniq.size

    render :stats
  end

  def polynomial
    expr = params[:expression].to_s.strip

    if expr.empty?
      @message = "Please enter an expression."
      return
    end

    begin
      expr.gsub!(/\)\s*\(/, ')*(')
      if expr.match(/\((\d*)[a-z]\s*[+-]\s*\d+\)\s*\^\d+/i)
        @expression = expand_binomial(expr)
      elsif expr.include?('*')
        left, right = expr.split('*', 2)
        left = left.gsub(/[()]/, '')
        right = right.gsub(/[()]/, '')
        @expression = multiply_polynomials(left, right)
      elsif expr.include?('/')
        left, right = expr.split('/', 2)
        @expression = divide_polynomial_by_monomial(left, right)
      else
        flat_expr = expr.gsub(/[()]/, '')
        @expression = simplify_polynomial(flat_expr)
      end
    rescue => e
      @expression = "Error: #{e.message}"
    end
  end

  private
  # Calculator
  def format_number_with_spaces(number)
    return number unless number.is_a?(Numeric)
    int_part, dec_part = number.to_s.split('.')
    int_part_with_spaces = int_part.reverse.scan(/.{1,3}/).join(',').reverse
    dec_part ? "#{int_part_with_spaces}.#{dec_part}" : int_part_with_spaces
  end

  def preprocess_expression(expr)
    expr = expr.gsub('^', '**')
    expr = expr.gsub(/%(\s*\d)/, '% of\1')
    expr = expr.gsub(/(\d+(\.\d+)?)\s*%\s*of\s*(\d+(\.\d+)?)/i) { "(#{$1} / 100.0) * #{$3}" }
    expr = expr.gsub(/(\d+(\.\d+)?)\s*%/) { "(#{$1} / 100.0)" }
    expr
  end

  # Polynomials
  def factorial(n)
    (1..n).inject(1, :*)
  end

  def combination(n, k)
    factorial(n) / (factorial(k) * factorial(n - k))
  end

  def expand_binomial(expr)
    match = expr.match(/\(\s*(\d*)([a-z])(?:\^(\d+))?\s*([+-])\s*(\d+)\s*\)\s*\^(\d+)/i)
    raise "Invalid binomial format" unless match

    a_str, var, power_str, op, b_str, n_str = match.captures
    a = a_str.empty? ? 1 : a_str.to_i
    power = power_str ? power_str.to_i : 1
    b = b_str.to_i
    b = -b if op == '-'
    n = n_str.to_i

    terms = []

    (0..n).each do |k|
      coeff = combination(n, k) * (a ** (n - k)) * (b ** k)
      total_power = power * (n - k)

      term = if total_power == 0
              "#{coeff}"
            elsif total_power == 1
              "#{coeff == 1 ? '' : coeff}#{var}"
            else
              "#{coeff == 1 ? '' : coeff}#{var}^#{total_power}"
            end

      terms << term
    end

    terms.join(' + ').gsub(/\+\s+-/, '- ')
  end

  def simplify_polynomial(expr)
    expr = expr.gsub(' ', '').gsub(/[()]/, '')
    terms = expr.scan(/[+-]?\d*[a-z](?:\^\d+)?(?:[a-z](?:\^\d+)?)*|[+-]?\d+/i)
    hash = Hash.new(0)

    terms.each do |term|
      if term.match(/[a-z]/i)
        coeff = term[/^[+-]?\d*/]
        coeff = '+1' if coeff == '+' || coeff.empty?
        coeff = '-1' if coeff == '-'
        coeff = coeff.to_i
        vars = term.sub(/^[+-]?\d*/, '')
        sorted_vars = vars.scan(/[a-z](?:\^\d+)?/i).sort
        var_key = sorted_vars.join
        hash[var_key] += coeff
      else
        hash[""] += term.to_i
      end
    end

    result = hash.sort_by do |key, _|
      degrees = key.scan(/[a-z](?:\^(\d+))?/i).map { |e| e[0] ? e[0].to_i : 1 }
      total_degree = degrees.sum
      [-total_degree, key]
    end.map do |vars, coeff|
      next if coeff == 0
      display = vars.empty? ? '' : vars
      coeff == 1 && !display.empty? ? display :
      coeff == -1 && !display.empty? ? "-#{display}" :
      "#{coeff}#{display}"
    end.compact.join(' + ').gsub(/\+\s+-/, '- ')
  end

  def parse_polynomial(expr)
    expr = expr.gsub(' ', '')
    terms = expr.scan(/[+-]?\d*[a-z](?:\^\d+)?(?:[a-z](?:\^\d+)?)*|[+-]?\d+/i)

    hash = Hash.new(0)

    terms.each do |term|
      next if term.strip.empty?

      if term.match(/[a-z]/)
        coeff_str = term[/^[+-]?\d*/]
        coeff =
          if coeff_str.nil? || coeff_str.empty?
            1
          elsif coeff_str == '+' then 1
          elsif coeff_str == '-' then -1
          else coeff_str.to_i
        end


        var_part = term.gsub(/^[+-]?\d*/, '')
        var_map = Hash.new(0)

        var_part.scan(/[a-z](?:\^\d+)?/i).each do |v|
          name = v[0]
          exp = v[/\^\d+/] ? v[/\^\d+/][1..].to_i : 1
          var_map[name] += exp
        end

        key = var_map.sort.to_h
        hash[key] += coeff
      else
        hash[{}] += term.to_i
      end
    end

    hash
  end

  def format_polynomial(hash)
    return "0" if hash.empty?

    sorted = hash.sort_by do |vars, _|
      [
        -vars.values.sum,                      
        vars.keys.join,                        
        vars.map { |_, exp| -exp }             
      ]
    end

    sorted.map do |vars, coeff|
      next if coeff == 0

      var_str = vars.map { |v, e| e == 1 ? v : "#{v}^#{e}" }.join

      if coeff == 1 && !var_str.empty?
        var_str
      elsif coeff == -1 && !var_str.empty?
        "-#{var_str}"
      else
        "#{coeff}#{var_str}"
      end
    end.compact.join(' + ').gsub(/\+\s+-/, '- ')
  end

  def multiply_polynomials(p1, p2)
    terms1 = parse_polynomial(p1)
    terms2 = parse_polynomial(p2)
    result = Hash.new(0)

    terms1.each do |k1, c1|
      terms2.each do |k2, c2|
        new_vars = merge_variable_keys(k1, k2)
        result[new_vars] += c1 * c2
      end
    end

    format_polynomial(result)
  end

  def divide_polynomial_by_monomial(poly, mono)
    terms = parse_polynomial(poly)
    divisor = parse_polynomial(mono)
    raise "Division only supports monomials" unless divisor.size == 1

    d_vars, d_coeff = divisor.first
    raise "Cannot divide by zero" if d_coeff == 0

    result = {}

    terms.each do |vars, coeff|
      new_coeff = coeff / d_coeff
      new_vars = subtract_variable_keys(vars, d_vars)
      result[new_vars] = new_coeff
    end

    format_polynomial(result)
  end

  def merge_variable_keys(k1, k2)
    new_vars = k1.dup
    k2.each do |v, e|
      new_vars[v] ||= 0
      new_vars[v] += e
    end
    new_vars
  end

  def subtract_variable_keys(k1, k2)
    new_vars = k1.dup
    k2.each { |v, e| new_vars[v] -= e }
    raise "Negative exponents not supported" if new_vars.values.any? { |x| x < 0 }
    new_vars.delete_if { |_, v| v == 0 }
    new_vars
  end


end
