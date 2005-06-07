{-# OPTIONS -cpp -#include HSCursesUtils.h -#include <signal.h> #-}

-- 
-- Copyright (C) 2005 Stefan Wehr
--
-- Derived from: yi/Curses/UI.hs
--      Copyright (C) 2004 Don Stewart - http://www.cse.unsw.edu.au/~dons
--      Released under the same license.
--
-- Derived from: riot/UI.hs
--      Copyright (c) Tuomo Valkonen 2004.
--      Released under the same license.
-- 
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation; either version 2 of
-- the License, or (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
-- General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
-- 02111-1307, USA.
-- 
--

module HSCurses.CursesHelper (

        -- * UI initialisation 
        start, end, suspend, resizeui,

        -- * Input
        getKey,

        -- * Drawing
        drawLine, drawCursor,

        -- * Navigation
        gotoTop,

        -- * Colors
        ForegroundColor(..), BackgroundColor(..),
        defaultColor, black, red, green, yellow, blue, magenta, cyan, white,

        -- * Attributes
        Attribute(..), convertAttributes,

        -- * Style
        Style(..), CursesStyle, mkCursesStyle, changeCursesStyle,
        setStyle, resetStyle, convertStyles,
        defaultStyle, defaultCursesStyle, withStyle, 

        -- * Keys
        displayKey,

        -- * Helpers
        withCursor, withProgram
  )   where

import HSCurses.Curses hiding ( refresh, Window )
import qualified HSCurses.Curses as Curses
import HSCurses.Logging

import Char
import Data.Maybe
import Data.List
import Control.Monad.Trans
import HSCurses.MonadException
import System.Posix.Signals

--
--

--
-- | @start@ initializes the UI and grabs the keyboard.
--
-- This function does not install a handler for the SIGWINCH signal.
-- This signal is sent when the terminal size changes, so it seems
-- a good idea to catch the signal and redraw your application from
-- within the handler. This approach is problematic for 3 reasons:
--
-- 1. Redraw is performed asynchronously.
-- 2. The redraw function cannot live in an application-specific monad.
--    The only way to access the application's state (which is certainly
--    necessary for doing the redraw) is via IORefs or similar constructs.
-- 3. SIGWINCH is not available on all platforms
--
-- The IMHO better solution for reacting on changes of the terminal size
-- is to check if @HSCurses.Curses.getCh@ returns the 
-- @HSCurses.Curses.keyResize@ character. This solution is implemented by
-- the @getKey@ function. The callback passed to @getKey@ can now live
-- in an application-specific monad and so it's possible to use parts of the
-- application's state for redrawing. The only disadvantage of this solution
-- is that it is a bit slower than reacting on the SIGWINCH signal.
--
-- If you want to redraw your application from a SIGWINCH handler, you
-- have to do the following: Install an appropriate handler for
-- the SIGWINCH signal (if available for the platform); the
-- signal is defined as @HSCurses.Curses.cursesSigWinch@. The redraw
-- handler passed to @getKey@ should then perform the redraw only if 
-- the signal is not available for the platform.
-- 
start :: IO ()
start = do
    Curses.initCurses           -- initialise the screen
    Curses.keypad Curses.stdScr True    -- grab the keyboard


--
-- | Clean up and go home. 
--
end :: IO ()
end = do Curses.endWin
-- Refresh is needed on linux. grr.
#if NCURSES_UPDATE_AFTER_END
         Curses.update
#endif

--
-- | Suspend the program.
--
suspend :: IO ()
suspend = raiseSignal sigTSTP

--
-- | @getKey refresh@ reads a key.
--
-- The @refresh@ function is used to redraw the screen when the terminal size
-- changes (see the documentatio of @start@ for a discussion of the problem).
--
getKey :: MonadIO m => m () -> m Key
getKey refresh = do
    k <- liftIO $ Curses.getCh
    case k of
        Nothing -> getKey refresh
        Just KeyResize -> do refresh
                             getKey refresh
        Just k' -> return k'


--
-- | @drawLine n s@ draws @n@ characters of string @s@.
--
drawLine :: Int -> String -> IO ()
-- lazy version is faster than calculating length of s
drawLine w s = Curses.wAddStr Curses.stdScr $! take w (s ++ repeat ' ')

--
-- | Draw the cursor at the given position.
--
drawCursor :: (Int,Int) -> (Int, Int) -> IO ()
drawCursor (o_y,o_x) (y,x) = withCursor Curses.CursorVisible $ do
    gotoTop
    (h,w) <- scrSize
    Curses.wMove Curses.stdScr (min (h-1) (o_y + y)) (min (w-1) (o_x + x))

--
-- | Move cursor to origin of stdScr.
--
gotoTop :: IO ()
gotoTop = Curses.wMove Curses.stdScr 0 0


--
-- | Resize the window
-- From "Writing Programs with NCURSES", by Eric S. Raymond and 
-- Zeyd M. Ben-Halim
--
--
resizeui :: IO (Int,Int)
resizeui = do
    Curses.endWin
    Curses.refresh
    Curses.scrSize



------------------------------------------------------------------------
--
-- | Basic colors.
--
defaultColor :: Curses.Color
defaultColor = fromJust $ Curses.color "default"

black, red, green, yellow, blue, magenta, cyan, white :: Curses.Color
black     = fromJust $ Curses.color "black"
red       = fromJust $ Curses.color "red"
green     = fromJust $ Curses.color "green"
yellow    = fromJust $ Curses.color "yellow"
blue      = fromJust $ Curses.color "blue"
magenta   = fromJust $ Curses.color "magenta"
cyan      = fromJust $ Curses.color "cyan"
white     = fromJust $ Curses.color "white"

--
-- | Converts a list of 'Curses.Color' pairs (foreground color and
--   background color) into the curses representation 'Curses.Pair'.
--
--   You should call this function exactly once, at application startup.
--
-- (not visible outside this module)
colorsToPairs :: [(Curses.Color, Curses.Color)] -> IO [Curses.Pair]
colorsToPairs cs =
    do p <- Curses.colorPairs
       let nColors = length cs
           blackWhite = p < nColors
       if blackWhite
          then trace ("Terminal does not support enough colors. Number of " ++
                      " colors requested: " ++ show nColors ++ 
                      ". Number of colors supported: " ++ show p)
                 return $ take nColors (repeat (Curses.Pair 0))
          else mapM toPairs (zip [1..] cs)
     where toPairs (n, (fg, bg)) = 
               let p = Curses.Pair n 
               in do Curses.initPair p fg bg
                     return p

------------------------------------------------------------------------
-- Nicer, user-visible color defs.
--
-- We separate colors into dark and bright colors, to prevent users
-- from erroneously constructing bright colors for dark backgrounds,
-- which doesn't work.

--
-- | Foreground colors.
--
data ForegroundColor
    = BlackF
    | GreyF
    | DarkRedF
    | RedF
    | DarkGreenF
    | GreenF
    | BrownF
    | YellowF
    | DarkBlueF
    | BlueF
    | PurpleF
    | MagentaF
    | DarkCyanF
    | CyanF
    | WhiteF
    | BrightWhiteF
    | DefaultF
    deriving (Eq, Show)

--
-- | Background colors.
--
data BackgroundColor
    = BlackB
    | DarkRedB
    | DarkGreenB
    | BrownB
    | DarkBlueB
    | PurpleB
    | DarkCyanB
    | WhiteB
    | DefaultB
    deriving (Eq, Show)

--
-- | Mapping abstract colours to ncurses attributes and colours
--
-- (not visible outside this module)

convertBg :: BackgroundColor -> ([Attribute], Curses.Color)
convertBg c = case c of
    BlackB      -> ([], black)
    DarkRedB    -> ([], red)
    DarkGreenB  -> ([], green)
    BrownB      -> ([], yellow)
    DarkBlueB   -> ([], blue)
    PurpleB     -> ([], magenta)
    DarkCyanB   -> ([], cyan)
    WhiteB      -> ([], white)
    DefaultB    -> ([], defaultColor)

convertFg :: ForegroundColor -> ([Attribute], Curses.Color)
convertFg c = case c of
    BlackF       -> ([], black)
    GreyF        -> ([Bold], black)
    DarkRedF     -> ([], red)
    RedF         -> ([Bold], red)
    DarkGreenF   -> ([], green)
    GreenF       -> ([Bold], green)
    BrownF       -> ([], yellow)
    YellowF      -> ([Bold], yellow)
    DarkBlueF    -> ([], blue)
    BlueF        -> ([Bold], blue)
    PurpleF      -> ([], magenta)
    MagentaF     -> ([Bold], magenta)
    DarkCyanF    -> ([], cyan)
    CyanF        -> ([Bold], cyan)
    WhiteF       -> ([], white)
    BrightWhiteF -> ([Bold], white)
    DefaultF     -> ([], defaultColor)


------------------------------------------------------------------------
--
-- | Abstractions for some commonly used attributes.
--
data Attribute = Bold
               | Underline
               | Dim
               | Reverse
               | Blink
               deriving (Eq, Show)

--
-- | Converts an abstract attribute list into its curses representation.
--
convertAttributes :: [Attribute] -> Curses.Attr
convertAttributes = 
    foldr setAttrs Curses.attr0
    where setAttrs Bold = setBoldA
          setAttrs Underline = setUnderlineA
          setAttrs Dim = setDimA
          setAttrs Reverse = setReverseA
          setAttrs Blink = setBlinkA

setBoldA, setUnderlineA, setDimA, 
  setReverseA, setBlinkA :: Curses.Attr -> Curses.Attr
setBoldA = flip Curses.setBold True
setUnderlineA = flip Curses.setUnderline True
setDimA = flip Curses.setDim True
setReverseA = flip Curses.setReverse   True
setBlinkA = flip Curses.setBlink True

------------------------------------------------------------------------
--
-- | A humand-readable style.
--
data Style = Style ForegroundColor BackgroundColor
           | AttributeStyle [Attribute] ForegroundColor BackgroundColor
           | ColorlessStyle [Attribute]
           deriving (Eq, Show)

defaultStyle :: Style
defaultStyle = Style DefaultF DefaultB

--
-- | A style which uses the internal curses representations for
--   attributes and colors.
--
data CursesStyle = CursesStyle Curses.Attr Curses.Pair
                 | ColorlessCursesStyle Curses.Attr
                 deriving (Eq, Show)

{-
instance Show CursesStyle where
    show (CursesStyle _ _) = "CursesStyle"
    show (ColorlessCursesStyle _) = "ColorlessCursesStyle"
-}

mkCursesStyle :: [Attribute] -> CursesStyle
mkCursesStyle attrs = ColorlessCursesStyle (convertAttributes attrs)

--
-- | Changes the attributes of the given CursesStyle.
--
changeCursesStyle :: CursesStyle -> [Attribute] -> CursesStyle
changeCursesStyle (CursesStyle _ p) attrs =
    CursesStyle (convertAttributes attrs) p
changeCursesStyle _ attrs = ColorlessCursesStyle (convertAttributes attrs)

defaultCursesStyle :: CursesStyle
defaultCursesStyle = CursesStyle Curses.attr0 (Curses.Pair 0)

--
-- | Reset the screen to normal values
--
resetStyle :: IO ()
resetStyle = setStyle defaultCursesStyle

--
-- | Manipulate the current style of the standard screen
--
setStyle :: CursesStyle -> IO ()
setStyle (CursesStyle a p) = Curses.wAttrSet Curses.stdScr (a, p)
setStyle (ColorlessCursesStyle a) = 
    do (_, p) <- Curses.wAttrGet Curses.stdScr
       Curses.wAttrSet Curses.stdScr (a, p)

withStyle :: MonadExcIO m => CursesStyle -> m a -> m a
withStyle style action = 
    bracketM
        (liftIO $ do old <- Curses.wAttrGet Curses.stdScr    -- before
                     setStyle style
                     return old)
        (\old -> liftIO $ Curses.wAttrSet Curses.stdScr old) -- after
        (\_ -> action)                                       -- do this

--
-- | Converts a list of human-readable styles into the corresponding
--   curses representation. 
--
--   This function should be called exactly once at application startup
--   for all styles of the application.
convertStyles :: [Style] -> IO [CursesStyle]
convertStyles styleList =
    do let (attrs, cs) = unzip $ map convertStyle styleList
           cursesAttrs = map convertAttributes attrs
       cursesPairs <- colorsToPairs' cs
       let res = zipWith toCursesStyle cursesAttrs cursesPairs
       trace ("convertStyles: " ++ show (zip styleList res)) (return res)
    where convertStyle (Style fg bg) = convertStyle (AttributeStyle [] fg bg)
          convertStyle (AttributeStyle attrs fg bg) =
              let (afg, cfg) = convertFg fg
                  (abg, cbg) = convertBg bg
              in (afg ++ abg ++ attrs, Just (cfg, cbg))
          convertStyle (ColorlessStyle attrs) = (attrs, Nothing)
          colorsToPairs' cs = 
              do pairs <- colorsToPairs (catMaybes cs)
                 return $ mergeNothing cs pairs
          mergeNothing (Just _:crest) (p:prest) = Just p 
                                                  : mergeNothing crest prest
          mergeNothing (Nothing:crest) ps = Nothing : mergeNothing crest ps
          mergeNothing [] [] = []
          toCursesStyle cursesAttrs Nothing = 
              ColorlessCursesStyle cursesAttrs
          toCursesStyle cursesAttrs (Just cursesPair) = 
              CursesStyle cursesAttrs cursesPair

------------------------------------------------------------------------
--
-- | Converting keys to humand-readable strings
--

displayKey :: Key -> String
displayKey (KeyChar ' ') = "<Space>"
displayKey (KeyChar '\t') = "<Tab>"
displayKey (KeyChar '\r') = "<Enter>"
displayKey (KeyChar c) 
    | isPrint c = [c]
displayKey (KeyChar c)  -- Control
    | ord '\^A' <= ord c && ord c <= ord '\^Z'
        = let c' = chr $ ord c - ord '\^A' + ord 'a'
              in '^':[toUpper c']
displayKey (KeyChar c) = show c
displayKey KeyDown = "<Down>"
displayKey KeyUp = "<Up>"
displayKey KeyLeft = "<Left>"
displayKey KeyRight = "<Right>"
displayKey KeyHome = "<Home>"
displayKey KeyBackspace = "<BS>"
displayKey (KeyF i) = 'F' : show i
displayKey KeyNPage = "<NPage>"
displayKey KeyPPage = "<PPage>"
displayKey KeyEnter = "<Return>"
displayKey KeyEnd = "<End>"
displayKey KeyIC = "<Insert>"
displayKey KeyDC = "<Delete>"
displayKey k = show k


------------------------------------------------------------------------
--
-- | Other helpers
--

--
-- | set the cursor, and do action
--
withCursor :: MonadExcIO m => CursorVisibility -> m a -> m a
withCursor nv action = 
    bracketM
        (liftIO $ Curses.cursSet nv)             -- before
        (\vis -> liftIO $ Curses.cursSet vis)    -- after
        (\_ -> action)                           -- do this

withProgram :: MonadExcIO m => m a -> m a
withProgram action = withCursor CursorVisible $ 
    bracketM_ (liftIO endWin) (liftIO flushinp) action
