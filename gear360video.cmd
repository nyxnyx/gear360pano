:<<"::IGNORE_THIS_LINE"
@echo off
goto :CMDSCRIPT
::IGNORE_THIS_LINE

# This is a small script to stitch panorama videos produced
# by Samsung Gear360
#
# https://github.com/ultramango/gear360pano
#
# Trick with Win/Linux from here:
# http://stackoverflow.com/questions/17510688/single-script-to-run-in-both-windows-batch-and-linux-bash

################################ Linux part here

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in
DIR=$(dirname `which $0`)
FRAMESTEMPDIR=`mktemp -d`
OUTTEMPDIR=`mktemp -d`
IMAGETMPL="image%05d.jpg"
IMAGETMPLENC="image%05d_pano.jpg"
PTOTMPL="$DIR/gear360video.pto"
TMPAUDIO="tmpaudio.aac"
TMPVIDEO="tmpvideo.mp4"
# Debug
DEBUG=""

# Debug, arguments:
# 1. Text to print
print_debug() {
  if [ "$DEBUG" == "yes" ]; then
    echo "DEBUG: $@"
  fi
}

# Clean-up function
clean_up() {
  echo "Removing temporary directories..."
  if [ -d "$FRAMESTEMPDIR" ]; then
    print_debug "Removing frames directory: $FRAMESTEMPDIR"
    rm -rf "$FRAMESTEMPDIR"
  fi
  if [ -d "$OUTTEMPDIR" ]; then
    print_debug "Removing output directory: $OUTTEMPDIR"
    rm -rf "$OUTTEMPDIR"
  fi
}

# Function to check if a command fails
# http://stackoverflow.com/questions/5195607/checking-bash-exit-status-of-several-commands-efficiently
run_command() {
  # Remove empty arguments (it will confuse the executed command)
  cmd=("$@")
  for i in "${!cmd[@]}"; do
    [ -n "${cmd[$i]}" ] || unset "cmd[$i]"
  done

  print_debug "Running command: " "${cmd[@]}"
  "${cmd[@]}"
  local status=$?
  if [ $status -ne 0 ]; then
    echo "Error while running $1" >&2
    if [ $1 != "notify-send" ]; then
       # Display error in a nice graphical popup if available
       run_command notify-send -a $0 "Error while running $1"
    fi
    clean_up
    exit 1
  fi
  return $status
}

# Check argument(s)
if [ -z "$1" ]; then
  echo "Small script to stitch panoramic videos."
  echo -e "Script originally writen for Samsung Gear 360.\n"
  echo -e "Usage:\n$0 inputdir [outputfile]\n"
  echo "Where inputfile is a panoramic video file,"
  echo "output parameter is optional."
  run_command notify-send -a $0 "Please provide an input file."
  sleep 2
  exit 1
fi

# Output name as second argument
if [ -z "$2" ]; then
  # If invoked by nautilus open-with, we need to remember the proper directory in the outname
  OUTNAME=`dirname "$1"`/`basename "${1%.*}"`_pano.mp4
  print_debug "Output filename: $OUTNAME"
fi

# Check if we have the software to do it
# http://stackoverflow.com/questions/592620/check-if-a-program-exists-from-a-bash-script
type ffmpeg >/dev/null 2>&1 || { echo >&2 "ffmpeg required but it's not installed. Aborting."; exit 1; }

# On some systems not using '-p .' (temp in current dir) might cause problems
STARTTS=`date +%s`

# Extract frames from video
run_command notify-send -a $0 "Starting panoramic video stitching..."
echo "Extracting frames from video (this might take a while)..."
run_command "ffmpeg" "-y" "-i" "$1" "$FRAMESTEMPDIR/$IMAGETMPL"

