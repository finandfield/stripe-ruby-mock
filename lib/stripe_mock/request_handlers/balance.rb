module StripeMock
  module RequestHandlers
    module Balance

      def Balance.included(klass)
        klass.add_handler 'get /v1/balance', :retrieve_balance
      end

      def retrieve_balance(route, method_url, params, headers)
        account = get_account_by_secret_key
        raise Stripe::InvalidRequestError.new("No account with secret key: #{Stripe.api_key}", 'balance', 400) unless account

        account[:balance]
      end

    end
  end
end