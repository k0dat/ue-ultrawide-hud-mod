# Echo Point Nova: other fixes

Fixes that are separate from UEUltrawideHUDMod but improve the game on an ultrawide screen.

## FOV aspect ratio fix

1. Open `%LOCALAPPDATA%\Greylock\Saved\Config\WindowsNoEditor\`.
2. Edit `Engine.ini`.
3. Add the following:

   ```ini
   [/script/engine.localplayer]
   AspectRatioAxisConstraint=AspectRatio_MaintainYFOV
   ```
