module StripeMock
  module RequestHandlers
    module Balance

      def Balance.included(klass)
        klass.add_handler 'get /v1/balance', :retrieve_balance
        # klass.add_handler 'get /v1/balance/(.*)', :retrieve_balance
        # klass.add_handler 'post /v1/accounts/(.*)/external_accounts', :create_external_account
        # klass.add_handler 'get /v1/accounts/(.*)/external_accounts/(.*)', :retrieve_external_account
        # klass.add_handler 'post /v1/accounts/(.*)/external_accounts/(.*)', :update_external_account
        # klass.add_handler 'delete /v1/accounts/(.*)/external_accounts/(.*)', :cancel_external_account
      end

      def retrieve_balance(route, method_url, params, headers)
        account = get_account_by_secret_key
        raise Stripe::InvalidRequestError.new("No account with secret key: #{Stripe.api_key}", 'balance', 400) unless account
        # binding.pry

        account[:balance]
      end

    end
  end
end