{-# LANGUAGE LambdaCase #-}
module Cardano.Wallet.Kernel.ProtocolParameters where

import           Universum

import qualified Data.ByteString.Char8 as B8
import           Servant.Client (BaseUrl (..), Scheme (..))

import Cardano.Node.Manager (credentialLoadX509)
import           Cardano.Wallet.Client
import           Cardano.Wallet.Client.Http
import Cardano.Wallet.Server.CLI
import           Network.HTTP.Client (Manager, newManager)
--import           Cardano.Node.API
import Cardano.Node.Manager (mkHttpsManagerSettings, readSignedObject)
--import qualified Pos.Node.API as P
import Pos.Web.Types


hello :: IO ()
hello = do
    return ()

setupClient :: WalletBackendParams -> IO (WalletClient IO, Manager)
setupClient params = do
    let (serverHost', serverPort') = walletAddress params
    let (serverHost, serverPort) = (B8.unpack serverHost', fromIntegral serverPort')
    let serverId = (serverHost, B8.pack $ show serverPort)


    let tlsParams = maybe (error "TODO") id $ walletTLSParams params
    let tlsPrivKeyPath    = tpKeyPath  tlsParams
    let tlsClientCertPath = tpCertPath tlsParams -- ????

    let tlsCACertPath = tpCaPath tlsParams

    caChain <- readSignedObject tlsCACertPath

    clientCredentials <- credentialLoadX509 tlsClientCertPath tlsPrivKeyPath >>= \case
        Right   a -> return a
        Left  err -> fail $ "Error decoding X509 certificates: " <> err
    manager <- newManager $ mkHttpsManagerSettings serverId caChain clientCredentials

    let
        baseUrl = BaseUrl Https serverHost serverPort mempty
        walletClient :: MonadIO m => WalletClient m
        walletClient = withThrottlingRetry
            . liftClient
            $ mkHttpClient baseUrl manager

    return (walletClient, manager)
