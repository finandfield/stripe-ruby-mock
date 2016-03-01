module StripeMock
  module RequestHandlers
    module Helpers

      def get_account_external_sources(account, acct_id)
        account[:external_accounts][:data].find{|acct| acct[:id] == acct_id }
      end

      def find_external_account_for_account(account, bank_id)
        account[:external_accounts][:data].find{|ex_acct| ex_acct == bank_id }
      end

      def find_account_with_bank(bank_id)
        found_account = nil
        accounts.each do |id, account|
          if account[:external_accounts][:data].find{|ba| ba[:id] == bank_id }
            found_account = account
            break
          end
        end
        found_account
        # accounts.values.find{|acct| acct[:external_accounts][:data].find{|ba| ba[:id] == bank_id } }
      end

      def find_bank_in_account(account, bank_id)
        # binding.pry
        begin
          account[:external_accounts][:data].find{|ba| ba[:id] == bank_id }
        rescue => e
          binding.pry
        end
      end

      def find_bank_account_in_accounts(bank_id)

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