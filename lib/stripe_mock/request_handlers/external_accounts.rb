module StripeMock
  module RequestHandlers
    module ExternalAccounts

      def ExternalAccounts.included(klass)
        klass.add_handler 'get /v1/accounts/(.*)/external_accounts', :retrieve_external_accounts
        klass.add_handler 'post /v1/accounts/(.*)/external_accounts', :create_external_account
        klass.add_handler 'get /v1/accounts/(.*)/external_accounts/(.*)', :retrieve_external_account
        klass.add_handler 'post /v1/accounts/(.*)/external_accounts/(.*)', :update_external_account
        klass.add_handler 'delete /v1/accounts/(.*)/external_accounts/(.*)', :cancel_external_account
      end

      def create_external_account(route, method_url, params, headers)
        route =~ method_url
        external_account = add_external_account_to_account($1, params)

        external_account
      end

      def retrieve_external_account(route, method_url, params, headers)
        route =~ method_url

        account = assert_existence :account, $1, accounts[$1]
        assert_existence :external_account, $2, get_account_external_account(account, $2)
      end

      def retrieve_external_accounts(route, method_url, params, headers)
        route =~ method_url

        account = assert_existence :account, $1, accounts[$1]
        account[:external_accounts]
      end

      # TODO
      def update_external_account(route, method_url, params, headers)

      end

      # TODO
      def delete_external_account(route, method_url, params, headers)

      end

      private

      def verify_card_present(account, plan, params={})
        if account[:default_source].nil? && account[:trial_end].nil? && plan[:trial_period_days].nil? &&
           plan[:amount] != 0 && plan[:trial_end].nil? && params[:trial_end].nil?
          raise Stripe::InvalidRequestError.new('You must supply a valid card xoxo', nil, 400)
        end
      end

    end
  end
end
