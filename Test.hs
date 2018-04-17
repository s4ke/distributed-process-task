{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE GADTs     #-}
{-# LANGUAGE KindSignatures     #-}
{-# LANGUAGE DeriveAnyClass     #-}

module Main where

import Control.Distributed.Process hiding (call, catch)
import Control.Distributed.Process.Async
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Extras.Time
import Control.Distributed.Process.Extras.Timer
import Control.Distributed.Process.Extras.Internal.Types
import Control.Distributed.Process.Node
import Control.Distributed.Process.Management
  ( MxAgentId(..)
  , MxEvent(MxRegistered)
  , mxAgent
  , mxSink
  , mxReady
  , liftMX
  )
import Control.Distributed.Process.ManagedProcess hiding (runProcess)
import Control.Distributed.Process.Serializable()
import Control.DeepSeq
import Control.Concurrent.MVar
import Data.Typeable
import Data.Binary
--import Control.Distributed.Process.SysTest.Utils

import Control.Distributed.Process.Task.Queue.BlockingQueue hiding (start)
import qualified Control.Distributed.Process.Task.Queue.BlockingQueue as Pool (start)

import Control.Distributed.Process.Serializable

-- import TestUtils

import Network.Transport.TCP
import qualified Network.Transport as NT

class (NFData a) => Evaluatable a where
  eval :: a -> Closure (Process a)

tskBase :: NFData a => a -> Process a
tskBase a = (rnf a) `seq` (return a)

tsk :: Int -> Process Int
tsk = tskBase

$(remotable ['tsk])

instance Evaluatable Int where
  eval = $(mkClosure 'tsk)

startPool :: (Binary a, Typeable a) => a -> SizeLimit -> Process ProcessId
startPool a sz = spawnLocal $ do
  Pool.start $ helper a sz
  where
    helper :: (Binary a, Typeable a) => a -> SizeLimit -> Process (InitResult (BlockingQueue a))
    helper _ sz = pool sz

runTasksInPool :: (MVar Int) -> Process ()
runTasksInPool mvar = do
  pid <- startPool (1::Int) 100
  (Right res) <- executeTask pid (Main.eval ((10::Int)))
  liftIO $ putMVar mvar res

waitForDown :: MonitorRef -> Process DiedReason
waitForDown ref =
  receiveWait [ matchIf (\(ProcessMonitorNotification ref' _ _) -> ref == ref')
                        (\(ProcessMonitorNotification _ _ dr) -> return dr) ]

myRemoteTable :: RemoteTable
myRemoteTable = Main.__remoteTable initRemoteTable

tests :: NT.Transport  -> IO ()
tests transport = do
  localNode <- newLocalNode transport myRemoteTable
  mvar <- newEmptyMVar
  runProcess localNode (runTasksInPool mvar)
  val <- takeMVar mvar
  putStrLn $ show $ val

-- | Given a @builder@ function, make and run a test suite on a single transport
main :: IO ()
main = do
  Right (transport, _) <- createTransportExposeInternals
                                    "127.0.0.1" "0" defaultTCPParameters
  tests transport
