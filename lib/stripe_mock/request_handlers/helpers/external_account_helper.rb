module StripeMock
  module RequestHandlers
    module Helpers

      def get_account_external_sources(account, acct_id)
        account[:external_accounts][:data].find{|acct| acct[:id] == acct_id }
      end

      def add_external_account_to_account(id, params, replace_current=false)
        account = assert_existence :account, id, accounts[id]
        external_accounts = account[:external_accounts]
        params[:id] ||= new_id('ba')

        external_account = Data.mock_external_account(id, params)
        (external_accounts[:data] ||= []) << external_account

        external_account
      end
    end
  end
end