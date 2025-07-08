require 'bigdecimal'
require 'bigdecimal/util'
require 'matrix'
require 'rational'

class CalculatorController < ApplicationController

  def index
    if request.post?
      expression = params[:expression].to_s.strip

      if expression.empty?
        @result = "Please input a number"
        return
      end

      if expression.gsub(/[0-9+\/*%().\s^,\-a-zA-Z√]/, '').empty?
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
    numbers = params[:numbers].to_s.strip.gsub(/[\s\r\n]+/, '').split(',').map(&:strip).map(&:to_d)
    weights = params[:weights].to_s.strip.gsub(/[\s\r\n]+/, '').split(',').map(&:strip).map(&:to_d)
    use_weighted = params[:use_weighted_mean].present?

    if numbers.empty? || numbers.size < 2
      @error = "Please enter at least two numbers."
      return render :stats
    end

    if use_weighted
      if weights.size != numbers.size
        @error = "Weights count must match numbers count."
        return render :stats
      end

      @weighted_components = numbers.each_with_index.map do |n, i|
        {
          index: i,
          number: n,
          weight: weights[i],
          product: n * weights[i]  # both are BigDecimal
        }
      end

      @weighted_sum = @weighted_components.sum { |h| h[:product] }
      @weight_total = weights.sum
      @weighted_mean = @weighted_sum / @weight_total unless @weight_total.zero?

    end

    # Unweighted Mean (always calculate this for basic stats)
    @mean = numbers.sum.to_f / numbers.size

    # Step 3: Basic stats
    sorted = numbers.sort
    len = numbers.size

    # Median
    @median = len.odd? ? sorted[len / 2] : (sorted[len / 2 - 1] + sorted[len / 2]) / 2.0

    # Mode
    freq = numbers.tally
    max_freq = freq.values.max
    @mode = freq.select { |_, v| v == max_freq }.keys
    @mode = nil if @mode.size == numbers.uniq.size

    # Min & Max
    @min = numbers.min
    @max = numbers.max

    # Variance and Std Dev (unweighted)
    squared_diffs = numbers.map { |n| (n - @mean)**2 }
    @pop_variance = squared_diffs.sum / numbers.size
    @pop_std_dev = Math.sqrt(@pop_variance)

    @sample_variance = squared_diffs.sum / (numbers.size - 1)
    @sample_std_dev = Math.sqrt(@sample_variance)

    # MAD
    absolute_diffs = numbers.map { |n| (n - @mean).abs }
    @mad = absolute_diffs.sum / numbers.size

    # RMS
    squared = numbers.map { |n| n**2 }
    @rms = Math.sqrt(squared.sum / numbers.size)

    # IQR
    q1_index = (len * 0.25).floor
    q3_index = (len * 0.75).floor
    q1 = sorted[q1_index]
    q3 = sorted[q3_index]
    @iqr = q3 - q1

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

  def linear
  end

  def calculate_linear
    if params[:equation].present?
      equations = params[:equation]
      solve_single_variable(equations)
    else
      solve_2x2()
    end

    render :linear
  end

  def quadratic
  end

  def calculate_quadratic
    values
    render :quadratic
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

    expr = expr.gsub('√', 'sqrt')

    # Implicit multiplication handling
    # number followed by parenthesis → 8(3) → 8*(3)
    expr = expr.gsub(/(\d)\s*\(/, '\1*(')

    # closing parenthesis followed by number → (3)8 → (3)*8
    expr = expr.gsub(/\)\s*(\d)/, ')*\1')

    # parenthesis followed by parenthesis → (2)(3) → (2)*(3)
    expr = expr.gsub(/\)\s*\(/, ')*(')

    # variable or function followed by parenthesis (e.g., 2sin(30) → 2*sin(30))
    expr = expr.gsub(/(\d)(Math\.[a-z]+)/, '\1*\2')

    # Percentage handling
    expr = expr.gsub(/%(\s*\d)/, '% of\1')
    expr = expr.gsub(/(\d+(\.\d+)?)\s*%\s*of\s*(\d+(\.\d+)?)/i) { "(#{$1} / 100.0) * #{$3}" }
    expr = expr.gsub(/(\d+(\.\d+)?)\s*%/) { "(#{$1} / 100.0)" }

    # Superscript numbers like ² to normal powers
    expr = expr.gsub(/([\d\)])([⁰¹²³⁴⁵⁶⁷⁸⁹]+)/) do
      base = $1
      power = $2.chars.map { |c| "⁰¹²³⁴⁵⁶⁷⁸⁹".index(c) }.join
      "#{base}**#{power}"
    end

    # Math function mapping
    expr = expr.gsub(/\b(sin|cos|tan|asin|acos|atan|sqrt|log|ln)\b/i) do |fn|
      case fn.downcase
      when 'ln' then 'Math.log'
      when 'log' then 'Math.log10'
      when 'sqrt' then 'Math.sqrt'
      else "Math.#{fn.downcase}"
      end
    end

    # Convert sin(x) → sin(x * Math::PI / 180) for degree support
    expr = expr.gsub(/Math\.(sin|cos|tan)\(([^()]+)\)/i) do
      "Math.#{$1}(#{$2} * Math::PI / 180)"
    end

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
    terms = expr.scan(/[+-]?[\d\.\/]*[a-z](?:\^\d+)?(?:[a-z](?:\^\d+)?)*|[+-]?[\d\.\/]+/i)
    hash = Hash.new(0)

    terms.each do |term|
      if term.match(/[a-z]/i)
        coeff = term[/^[+-]?[\d\.\/]+/] || term[/^[+-]/] || '1'
        coeff = '+1' if coeff == '+'
        coeff = '-1' if coeff == '-'
        coeff = parse_number(coeff)

        vars = term.sub(/^[+-]?[\d\.\/]+/, '')
        sorted_vars = vars.scan(/[a-z](?:\^\d+)?/i).sort
        var_key = sorted_vars.join
        hash[var_key] += coeff
      else
        hash[""] += parse_number(term)
      end
    end

    result = hash.sort_by do |key, _|
      degrees = key.scan(/[a-z](?:\^(\d+))?/i).map { |e| e[0] ? e[0].to_i : 1 }
      total_degree = degrees.sum
      [-total_degree, key]
    end.map do |vars, coeff|
      next if coeff == 0
      display = vars.empty? ? '' : vars

      formatted_coeff =
        if coeff.is_a?(Rational) && coeff.denominator != 1
          "(#{coeff})"
        elsif coeff == 1 && !display.empty?
          ''
        elsif coeff == -1 && !display.empty?
          "-"
        else
          coeff.to_s
        end

      "#{formatted_coeff}#{display}"
    end.compact.join(' + ').gsub(/\+\s+-/, '- ')
  end

  def parse_polynomial(expr)
    expr = expr.gsub(' ', '')
    terms = expr.scan(/[+-]?[\d\.\/]*[a-z](?:\^\d+)?(?:[a-z](?:\^\d+)?)*|[+-]?[\d\.\/]+/i)

    hash = Hash.new(0)

    terms.each do |term|
      next if term.strip.empty?

      if term.match(/[a-z]/)
        coeff_str = term[/^[+-]?[\d\.\/]+/] || term[/^[+-]/] || '1'
        coeff = parse_number(coeff_str)

        var_part = term.gsub(/^[+-]?[\d\.\/]+/, '')
        var_map = Hash.new(0)

        var_part.scan(/[a-z](?:\^\d+)?/i).each do |v|
          name = v[0]
          exp = v[/\^\d+/] ? v[/\^\d+/][1..].to_i : 1
          var_map[name] += exp
        end

        key = var_map.sort.to_h
        hash[key] += coeff
      else
        hash[{}] += parse_number(term)
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

      formatted_coeff =
        if coeff.is_a?(Rational) && coeff.denominator != 1
          "(#{coeff})"
        elsif coeff == 1 && !var_str.empty?
          ""
        elsif coeff == -1 && !var_str.empty?
          "-"
        else
          coeff.to_s
        end

      "#{formatted_coeff}#{var_str}"
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

  # Linear Equations
  def solve_2x2
    begin
      required = [:a1, :b1, :c1, :a2, :b2, :c2]
        if required.any? { |key| params[key].to_s.strip.empty? }
          @error = "Please input all coefficients for both equations."
          return
        end

      a1 = parse_number(params[:a1])
      b1 = parse_number(params[:b1])
      c1 = parse_number(params[:c1])
      a2 = parse_number(params[:a2])
      b2 = parse_number(params[:b2])
      c2 = parse_number(params[:c2])

      a = Matrix[[a1, b1], [a2, b2]]
      b = Matrix[[c1], [c2]]

      result = a.inverse * b
      @x = result[0, 0].to_f.round(4)
      @y = result[1, 0].to_f.round(4)
    rescue => e
      @error = "2x2 Solver Error: #{e.message}"
    end
  end

  def solve_single_variable(equation)
    begin
      if equation.to_s.strip.empty?
        @error = "Please input an equation."
        return
      end
      # Normalize unicode dashes to ASCII minus
      equation = equation.gsub(/[–—−]/, '-')

      # Replace 'y' with 'x'
      expr = equation.gsub('y', 'x')

      # Insert * between digits and variables (e.g., 2x → 2*x)
      expr = expr.gsub(/(\d)([a-zA-Z])/, '\1*\2')

      # Insert * between variable and variable (e.g., xy → x*y)
      expr = expr.gsub(/([a-zA-Z])([a-zA-Z])/, '\1*\2')

      # Insert * between number/variable and open parenthesis
      expr = expr.gsub(/(\d|\w)\(/, '\1*(')

      # Insert * between closing parenthesis and variable/number
      expr = expr.gsub(/\)(\d|\w)/, ')*\1')

      # Convert fractions like 1/2 to (1.0/2) to allow float division
      expr = expr.gsub(/(?<!\()(\b\d+)\s*\/\s*(\d+\b)(?![\d\/]*\))/, '(\1.0/\2)')

      # Split and validate
      left, right = expr.split('=')
      raise 'Invalid equation format' unless left && right

      solution = nil
      (-1000..1000).step(0.01).each do |x|
        x = x.to_r
        lhs = eval(left)
        rhs = eval(right)
        if (lhs - rhs).abs < 0.0001
          solution = x.to_f.round(4)
          break
        end
      end

      raise "No solution found (or too complex)" unless solution

      @single_solution = "y = #{solution}"
    rescue => e
      @error = "Single Variable Error: #{e.message}"
    end
  end

  #Quadratic Equations
  def values
    a_str = params[:a].to_s.strip
    b_str = params[:b].to_s.strip
    c_str = params[:c].to_s.strip

    if a_str.empty? || b_str.empty? || c_str.empty?
      @solution = "Please input a number for all fields (a, b, and c)."
      return
    end
    
    a = parse_number(params[:a])
    b = parse_number(params[:b])
    c = parse_number(params[:c])

    if a == 0
      @solution = "a = 0 is invalid"
      return
    end

    discriminant = b**2 - 4 * a * c

    if discriminant > 0
      root1 = (-b + Math.sqrt(discriminant.to_f)) / (2 * a)
      root2 = (-b - Math.sqrt(discriminant.to_f)) / (2 * a)
      @solution = "x₁ = #{format_number(root1)}, x₂ = #{format_number(root2)}"
    elsif discriminant == 0
      root = -b / (2 * a)
      @solution = "x = #{format_number(root)} (double root)"
    else
      real = -b / (2 * a)
      imag = Math.sqrt(-discriminant.to_f) / (2 * a)
      @solution = "x₁ = #{format_number(real)} + #{format_number(imag)}i, x₂ = #{format_number(real)} - #{format_number(imag)}i"
    end
  end

  #Determines if the input is float/fractional or a integer
  def parse_number(str)
    str = str.to_s.strip

    # Remove wrapping parentheses like (1/2) or (3.5)
    str = str[1..-2].strip if str.start_with?('(') && str.end_with?(')')

    if str.include?('/')
      Rational(str)
    else
      BigDecimal(str)
    end
    rescue
      raise "Invalid number format: #{str}"
  end
  
  def format_number(num)
    num = num.to_f
    num.abs > 1_000_000 ? "∞" : num.round(4)
  end

end
