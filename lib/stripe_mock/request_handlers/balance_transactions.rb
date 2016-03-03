module StripeMock
  module RequestHandlers
    module BalanceTransactions

      def BalanceTransactions.included(klass)
        klass.add_handler 'get /v1/balance/history/(.*)', :retrieve_balance_transaction
        # klass.add_handler 'get /v1/balance/(.*)', :retrieve_balance
        # klass.add_handler 'post /v1/accounts/(.*)/external_accounts', :create_external_account
        # klass.add_handler 'get /v1/accounts/(.*)/external_accounts/(.*)', :retrieve_external_account
        # klass.add_handler 'post /v1/accounts/(.*)/external_accounts/(.*)', :update_external_account
        # klass.add_handler 'delete /v1/accounts/(.*)/external_accounts/(.*)', :cancel_external_account
      end

      def retrieve_balance_transaction(route, method_url, params, headers)
        route =~ method_url

        balance_transactions[$1]
      end

    end
  end
end