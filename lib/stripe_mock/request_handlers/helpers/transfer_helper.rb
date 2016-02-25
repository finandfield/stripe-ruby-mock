module StripeMock
  module RequestHandlers
    module Helpers
      def find_object_from_transfer_destination(destination)
        if is_account?(destination)
          accounts[destination]
        else
          find_account_with_bank(destination)
        end
      end

      def is_account?(id)
        id.include?('acct_')
      end

      def is_bank?(id)
        id.include?('ba_')
      end

    end
  end
end