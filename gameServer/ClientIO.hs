{-# LANGUAGE ScopedTypeVariables #-}
module ClientIO where

import qualified Control.Exception as Exception
import Control.Concurrent.Chan
import Control.Concurrent
import Control.Monad
import System.IO
import qualified Data.ByteString.UTF8 as BUTF8
import qualified Data.ByteString as B
----------------
import CoreTypes
import RoomsAndClients

listenLoop :: Handle -> Int -> [String] -> Chan CoreMessage -> ClientIndex -> IO ()
listenLoop handle linesNumber buf chan clientID = do
    putStrLn $ show handle ++ show buf ++ show clientID
    str <- liftM BUTF8.toString $ B.hGetLine handle
    if (linesNumber > 50) || (length str > 450) then
           protocolViolationMsg >> freeClient
        else
        if str == "" then do
            writeChan chan $ ClientMessage (clientID, reverse buf)
            yield
            listenLoop handle 0 [] chan clientID
            else
            listenLoop handle (linesNumber + 1) (str : buf) chan clientID
    where 
        protocolViolationMsg = writeChan chan $ ClientMessage (clientID, ["QUIT", "Protocol violation"])
        freeClient = writeChan chan $ FreeClient clientID


clientRecvLoop :: Handle -> Chan CoreMessage -> ClientIndex -> IO ()
clientRecvLoop handle chan clientID =
    listenLoop handle 0 [] chan clientID
        `catch` (\e -> clientOff (show e) >> freeClient >> return ())
    where 
        clientOff msg = writeChan chan $ ClientMessage (clientID, ["QUIT", msg]) -- if the client disconnects, we perform as if it sent QUIT message
        freeClient = writeChan chan $ FreeClient clientID

clientSendLoop :: Handle -> Chan CoreMessage -> Chan [String] -> ClientIndex -> IO()
clientSendLoop handle coreChan chan clientID = do
    answer <- readChan chan
    doClose <- Exception.handle
        (\(e :: Exception.IOException) -> if isQuit answer then return True else sendQuit e >> return False) $ do
            B.hPutStrLn handle $ BUTF8.fromString $ unlines answer
            hFlush handle
            return $ isQuit answer

    if doClose then
        Exception.handle (\(_ :: Exception.IOException) -> putStrLn "error on hClose") $ hClose handle
        else
        clientSendLoop handle coreChan chan clientID

    where
        sendQuit e = writeChan coreChan $ ClientMessage (clientID, ["QUIT", show e])
        isQuit ("BYE":xs) = True
        isQuit _ = False
