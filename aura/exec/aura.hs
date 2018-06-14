{-# LANGUAGE TupleSections #-}
{-# LANGUAGE OverloadedStrings #-}

{-

Copyright 2012 - 2018 Colin Woodbury <colin@fosskers.ca>

This file is part of Aura.

Aura is free s

             oftwar
        e:youcanredist
     ributeitand/ormodify
    itunderthetermsoftheGN
   UGeneralPublicLicenseasp
  ublishedbytheFreeSoftw
 areFoundation,either     ver        sio        n3o        fth
 eLicense,or(atyou       ropti      on)an      ylate      rvers
ion.Auraisdistr         ibutedi    nthehop    ethatit    willbeu
 seful,butWITHOUTA       NYWAR      RANTY      ;with      outev
 entheimpliedwarranty     ofM        ERC        HAN        TAB
  ILITYorFITNESSFORAPART
   ICULARPURPOSE.SeetheGNUG
    eneralPublicLicensefor
     moredetails.Youshoul
        dhavereceiveda
             copyof

the GNU General Public License
along with Aura.  If not, see <http://www.gnu.org/licenses/>.

-}

module Main where

-- import           Aura.Colour.Text (yellow)
import           Aura.Commands.A as A
import           Aura.Commands.B as B
import           Aura.Commands.C as C
import           Aura.Commands.L as L
import           Aura.Commands.O as O
import           Aura.Core
import           Aura.Languages
import           Aura.Logo
import           Aura.Monad.Aura
import           Aura.Pacman
import           Aura.Settings.Base
import           Aura.Types
import           BasePrelude hiding (Version)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           Flags
import           Options.Applicative
import           Settings
import           Shelly (toTextIgnore, shelly, run_)
import           Utilities

---

auraVersion :: T.Text
auraVersion = "1.5.0"

main :: IO ()
main = do
  options   <- execParser opts
  esettings <- getSettings options
  case esettings of
    Left err -> T.putStrLn . ($ English) $ _failure err
    Right ss -> execute ss options >>= exit

execute :: Settings -> Program -> IO (Either T.Text ())
execute ss p = first (($ langOf ss) . _failure) <$> runAura (executeOpts p) ss

exit :: Either T.Text () -> IO a
exit (Left e)  = scold e *> exitFailure
exit (Right _) = exitSuccess

executeOpts :: Program -> Aura (Either Failure ())
executeOpts (Program ops _ _ _) = do
  case ops of
    Left o -> pacman $ asFlag o
    Right (AurSync o) ->
      case o of
        Right ps              -> fmap (join . join) . trueRoot . sudo $ A.install ps
        Left (AurDeps ps)     -> A.displayPkgDeps ps
        Left (AurInfo ps)     -> Right <$> A.aurPkgInfo ps
        Left (AurPkgbuild ps) -> Right <$> A.displayPkgbuild ps
        Left (AurSearch s)    -> Right <$> A.aurPkgSearch s
        Left (AurUpgrade ps)  -> fmap (join . join) . trueRoot . sudo $ A.upgradeAURPkgs ps
        Left (AurTarball ps)  -> Right <$> A.downloadTarballs ps
    Right (Backup o) ->
      case o of
        Nothing              -> sudo B.saveState
        Just (BackupClean n) -> fmap join . sudo $ B.cleanStates n
        Just BackupRestore   -> join <$> sudo B.restoreState
    Right (Cache o) ->
      case o of
        Right ps               -> fmap Right . liftIO $ traverse_ T.putStrLn ps
        Left (CacheSearch s)   -> Right <$> C.searchCache s
        Left (CacheClean n)    -> fmap join . sudo $ C.cleanCache n
        Left (CacheBackup pth) -> fmap join . sudo $ C.backupCache pth
    Right (Log o) ->
      case o of
        Nothing            -> Right <$> L.viewLogFile
        Just (LogInfo ps)  -> Right <$> L.logInfoOnPkg ps
        Just (LogSearch s) -> ask >>= fmap Right . liftIO . flip L.searchLogFile s
    Right (Orphans o) ->
      case o of
        Nothing               -> O.displayOrphans
        Just OrphanAbandon    -> fmap join . sudo $ orphans >>= removePkgs
        Just (OrphanAdopt ps) -> O.adoptPkg ps
    Right Version -> getVersionInfo >>= fmap Right . animateVersionMsg
{-

-- | Hand user input to the Aura Monad and run it.
execute :: (UserInput, Settings) -> IO (Either T.Text ())
execute ((flags, input, pacOpts), ss) = do
  let flags' = filter notSettingsFlag flags
  when (Debug `elem` flags) $ debugOutput ss
  first (($ langOf ss) . _failure) <$> runAura (executeOpts (flags', input, pacOpts)) ss

-- | After determining what Flag was given, dispatches a function.
-- The `flags` must be sorted to guarantee the pattern matching
-- below will work properly.
-- If no matches on Aura flags are found, the flags are assumed to be
-- pacman's.
executeOpts :: UserInput -> Aura (Either Failure ())
executeOpts ([], _, []) = executeOpts ([Help], [], [])
executeOpts (flags, input, pacOpts) =
  case sort flags of
    (AURInstall:fs) ->
        case fs of
          []             -> fmap (join . join) . trueRoot . sudo $ A.install (map T.pack pacOpts) (map T.pack input)
          [Upgrade]      -> fmap (join . join) . trueRoot . sudo $ A.upgradeAURPkgs (map T.pack pacOpts) (map T.pack input)
          [Info]         -> Right <$> A.aurPkgInfo (map T.pack input)
          [Search]       -> Right <$> A.aurPkgSearch (map T.pack input)
          [ViewDeps]     -> A.displayPkgDeps (map T.pack input)
          [Download]     -> Right <$> A.downloadTarballs (map T.pack input)
          [GetPkgbuild]  -> Right <$> A.displayPkgbuild (map T.pack input)
          (Refresh:fs')  -> fmap join . sudo $ syncAndContinue (fs', input, pacOpts)
          _              -> pure $ failure executeOpts_1
    (SaveState:fs) ->
        case fs of
          []             -> sudo B.saveState
          [Clean]        -> fmap join . sudo $ B.cleanStates input
          [RestoreState] -> join <$> sudo B.restoreState
          _              -> pure $ failure executeOpts_1
    (Cache:fs) ->
        case fs of
          []             -> fmap join . sudo $ C.downgradePackages (map T.pack pacOpts) (map T.pack input)
          [Clean]        -> fmap join . sudo $ C.cleanCache (map T.pack input)
          [Clean, Clean] -> join <$> sudo C.cleanNotSaved
          [Search]       -> fmap Right . C.searchCache $ map T.pack input
          [CacheBackup]  -> fmap join . sudo $ C.backupCache (map (fromText . T.pack) input)
          _              -> pure $ failure executeOpts_1
    (LogFile:fs) ->
        case fs of
          []       -> ask >>= fmap Right . L.viewLogFile . logFilePathOf
          [Search] -> ask >>= fmap Right . liftIO . flip L.searchLogFile (map T.pack input)
          [Info]   -> Right <$> L.logInfoOnPkg (map T.pack input)
          _        -> pure $ failure executeOpts_1
    (Orphans:fs) ->
        case fs of
          []        -> O.displayOrphans (map T.pack input)
          [Abandon] -> fmap join . sudo $ orphans >>= flip removePkgs (map T.pack pacOpts)
          _         -> pure $ failure executeOpts_1
    [ViewConf]  -> Right <$> viewConfFile
    [Languages] -> Right <$> displayOutputLanguages
    [Help]      -> printHelpMsg $ map T.pack pacOpts
    [Version]   -> getVersionInfo >>= fmap Right . animateVersionMsg
    _ -> pacman $ map T.pack pacOpts <> map T.pack hijackedFlags <> map T.pack input
    where hijackedFlags = reconvertFlags hijackedFlagMap flags
-}

-- | `-y` was included with `-A`. Sync database before continuing.
-- syncAndContinue :: UserInput -> Aura (Either Failure ())
-- syncAndContinue (flags, input, pacOpts) = do
--   syncDatabase (map T.pack pacOpts)
--   executeOpts (AURInstall:flags, input, pacOpts)

----------
-- GENERAL
----------
viewConfFile :: Aura ()
viewConfFile = shelly $ run_ "less" [toTextIgnore pacmanConfFile]

displayOutputLanguages :: Aura ()
displayOutputLanguages = do
  asks langOf >>= notify . displayOutputLanguages_1
  liftIO $ traverse_ print allLanguages

{-
printHelpMsg :: [T.Text] -> Aura (Either Failure ())
printHelpMsg [] = do
  ss <- ask
  pacmanHelp <- getPacmanHelpMsg
  fmap Right . liftIO . T.putStrLn $ getHelpMsg ss pacmanHelp
printHelpMsg pacOpts = pacman $ pacOpts <> ["-h"]

getHelpMsg :: Settings -> [T.Text] -> T.Text
getHelpMsg settings pacmanHelpMsg = T.unlines allMessages
    where lang = langOf settings
          allMessages   = [replacedLines, auraOperMsg lang, manpageMsg lang]
          replacedLines = T.unlines (map (replaceByPatt patterns) pacmanHelpMsg)
          colouredMsg   = yellow $ inheritedOperTitle lang
          patterns      = [Pattern "pacman" "aura", Pattern "operations" colouredMsg]
-}

-- | Animated version message.
animateVersionMsg :: [T.Text] -> Aura ()
animateVersionMsg verMsg = ask >>= \ss -> liftIO $ do
  hideCursor
  traverse_ (T.putStrLn . padString verMsgPad) verMsg  -- Version message
  raiseCursorBy 7  -- Initial reraising of the cursor.
  drawPills 3
  traverse_ T.putStrLn $ renderPacmanHead 0 Open  -- Initial rendering of head.
  raiseCursorBy 4
  takeABite 0  -- Initial bite animation.
  traverse_ pillEating pillsAndWidths
  clearGrid
  T.putStrLn auraLogo
  T.putStrLn $ "AURA Version " <> auraVersion
  T.putStrLn " by Colin Woodbury\n"
  traverse_ T.putStrLn . translatorMsg . langOf $ ss
  showCursor
    where pillEating (p, w) = clearGrid *> drawPills p *> takeABite w
          pillsAndWidths   = [(2, 5), (1, 10), (0, 15)]