module StripeMock
  module RequestHandlers
    module Transfers

      def Transfers.included(klass)
        klass.add_handler 'post /v1/transfers',             :new_transfer
        klass.add_handler 'get /v1/transfers',              :get_all_transfers
        klass.add_handler 'get /v1/transfers/(.*)',         :get_transfer
        klass.add_handler 'post /v1/transfers/(.*)/cancel', :cancel_transfer
      end

      def get_all_transfers(route, method_url, params, headers)
        if recipient = params[:recipient]
          assert_existence :recipient, recipient, recipients[recipient]
        end

        if destination = params[:destination]
          if is_account?(destination)
            account = assert_existence :accounts, destination, accounts[destination]
          end
        end

        _transfers = transfers.each_with_object([]) do |(_, transfer), array|
          if recipient
            array << transfer if transfer[:recipient] == recipient
          elsif destination
            array << transfer if transfer[:destination] == destination
          else
            array << transfer
          end
        end

        if params[:limit]
          _transfers = _transfers.first([params[:limit], _transfers.size].min)
        end

        Data.mock_list_object(_transfers, params)
      end

      def new_transfer(route, method_url, params, headers)
        id = new_id('tr')
        begin
          object = find_object_from_transfer_params(params)
        rescue => e
          binding.pry
        end

        begin
          if is_bank?(params[:destination])
            @bank = find_bank_in_account(object, params[:destination])
          elsif is_bank?(params[:bank_account])
            @bank = find_bank_in_account(object, params[:destination])
          elsif is_account?(params[:destination])
            @account = object
          end
        rescue => e
          binding.pry
        end

        # binding.pry
        # if params[:bank_account]
        #   params[:account] = get_bank_by_token(params.delete(:bank_account))
        # end
        # binding.pry

        #TODO handle application fees/stripe processing fees
        params[:amount] = params[:amount] - params[:application_fee] if params[:application_fee]

        unless params[:amount].is_a?(Integer) || (params[:amount].is_a?(String) && /^\d+$/.match(params[:amount]))
          raise Stripe::InvalidRequestError.new("Invalid integer: #{params[:amount]}", 'amount', 400)
        end

        params.merge!(:id => id)

        if is_bank?(params[:destination])
          begin
            transfer = Data.mock_bank_transfer(object[:id], params)

            transfer.merge!({bank_account: @bank}) if @bank

            object[:balance][:available].first[:amount] -= transfer[:amount]
            object[:balance][:available].first[:source_types][transfer[:source_type].to_sym] -= transfer[:amount]

            transfers[id] = transfer
          rescue => e
            binding.pry
          end
        elsif is_account?(params[:destination])
          transfer = Data.mock_account_transfer(params)

          # TODO handle negative master account balances(throw same exception as stripe)
          $master_account[:balance][:available].first[:amount] -= transfer[:amount]
          $master_account[:balance][:available].first[:source_types][transfer[:source_type].to_sym] += transfer[:amount]

          #TODO need to handle pending/available
          #TODO use correct currencies for balance addition using transfer[:currency]
          object[:balance][:available].first[:amount] += transfer[:amount]
          object[:balance][:available].first[:source_types][transfer[:source_type].to_sym] += transfer[:amount]

          #TODO also transfer to account pending/available balances
          transfers[id] = transfer
        end
        # binding.pry
        transfer
      end

      def get_transfer(route, method_url, params, headers)
        route =~ method_url
        assert_existence :transfer, $1, transfers[$1]
        transfers[$1] ||= Data.mock_transfer(:id => $1)
      end

      def cancel_transfer(route, method_url, params, headers)
        route =~ method_url
        assert_existence :transfer, $1, transfers[$1]
        t = transfers[$1] ||= Data.mock_transfer(:id => $1)
        t.merge!({:status => "canceled"})
      end
    end
  end
end
