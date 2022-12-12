#Back to School 10% Off Sitewide No Coupons
class Campaign
    def initialize(condition, *qualifiers)
      @condition = (condition.to_s + '?').to_sym
      @qualifiers = PostCartAmountQualifier ? [] : [] rescue qualifiers.compact
      @line_item_selector = qualifiers.last unless @line_item_selector
      qualifiers.compact.each do |qualifier|
        is_multi_select = qualifier.instance_variable_get(:@conditions).is_a?(Array)
        if is_multi_select
          qualifier.instance_variable_get(:@conditions).each do |nested_q|
            @post_amount_qualifier = nested_q if nested_q.is_a?(PostCartAmountQualifier)
            @qualifiers << qualifier
          end
        else
          @post_amount_qualifier = qualifier if qualifier.is_a?(PostCartAmountQualifier)
          @qualifiers << qualifier
        end
      end if @qualifiers.empty?
    end
  
    def qualifies?(cart)
      return true if @qualifiers.empty?
      @unmodified_line_items = cart.line_items.map do |item|
        new_item = item.dup
        new_item.instance_variables.each do |var|
          val = item.instance_variable_get(var)
          new_item.instance_variable_set(var, val.dup) if val.respond_to?(:dup)
        end
        new_item
      end if @post_amount_qualifier
      @qualifiers.send(@condition) do |qualifier|
        is_selector = false
        if qualifier.is_a?(Selector) || qualifier.instance_variable_get(:@conditions).any? { |q| q.is_a?(Selector) }
          is_selector = true
        end rescue nil
        if is_selector
          raise "Missing line item match type" if @li_match_type.nil?
          cart.line_items.send(@li_match_type) { |item| qualifier.match?(item) }
        else
          qualifier.match?(cart, @line_item_selector)
        end
      end
    end
  
    def run_with_hooks(cart)
      before_run(cart) if respond_to?(:before_run)
      run(cart)
      after_run(cart)
    end
  
    def after_run(cart)
      @discount.apply_final_discount if @discount && @discount.respond_to?(:apply_final_discount)
      revert_changes(cart) unless @post_amount_qualifier.nil? || @post_amount_qualifier.match?(cart)
    end
  
    def revert_changes(cart)
      cart.instance_variable_set(:@line_items, @unmodified_line_items)
    end
  end
  
  class ConditionalDiscount < Campaign
    def initialize(condition, customer_qualifier, cart_qualifier, line_item_selector, discount, max_discounts)
      super(condition, customer_qualifier, cart_qualifier)
      @line_item_selector = line_item_selector
      @discount = discount
      @items_to_discount = max_discounts == 0 ? nil : max_discounts
    end
  
    def run(cart)
      raise "Campaign requires a discount" unless @discount
      return unless qualifies?(cart)
      applicable_items = cart.line_items.select { |item| @line_item_selector.nil? || @line_item_selector.match?(item) }
      applicable_items = applicable_items.sort_by { |item| item.variant.price }
      applicable_items.each do |item|
        break if @items_to_discount == 0
        if (!@items_to_discount.nil? && item.quantity > @items_to_discount)
          discounted_items = item.split(take: @items_to_discount)
          @discount.apply(discounted_items)
          cart.line_items << discounted_items
          @items_to_discount = 0
        else
          @discount.apply(item)
          @items_to_discount -= item.quantity if !@items_to_discount.nil?
        end
      end
    end
  end
  
  class Qualifier
    def partial_match(match_type, item_info, possible_matches)
      match_type = (match_type.to_s + '?').to_sym
      if item_info.kind_of?(Array)
        possible_matches.any? do |possibility|
          item_info.any? do |search|
            search.send(match_type, possibility)
          end
        end
      else
        possible_matches.any? do |possibility|
          item_info.send(match_type, possibility)
        end
      end
    end
  
    def compare_amounts(compare, comparison_type, compare_to)
      case comparison_type
        when :greater_than
          return compare > compare_to
        when :greater_than_or_equal
          return compare >= compare_to
        when :less_than
          return compare < compare_to
        when :less_than_or_equal
          return compare <= compare_to
        when :equal_to
          return compare == compare_to
        else
          raise "Invalid comparison type"
      end
    end
  end
  
  class NoCodeQualifier < Qualifier
    def match?(cart, selector = nil)
      return true if cart.discount_code.nil?
      false
    end
  end
  
  class Selector
    def partial_match(match_type, item_info, possible_matches)
      match_type = (match_type.to_s + '?').to_sym
      if item_info.kind_of?(Array)
        possible_matches.any? do |possibility|
          item_info.any? do |search|
            search.send(match_type, possibility)
          end
        end
      else
        possible_matches.any? do |possibility|
          item_info.send(match_type, possibility)
        end
      end
    end
  end
  
  class ProductTagSelector < Selector
    def initialize(match_type, match_condition, tags)
      @match_condition = match_condition
      @invert = match_type == :does_not
      @tags = tags.map(&:downcase)
    end
  
    def match?(line_item)
      product_tags = line_item.variant.product.tags.to_a.map(&:downcase)
      case @match_condition
        when :match
          return @invert ^ ((@tags & product_tags).length > 0)
        else
          return @invert ^ partial_match(@match_condition, product_tags, @tags)
      end
    end
  end
  
  class PercentageDiscount
    def initialize(percent, message)
      @discount = (100 - percent) / 100.0
      @message = message
    end
  
    def apply(line_item)
      line_item.change_line_price(line_item.line_price * @discount, message: @message)
    end
  end
  
  CAMPAIGNS = [
    ConditionalDiscount.new(
      :all,
      nil,
      NoCodeQualifier.new(),
      ProductTagSelector.new(
        :does_not,
        :match,
        ["NOPROMO"]
      ),
      PercentageDiscount.new(
        10,
        "Back to School 10% Off"
      ),
      0
    )
  ].freeze
  
  CAMPAIGNS.each do |campaign|
    campaign.run_with_hooks(Input.cart)
  end
  
  Output.cart = Input.cart
