module StripeMock
  module RequestHandlers
    module Subscriptions

      def Subscriptions.included(klass)
        klass.add_handler 'get /v1/customers/(.*)/subscriptions', :retrieve_subscriptions
        klass.add_handler 'post /v1/customers/(.*)/subscriptions', :create_subscription
        klass.add_handler 'get /v1/customers/(.*)/subscriptions/(.*)', :retrieve_subscription
        klass.add_handler 'post /v1/customers/(.*)/subscriptions/(.*)', :update_subscription
        klass.add_handler 'delete /v1/customers/(.*)/subscriptions/(.*)', :cancel_subscription
      end

      def create_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existence :customer, $1, customers[$1]

        plan_id = params[:plan]
        plan = assert_existence :plan, plan_id, plans[plan_id]

        if params[:source]
          new_card = get_card_by_token(params.delete(:source))
          add_card_to_object(:customer, new_card, customer)
          customer[:default_source] = new_card[:id]
        end

        # Ensure customer has card to charge if plan has no trial and is not free
        verify_card_present(customer, plan, params)

        subscription = Data.mock_subscription({ id: (params[:id] || new_id('su')) })
        subscription.merge!(custom_subscription_params(plan, customer, params))

        if params[:coupon]
          coupon_id = params[:coupon]

          raise Stripe::InvalidRequestError.new("No such coupon: #{coupon_id}", 'coupon', 400) unless coupons[coupon_id]

          # FIXME assert_existence returns 404 error code but Stripe returns 400
          # coupon = assert_existence :coupon, coupon_id, coupons[coupon_id]

          coupon = Data.mock_coupon({ id: coupon_id })

          subscription[:discount] = Stripe::Util.convert_to_stripe_object({ coupon: coupon }, {})
        end



        add_subscription_to_customer(customer, subscription)

        line = Data.mock_subscription_line_item_from_plan(plan)
        line[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}
        customer[:upcoming] << line
        subscription
      end

      def retrieve_subscription(route, method_url, params, headers)
        route =~ method_url

        customer = assert_existence :customer, $1, customers[$1]
        assert_existence :subscription, $2, get_customer_subscription(customer, $2)
      end

      def retrieve_subscriptions(route, method_url, params, headers)
        route =~ method_url

        customer = assert_existence :customer, $1, customers[$1]
        customer[:subscriptions]
      end

      def update_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existence :customer, $1, customers[$1]

        subscription = get_customer_subscription(customer, $2)
        assert_existence :subscription, $2, subscription

        if params[:source]
          new_card = get_card_by_token(params.delete(:source))
          add_card_to_object(:customer, new_card, customer)
          customer[:default_source] = new_card[:id]
        end

        # expand the plan for addition to the customer object
        plan_name = params[:plan] if params[:plan] && params[:plan] != {}
        plan_name ||= subscription[:plan][:id]
        plan = plans[plan_name]

        new_plan = plan.clone
        old_plan = subscription[:plan].clone

        if params[:coupon]
          coupon_id = params[:coupon]
          raise Stripe::InvalidRequestError.new("No such coupon: #{coupon_id}", 'coupon', 400) unless coupons[coupon_id]

          # FIXME assert_existence returns 404 error code but Stripe returns 400
          # coupon = assert_existence :coupon, coupon_id, coupons[coupon_id]

          coupon = Data.mock_coupon({ id: coupon_id })
          subscription[:discount] = Stripe::Util.convert_to_stripe_object({ coupon: coupon }, {})
        end

        assert_existence :plan, plan_name, plan
        params[:plan] = plan if params[:plan]
        verify_card_present(customer, plan)

        if subscription[:cancel_at_period_end]
          subscription[:cancel_at_period_end] = false
          subscription[:canceled_at] = nil
        end

        # TODO need to verify if the timing difference experienced here happens with stripe
        #   to make a long story short, between the initial request and the subsequent one to a paid package
        #   results in StripeMock updating the current_period_start due to #custom_subscription_params
        #   i believe stripe maintains the same period between requests
        if params[:current_period_start].nil? && !subscription[:current_period_start].nil?
          params[:current_period_start] = subscription[:current_period_start]

        end

        subscription.merge!(custom_subscription_params(plan, customer, params))


        old_subscription = customer[:subscriptions][:data].find { |sub| sub[:id] == subscription[:id] }.clone

        customer[:subscriptions][:data].delete(old_subscription)

        customer[:subscriptions][:data] << subscription
        if subscription && old_subscription && old_subscription[:current_period_start] == subscription[:current_period_start]
          if params[:prorate]

            customer[:upcoming] ||= []
            if old_plan[:amount] == 0

              line = Data.mock_subscription_line_item_from_plan(new_plan)
              line[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}

              customer[:upcoming] << line
            elsif old_plan[:interval] == new_plan[:interval]
              # Moving to a new plan
              if new_plan[:amount] > old_plan[:amount]

                line_item = Data.mock_subscription_line_item_from_plan(new_plan)

                old_line_item = Data.mock_subscription_line_item_from_plan(old_plan)

                old_line_item[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}
                if old = customer[:upcoming].find{|u| u[:amount] == old_line_item[:amount] && u[:period][:start] == old_line_item[:period][:start]}
                  customer[:upcoming].delete(old)
                end

                old_line_item[:amount] = -old_line_item[:amount]

                line_two = line_item.clone
                line_item[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}

                line_two[:period] = {start: subscription[:current_period_end], end: future_end_time_for(new_plan, subscription)}

                customer[:upcoming] += [line_item, old_line_item, line_two]

              elsif new_plan[:amount] < old_plan[:amount]
                # TODO should probably handle annual vs monthly, if the new plan is less than half the old plan, then it won't be a full
                #   credit the next period
                # EX: new_plan(50)  old_plan(60) -> results in -> [-50, 10] for next upcoming invoice[now, next_period]
                # They get a lot of credit for time unused
                line_item = Data.mock_subscription_line_item_from_plan(new_plan)
                # line_item[:type] = 'subscription'

                prorate_item = Data.mock_subscription_line_item_from_plan(old_plan)


                # Problem here
                line_item[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}
                line_item[:description] = "Remaining time on #{plan[:name]} after 08 Mar 2016"

                future_line_item = line_item.clone

                future_line_item[:period] = {start: subscription[:current_period_end], end: future_end_time_for(new_plan, subscription)}


                prorate_item[:period] = {start: subscription[:current_period_start], end: subscription[:current_period_end]}


                # See if there was a previously prorated charge and remove it, since the date will no longer be correct
                if existing = customer[:upcoming].find{|u| u[:amount] == prorate_item[:amount] && u[:period][:start] >= prorate_item[:period][:start]}
                  #TODO also check that plans match AND dates are correct
                  customer[:upcoming].delete(existing)
                end

                prorate_item[:amount] = -prorate_item[:amount]
                # TODO include actual date
                prorate_item[:description] = "Unused time on #{plan[:name]} after <08 Mar 2016>"
                customer[:upcoming] += [line_item, future_line_item, prorate_item]
              else
                old_plan[:amount]
              end
            else
              # Interval type changed
              # TODO should mock the charge here
              # TODO handle year -> month & month -> year separately
              line_item = Data.mock_subscription_line_item_from_plan(new_plan)
              # For now I'm just going to reset this, since stripe forces the charge in these cases.
              # TODO this won't be correct if there were a lot of other subscription changes
              customer[:upcoming] = [line_item]
            end
          end
        end

        subscription
      end

      def cancel_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existence :customer, $1, customers[$1]

        subscription = get_customer_subscription(customer, $2)
        assert_existence :subscription, $2, subscription

        cancel_params = { canceled_at: Time.now.utc.to_i }
        cancelled_at_period_end = (params[:at_period_end] == true)
        if cancelled_at_period_end
          cancel_params[:cancel_at_period_end] = true
        else
          cancel_params[:status] = "canceled"
          cancel_params[:cancel_at_period_end] = false
          cancel_params[:ended_at] = Time.now.utc.to_i
        end

        subscription.merge!(cancel_params)

        unless cancelled_at_period_end
          delete_subscription_from_customer customer, subscription
        end

        subscription
      end

      private

      def verify_card_present(customer, plan, params={})
        if customer[:default_source].nil? && customer[:trial_end].nil? && plan[:trial_period_days].nil? &&
           plan[:amount] != 0 && plan[:trial_end].nil? && params[:trial_end].nil?
          raise Stripe::InvalidRequestError.new('You must supply a valid card xoxo', nil, 400)
        end
      end

    end
  end
end
