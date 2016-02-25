module StripeMock
  module RequestHandlers
    module Helpers
      def find_object_from_transfer_params(params)
        if is_account?(params[:destination])
          accounts[params[:destination]]
        elsif is_bank?(params[:destination])
          if params[:destination] == 'bank_account' && params[:bank_account].present?
            find_account_with_bank(params[:bank_account])
          else
            find_account_with_bank(params[:bank_account])
          end
        end
      end

      def is_account?(id)
        id && id.include?('acct_')
      end

      def is_bank?(id)
        id && (id.include?('ba_') || id == 'bank_account')
      end

      #TODO move to helper
      def is_master_account?
        $master_account[:keys][:secret] == Stripe.api_key
      end

    end
  end
end