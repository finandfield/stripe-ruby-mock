module StripeMock
  module RequestHandlers
    module Helpers

      def request_as_connected_account(account, &block)
        key = Stripe.api_key

        Stripe.api_key = account[:keys][:secret]

        result = block.call

        Stripe.api_key = key
      end

      def get_account_by_secret_key
        account = accounts.select do |id, account|
          account[:keys] && account[:keys][:secret] == Stripe.api_key
        end.values.first
        account
      end
    end
  end
end