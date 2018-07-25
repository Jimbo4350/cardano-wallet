{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

module Cardano.Wallet.API.V1.Handlers.Transactions (
      handlers
    , newTransaction
    , getTransactionsHistory
    , estimateFees
    ) where

import           Universum

import           Servant

import           Data.Coerce (coerce)

import           Cardano.Wallet.Kernel.CoinSelection.FromGeneric
                     (ExpenseRegulation (..), InputGrouping (..))
import           Cardano.Wallet.Kernel.Util (getCurrentTimestamp, paymentAmount)
import qualified Cardano.Wallet.WalletLayer as WalletLayer
import           Cardano.Wallet.WalletLayer.Types (ActiveWalletLayer)

import           Pos.Client.Txp.Util (InputSelectionPolicy (..),
                     defaultInputSelectionPolicy)
import           Pos.Core (Address)
import           Pos.Core.Txp (Tx (..), TxOut (..))
import           Pos.Crypto (hash)

import           Cardano.Wallet.API.Request
import           Cardano.Wallet.API.Response
import qualified Cardano.Wallet.API.V1.Transactions as Transactions
import           Cardano.Wallet.API.V1.Types

handlers :: ActiveWalletLayer IO -> ServerT Transactions.API Handler
handlers aw = newTransaction aw
         :<|> getTransactionsHistory
         :<|> estimateFees aw


-- Matches the input InputGroupingPolicy with the Kernel's 'InputGrouping'
toInputGrouping :: Maybe (V1 InputSelectionPolicy) -> InputGrouping
toInputGrouping v1GroupingPolicy =
    let (V1 policy) = fromMaybe (V1 defaultInputSelectionPolicy) v1GroupingPolicy
    in case policy of
            OptimizeForSecurity       -> PreferGrouping
            OptimizeForHighThroughput -> IgnoreGrouping

-- | Given a 'Payment' as input, tries to generate a new 'Transaction', submitting
-- it to the network eventually.
newTransaction :: ActiveWalletLayer IO
               -> Payment
               -> Handler (WalletResponse Transaction)
newTransaction aw payment@Payment{..} = do

    -- TODO(adn) If the wallet is being restored, we need to disallow any @Payment@ from
    -- being submitted.
    -- NOTE(adn) The 'SenderPaysFee' option will become configurable as part
    -- of CBR-291.
    res <- liftIO $ (WalletLayer.pay aw) (maybe mempty coerce pmtSpendingPassword)
                                         (toInputGrouping pmtGroupingPolicy)
                                         SenderPaysFee
                                         payment
    case res of
         Left err -> throwM err
         Right tx -> do
             now <- liftIO getCurrentTimestamp
             -- NOTE(adn) As part of [CBR-329], we could simply fetch the
             -- entire 'Transaction' as part of the TxMeta.
             return $ single Transaction {
                               txId            = V1 (hash tx)
                             , txConfirmations = 0
                             , txAmount        = V1 (paymentAmount $ _txOutputs tx)
                             , txInputs        = error "TODO, see [CBR-324]"
                             , txOutputs       = fmap outputsToDistribution (_txOutputs tx)
                             , txType          = error "TODO, see [CBR-324]"
                             , txDirection     = OutgoingTransaction
                             , txCreationTime  = V1 now
                             , txStatus        = Creating
                             }
    where
        outputsToDistribution :: TxOut -> PaymentDistribution
        outputsToDistribution (TxOut addr amount) = PaymentDistribution (V1 addr) (V1 amount)

getTransactionsHistory :: Maybe WalletId
                       -> Maybe AccountIndex
                       -> Maybe (V1 Address)
                       -> RequestParams
                       -> FilterOperations Transaction
                       -> SortOperations Transaction
                       -> Handler (WalletResponse [Transaction])
getTransactionsHistory _ _ _ _ _ _ =
  liftIO ret
    where
      ret = error "TODO" -- CBR-239

-- | Computes the fees generated by this payment, without actually sending
-- the transaction to the network.
estimateFees :: ActiveWalletLayer IO
             -> Payment
             -> Handler (WalletResponse EstimatedFees)
estimateFees aw payment@Payment{..} = do
    let spendingPassword = maybe mempty coerce pmtSpendingPassword
    res <- liftIO $ (WalletLayer.estimateFees aw) spendingPassword
                                                  (toInputGrouping pmtGroupingPolicy)
                                                  SenderPaysFee
                                                  payment
    case res of
         Left err  -> throwM err
         Right fee -> return $ single (EstimatedFees (V1 fee))
