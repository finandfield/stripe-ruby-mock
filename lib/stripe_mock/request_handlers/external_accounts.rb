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

      def update_external_account(route, method_url, params, headers)
        route =~ method_url
        account = assert_existence :account, $1, accounts[$1]

        external_account = get_account_external_account(account, $2)
        assert_existence :external_account, $2, external_account

        if params[:source]
          new_card = get_card_by_token(params.delete(:source))
          add_card_to_object(:account, new_card, account)
          account[:default_source] = new_card[:id]
        end

        # expand the plan for addition to the account object
        plan_name = params[:plan] if params[:plan] && params[:plan] != {}
        plan_name ||= external_account[:plan][:id]
        plan = plans[plan_name]

        if params[:coupon]
          coupon_id = params[:coupon]
          raise Stripe::InvalidRequestError.new("No such coupon: #{coupon_id}", 'coupon', 400) unless coupons[coupon_id]

          # FIXME assert_existence returns 404 error code but Stripe returns 400
          # coupon = assert_existence :coupon, coupon_id, coupons[coupon_id]

          coupon = Data.mock_coupon({ id: coupon_id })
          external_account[:discount] = Stripe::Util.convert_to_stripe_object({ coupon: coupon }, {})
        end

        assert_existence :plan, plan_name, plan
        params[:plan] = plan if params[:plan]
        verify_card_present(account, plan)

        if external_account[:cancel_at_period_end]
          external_account[:cancel_at_period_end] = false
          external_account[:canceled_at] = nil
        end

        external_account.merge!(custom_external_account_params(plan, account, params))

        # delete the old external_account, replace with the new external_account
        account[:external_accounts][:data].reject! { |sub| sub[:id] == external_account[:id] }
        account[:external_accounts][:data] << external_account

        external_account
      end

      def cancel_external_account(route, method_url, params, headers)
        route =~ method_url
        account = assert_existence :account, $1, accounts[$1]

        external_account = get_account_external_account(account, $2)
        assert_existence :external_account, $2, external_account

        cancel_params = { canceled_at: Time.now.utc.to_i }
        cancelled_at_period_end = (params[:at_period_end] == true)
        if cancelled_at_period_end
          cancel_params[:cancel_at_period_end] = true
        else
          cancel_params[:status] = "canceled"
          cancel_params[:cancel_at_period_end] = false
          cancel_params[:ended_at] = Time.now.utc.to_i
        end

        external_account.merge!(cancel_params)

        unless cancelled_at_period_end
          delete_external_account_from_account account, external_account
        end

        external_account
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