# Stitch frames
echo "Stitching frames..."
for i in $FRAMESTEMPDIR/*.jpg; do
  echo Frame: $i
  run_command "$DIR/gear360pano.cmd" "-m" "-o" "$OUTTEMPDIR" "$i" "$PTOTMPL"
done

# Put stitched frames together
echo "Recoding the video..."
run_command ffmpeg -y -f image2 -i "$OUTTEMPDIR/$IMAGETMPLENC" -r 30 -s 3840:1920 -vcodec libx264 "$OUTTEMPDIR/$TMPVIDEO"

# Check if there's an audio (https://stackoverflow.com/questions/21446804/find-if-video-file-has-audio-present-in-it)
ISAUDIO=`ffprobe -v fatal -of default=nw=1:nk=1 -show_streams -select_streams a -show_entries stream=codec_type "$1"`

if [ -n "$ISAUDIO" ]; then
  echo "Extracting audio..."
  run_command notify-send -a $0 "Extracting audio..."
  run_command ffmpeg -y -i "$1" -vn -acodec copy "$OUTTEMPDIR/$TMPAUDIO"

  echo "Merging audio..."
  run_command notify-send -a $0 "Merging audio..."
  run_command ffmpeg -y -i "$OUTTEMPDIR/$TMPVIDEO" -i "$OUTTEMPDIR/$TMPAUDIO" -c:v copy -c:a aac -strict experimental "$OUTNAME"
else
  print_debug "No audio detected"
  mv "$OUTTEMPDIR/$TMPVIDEO" "$OUTNAME"
fi

# Remove temporary directories
clean_up

# Inform user about the result
ENDTS=`date +%s`
RUNTIME=$((ENDTS-STARTTS))
echo Video written to $OUTNAME, took: $RUNTIME s
run_command notify-send -a $0 "'Conversion complete. Video written to $OUTNAME, took: $RUNTIME s'"
exit 0

################################ Windows part here

:CMDSCRIPT

set FFMPEGPATH=c:\Program Files\ffmpeg\bin
set FRAMESTEMPDIR=frames
set OUTTEMPDIR=frames_stitched
set PTOTMPL=gear360video.pto
rem %% is an escape character (note: this will fail on wine's cmd.exe)
set IMAGETMPL=image%%05d.jpg
set IMAGETMPLENC=image%%05d_pano.jpg
set TMPAUDIO=tmpaudio.aac
set TMPVIDEO=tmpvideo.mp4
set DEBUG=""

rem Check arguments
IF [%1] == [] GOTO NOARGS

:SETNAMEOK
rem Check ffmpeg...
if exist "%FFMPEGPATH%/ffmpeg.exe" goto FFMPEGOK
goto NOFFMPEG

:FFMPEGOK
rem Create temporary directories
mkdir %FRAMESTEMPDIR%
mkdir %OUTTEMPDIR%

rem Execute commands (as simple as it is)
echo Converting video to images...
"%FFMPEGPATH%/ffmpeg.exe" -y -i %1 %FRAMESTEMPDIR%/%IMAGETMPL%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

rem Stitching
echo Stitching frames...
for %%f in (%FRAMESTEMPDIR%/*.jpg) do (
rem For whatever reason (this has to be at the beginning of the line!)
  echo Processing frame %FRAMESTEMPDIR%\%%f
rem TODO: There should be some error checking
  call gear360pano.cmd /m /o %OUTTEMPDIR% %FRAMESTEMPDIR%\%%f %PTOTMPL%
)

echo "Reencoding video..."
"%FFMPEGPATH%/ffmpeg.exe" -y -f image2 -i %OUTTEMPDIR%/%IMAGETMPLENC% -r 30 -s 3840:1920 -vcodec libx264 %OUTTEMPDIR%/%TMPVIDEO%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

echo "Extracting audio..."
"%FFMPEGPATH%/ffmpeg.exe" -y -i %1 -vn -acodec copy %OUTTEMPDIR%/%TMPAUDIO%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

echo "Merging audio..."

rem Check if second argument present, if not, set some default for output filename
rem This is here, because for whatever reason OUTNAME gets overriden by
rem the last iterated filename if this is at the beginning (for loop is buggy?)
if not [%2] == [] goto SETNAMEOK
set OUTNAME="%~n1_pano.mp4"

:SETNAMEOK
"%FFMPEGPATH%/ffmpeg.exe" -y -i %OUTTEMPDIR%/%TMPVIDEO% -i %OUTTEMPDIR%/%TMPAUDIO% -c:v copy -c:a aac -strict experimental %OUTNAME%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

rem Clean-up (f - force, read-only & dirs, q - quiet)
del /f /q %FRAMESTEMPDIR%
del /f /q %OUTTEMPDIR%

echo Video written to %OUTNAME%
goto eof

:NOARGS
echo Script to stitch raw video panorama files, raw
echo meaning two fisheye images side by side.
echo.
echo Script originally writen for Samsung Gear 360.
echo.
echo Usage:
echo %0 inputfile [outputfile]
echo.
echo Where inputfile is a panorama file from camera,
echo output parameter is optional
goto eof

:NOFFMPEG
echo ffmpeg was not found in %FFMPEGPATH%, download from: https://ffmpeg.zeranoe.com/builds/
echo and unpack to program files directory
goto eof

:FFMPEGERROR
echo ffmpeg failed, video not created
goto eof

:PRINT_DEBUG
if %DEBUG% == "yes" (
  echo DEBUG: %1 %2 %3 %4 %5 %6 %7 %8 %9
)

exit /b 0

:eof
