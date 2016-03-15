module StripeMock
  module RequestHandlers
    module Charges

      def Charges.included(klass)
        klass.add_handler 'get /v1/charges/(.*)/refunds/(.*)',          :get_refund
        klass.add_handler 'post /v1/charges',               :new_charge
        klass.add_handler 'get /v1/charges',                :get_charges
        klass.add_handler 'get /v1/charges/(.*)',           :get_charge
        klass.add_handler 'post /v1/charges/(.*)/capture',  :capture_charge
        klass.add_handler 'post /v1/charges/(.*)/refund',   :refund_charge
        klass.add_handler 'post /v1/refunds',               :create_refund
        klass.add_handler 'post /v1/charges/(.*)',          :update_charge
      end

      def new_charge(route, method_url, params, headers)
        id = new_id('ch')
        if params[:source] && params[:source].is_a?(String)
          # if a customer is provided, the card parameter is assumed to be the actual
          # card id, not a token. in this case we'll find the card in the customer
          # object and return that.
          if params[:customer]
            params[:source] = get_card(customers[params[:customer]], params[:source])
          else
            params[:source] = get_card_by_token(params[:source])
          end
        elsif params[:source] && params[:source][:id]
          raise Stripe::InvalidRequestError.new("Invalid token id: #{params[:card]}", 'card', 400)
        end


        customer = customers[params[:customer]]

        unless customer.present?
          raise Stripe::InvalidRequestError.new("Could not find customer with id: #{params[:customer].inspect}", 'customer', 400)
        end

        # Find the customers card
        if params[:source].nil? && customer && params[:destination] && params[:destination].include?('acct') && customer[:default_source]
          # This is most often called when we do an "instant charge"
          card = customer[:sources][:data].find{|card| card[:id] == customer[:default_source]}
        elsif customer[:sources] && customer[:sources][:data].any?
          card = customer[:sources][:data].find{|card| card[:id] == params[:card]}
        end

        # Raise an exception if the card doesn't belong to the customer
        unless card
          raise Stripe::InvalidRequestError.new("#{params[:card]} does not belong to #{params[:customer]}", 'amount', 400)
        end

        ensure_required_params(params)
        charge = Data.mock_charge(params.merge :id => id, :balance_transaction => new_balance_transaction('txn'))

        if customer && card && params[:destination] && params[:destination].include?('acct')
          # In these cases, we are accounting for cards with the number `4000 0000 0000 0077`. When this card is used, funds are
          #   deposited directly into the destination account
          #TODO handle failure cards
          if card[:last4] == CARDS.instant_charge.last(4)
            # These charges go straight to the account's available balance
            balance_type = :available
          else
            # These charges are stored in the pending balance
            balance_type = :pending
          end
          account = accounts[params[:destination]]
          account[:balance][balance_type].first[:amount] += charge[:amount]
          account[:balance][balance_type].first[:source_types][:card] += charge[:amount]
        else
          # This deals with a normal charge, where it is placed in the "master" account(the account all Connected Accounts report to)

          #TODO handle failure cards
          if card && card[:last4] == CARDS.instant_charge.last(4)
            # Instant charge goes straight to available balance
            balance_type = :available
          else
            # Other charges go to pending
            balance_type = :pending
          end
          $master_account[:balance][balance_type].first[:amount] += charge[:amount]
          $master_account[:balance][balance_type].first[:source_types][:card] += charge[:amount]
        end

        if card
          charge[:source] = card
        end

        balance_transaction = Data.mock_balance_transaction_from_charge(charge)
        balance_transactions[balance_transaction[:id]] = balance_transaction

        charges[id] = charge
      end

      def update_charge(route, method_url, params, headers)
        route =~ method_url
        id = $1

        charge = assert_existence :charge, id, charges[id]
        allowed = allowed_params(params)
        disallowed = params.keys - allowed
        if disallowed.count > 0
          raise Stripe::InvalidRequestError.new("Received unknown parameters: #{disallowed.join(', ')}" , '', 400)
        end

        charges[id] = Util.rmerge(charge, params)
      end

      def get_charges(route, method_url, params, headers)
        params[:offset] ||= 0
        params[:limit] ||= 10

        clone = charges.clone

        if params[:customer]
          clone.delete_if { |k,v| v[:customer] != params[:customer] }
        end

        Data.mock_list_object(clone.values, params)
      end

      def get_charge(route, method_url, params, headers)
        route =~ method_url

        if $1
          assert_existence :charge, $1, charges[$1]
        elsif params[:charge]
          assert_existence :charge, params[:charge], charges[params[:charge]]
        end
      end

      def get_refund(route, method_url, params, headers)
        route =~ method_url
        charge = charges[$1]
        refund = charge[:refunds][:data].find{|r| r[:id] == $2}
        refund
      end

      def capture_charge(route, method_url, params, headers)
        route =~ method_url
        charge = assert_existence :charge, $1, charges[$1]

        if params[:amount]
          refund = Data.mock_refund(
            :balance_transaction => new_balance_transaction('txn'),
            :id => new_id('re'),
            :amount => charge[:amount] - params[:amount]
          )
          add_refund_to_charge(refund, charge)
        end

        charge[:captured] = true
        charge
      end

      def refund_charge(route, method_url, params, headers)
        charge = get_charge(route, method_url, params, headers)

        refund = Data.mock_refund params.merge(
          :balance_transaction => new_balance_transaction('txn'),
          :id => new_id('re')
        )
        add_refund_to_charge(refund, charge)
        charge
      end

      def create_refund(route, method_url, params, headers)
        charge = get_charge(route, method_url, params, headers)

        refund = Data.mock_refund params.merge(
          :balance_transaction => new_balance_transaction('txn'),
          :id => new_id('re'),
          :charge => charge[:id],
          :card => charge[:source],
          :amount => charge[:amount]
        )

        add_refund_to_charge(refund, charge)

        transaction_params = refund.clone
        transaction_params[:amount] = -transaction_params[:amount]
        balance_transaction = Data.mock_balance_transaction_from_charge(transaction_params)
        balance_transactions[balance_transaction[:id]] = balance_transaction

        refund
      end

      private

      def ensure_required_params(params)
        if params[:amount].nil?
          require_param(:amount)
        elsif params[:currency].nil?
          require_param(:currency)
        elsif non_integer_charge_amount?(params)
          raise Stripe::InvalidRequestError.new("Invalid integer: #{params[:amount]}", 'amount', 400)
        elsif non_positive_charge_amount?(params)
          raise Stripe::InvalidRequestError.new('Invalid positive integer', 'amount', 400)
        end
      end

      def non_integer_charge_amount?(params)
        params[:amount] && !params[:amount].is_a?(Integer)
      end

      def non_positive_charge_amount?(params)
        params[:amount] && params[:amount] < 1
      end

      def require_param(param)
        raise Stripe::InvalidRequestError.new("Missing required param: #{param}", param.to_s, 400)
      end

      def allowed_params(params)
        allowed = [:description, :metadata, :receipt_email, :fraud_details, :shipping]

        # This is a workaround for the way the Stripe API sends params even when they aren't modified.
        # Stipe will include those params even when they aren't modified.
        allowed << :fee_details if params.has_key?(:fee_details) && params[:fee_details].nil?
        allowed << :source if params.has_key?(:source) && params[:source].empty?
        if params.has_key?(:refunds) && (params[:refunds].empty? ||
           params[:refunds].has_key?(:data) && params[:refunds][:data].nil?)
          allowed << :refunds
        end
      end
    end
  end
end
