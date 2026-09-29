@echo off
:: ============================================================================
::  Smart File Organizer for Windows
::  Sorts files into folders by type, tidies loose folders, cleans empty ones.
::
::  Usage:
::    Double-click          -> asks which folder to organize
::    Drag a folder onto it -> organizes that folder
::    Command line:
::      organize_files.bat "C:\Users\me\Downloads" [/preview] [/folders] [/clean] [/yes]
::
::      /preview  Dry run - only show what would happen, move nothing
::      /folders  Move other existing folders into "_Folders"
::      /clean    Delete EMPTY sub-folders afterwards
::      /yes      Don't ask any questions (use only the switches given)
::
::  Every real run writes a log and an UNDO script to "_OrganizerLogs".
::
::  https://github.com/X-rajat/smart-file-organizer  -  MIT License
:: ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1
title Smart File Organizer

set "SELF=%~f0"
set "TARGET="
set "DRY="
set "GATHER="
set "CLEAN="
set "NOASK=0"

:ParseArgs
if "%~1"=="" goto :ArgsDone
if /i "%~1"=="/help" goto :Usage
if /i "%~1"=="/preview" (set "DRY=1") else if /i "%~1"=="/folders" (set "GATHER=1") else if /i "%~1"=="/clean" (set "CLEAN=1") else if /i "%~1"=="/yes" (set "NOASK=1") else set "TARGET=%~1"
shift
goto :ParseArgs
:ArgsDone

:: ---------------------------------------------------------------------------
::  Category map  (folder  ->  extensions)
::  Edit these lines to add/change types. Sub-folders like "Documents\PDF" are OK.
:: ---------------------------------------------------------------------------
set "CATDIRS="
call :Reg "Documents\PDF"            ".pdf"
call :Reg "Documents\Word"           ".doc .docx .docm .dot .dotx .odt .rtf .pages .wps"
call :Reg "Documents\Spreadsheets"   ".xls .xlsx .xlsm .xlsb .ods .csv .tsv .numbers"
call :Reg "Documents\Presentations"  ".ppt .pptx .pptm .pps .ppsx .odp .key"
call :Reg "Documents\Text"           ".txt .md .log .tex .nfo"
call :Reg "Documents\eBooks"         ".epub .mobi .azw .azw3 .djvu .fb2 .cbr .cbz"
call :Reg "Images"                   ".jpg .jpeg .jfif .png .gif .bmp .tif .tiff .webp .heic .heif .avif .ico .svg"
call :Reg "Images\RAW"               ".raw .cr2 .cr3 .nef .arw .dng .orf .rw2 .raf"
call :Reg "Videos"                   ".mp4 .mkv .avi .mov .wmv .flv .webm .m4v .mpg .mpeg .3gp .vob .mts .m2ts"
call :Reg "Audio"                    ".mp3 .wav .flac .aac .ogg .oga .wma .m4a .opus .aiff .aif .mid .midi .amr"
call :Reg "Archives"                 ".zip .rar .7z .tar .gz .tgz .bz2 .xz .zst .cab .lzh"
call :Reg "Software\Installers"      ".exe .msi .msix .msixbundle .appx .appxbundle .apk .xapk .dmg .pkg .deb .rpm"
call :Reg "Software\DiskImages"      ".iso .img .vhd .vhdx .vmdk .ova .ovf .qcow2"
call :Reg "Code"                     ".py .ipynb .js .mjs .ts .jsx .tsx .html .htm .css .scss .java .c .cpp .h .hpp .cs .go .rs .php .rb .swift .kt .sh .ps1 .bat .cmd .vbs .sql .json .xml .yaml .yml .toml .ini .cfg .r .lua"
call :Reg "Fonts"                    ".ttf .otf .woff .woff2 .fon"
call :Reg "Design"                   ".psd .ai .xd .fig .sketch .indd .eps .cdr .afdesign .afphoto"
call :Reg "Design\3D-CAD"            ".blend .obj .fbx .stl .3mf .dwg .dxf .skp .step .stp"
call :Reg "Torrents"                 ".torrent"
call :Reg "Shortcuts"                ".lnk .url"
:: Unfinished downloads / temp files are left alone
for %%E in (.crdownload .part .partial .download .tmp) do set "MAP%%E=__SKIP__"

:: Top-level folders the organizer owns (never moved into _Folders)
set ROOTS="Documents" "Images" "Videos" "Audio" "Archives" "Software" "Code" "Fonts" "Design" "Torrents" "Shortcuts" "Others" "_Folders" "_OrganizerLogs"

:: ---------------------------------------------------------------------------
::  Pick & validate the target folder
:: ---------------------------------------------------------------------------
echo.
echo  ==========================================
echo           SMART FILE ORGANIZER
echo  ==========================================
echo.
if not defined TARGET if "%NOASK%"=="0" set /p "TARGET= Folder to organize (drag it here, or press Enter for this script's folder): "
if not defined TARGET set "TARGET=%~dp0"
set "TARGET=%TARGET:"=%"
for %%I in ("%TARGET%") do set "TARGET=%%~fI"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"

if not exist "%TARGET%\" (
    echo  ERROR: Folder not found: "%TARGET%"
    goto :End
)

:: Refuse system folders
for %%P in ("%SystemRoot%" "%ProgramFiles%" "%ProgramFiles(x86)%" "%ProgramData%" "%SystemDrive%") do (
    if /i "%TARGET%"=="%%~P" (
        echo  REFUSED: "%TARGET%" is a system folder. Pick something like Downloads or Desktop.
        goto :End
    )
)

:: Drive roots / user profile: sort loose files only, never touch folders
set "PROTECTED=0"
if /i "%TARGET%"=="%USERPROFILE%" set "PROTECTED=1"
if "%TARGET:~2%"=="" set "PROTECTED=1"

:: ---------------------------------------------------------------------------
::  Options
:: ---------------------------------------------------------------------------
if "%NOASK%"=="0" if not defined DRY call :Ask DRY "Preview only - show what would happen, move nothing?"
if "%PROTECTED%"=="0" if "%NOASK%"=="0" if not defined GATHER call :Ask GATHER "Move other existing folders into a '_Folders' folder?"
if "%PROTECTED%"=="0" if "%NOASK%"=="0" if not defined CLEAN call :Ask CLEAN "Delete EMPTY sub-folders afterwards?"
if not defined DRY set "DRY=0"
if not defined GATHER set "GATHER=0"
if not defined CLEAN set "CLEAN=0"
if "%PROTECTED%"=="1" (
    set "GATHER=0"
    set "CLEAN=0"
    echo  NOTE: Drive root / user profile detected - only loose files will be sorted.
)

echo.
echo  Target folder : %TARGET%
if "%DRY%"=="1" (echo  Mode          : PREVIEW - nothing will be moved) else (echo  Mode          : ORGANIZE)
if "%GATHER%"=="1" (echo  Loose folders : move into _Folders) else (echo  Loose folders : leave as-is)
if "%CLEAN%"=="1"  (echo  Empty folders : delete) else (echo  Empty folders : keep)
echo.
if "%NOASK%"=="0" (
    choice /c YN /n /m " Continue? [Y/N] "
    if errorlevel 2 goto :End
)

:: ---------------------------------------------------------------------------
::  Log + undo script
:: ---------------------------------------------------------------------------
set "STAMP="
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss" 2^>nul') do set "STAMP=%%T"
if not defined STAMP set "STAMP=%RANDOM%%RANDOM%"
set "LOGDIR=%TARGET%\_OrganizerLogs"
set "LOG=%LOGDIR%\log_%STAMP%.txt"
set "UNDO=%LOGDIR%\undo_%STAMP%.bat"
if "%DRY%"=="1" goto :SkipLogInit
md "%LOGDIR%" 2>nul
>"%LOG%"  echo File Organizer run %STAMP% on "%TARGET%"
>"%UNDO%" echo @echo off
>>"%UNDO%" echo chcp 65001 ^>nul
>>"%UNDO%" echo echo Reverting File Organizer run %STAMP% ...
:SkipLogInit

set /a MOVED=0, FAILED=0, SKIPPED=0, REMOVED=0

:: ---------------------------------------------------------------------------
::  1) Sort files by type (top level only; hidden/system files are ignored)
:: ---------------------------------------------------------------------------
echo.
echo  --- Sorting files ---
for /f "eol=: delims=" %%F in ('dir /b /a:-d-h-s "%TARGET%\" 2^>nul') do (
    set "SRC=%TARGET%\%%F"
    set "NAME=%%F"
    set "BASE=%%~nF"
    set "EXT=%%~xF"
    call :ProcessFile
)

:: ---------------------------------------------------------------------------
::  2) Tidy loose folders into _Folders
:: ---------------------------------------------------------------------------
if not "%GATHER%"=="1" goto :SkipGather
echo.
echo  --- Tidying folders ---
for /f "eol=: delims=" %%D in ('dir /b /a:d-h-s "%TARGET%\" 2^>nul') do (
    set "SRC=%TARGET%\%%D"
    set "NAME=%%D"
    call :ProcessFolder
)
:SkipGather

:: ---------------------------------------------------------------------------
::  3) Remove empty folders (rd without /s only ever deletes EMPTY folders)
:: ---------------------------------------------------------------------------
if not "%CLEAN%"=="1" goto :SkipClean
echo.
if "%DRY%"=="1" (
    echo  --- Empty folders would be removed here - skipped in preview ---
    goto :SkipClean
)
echo  --- Removing empty folders ---
for /f "delims=" %%D in ('dir /b /s /a:d "%TARGET%\" 2^>nul ^| sort /r') do (
    rd "%%D" 2>nul && (
        echo   [removed] %%D
        set /a REMOVED+=1
    )
)
:SkipClean

:: Finish undo script: move things back, then delete now-empty category folders
if "%DRY%"=="1" goto :Summary
for %%C in (%CATDIRS% %ROOTS%) do >>"%UNDO%" echo rd "%TARGET%\%%~C" 2^>nul
>>"%UNDO%" echo echo Done.
>>"%UNDO%" echo pause

:Summary
echo.
echo  ==========================================
if "%DRY%"=="1" (
    echo   PREVIEW COMPLETE - nothing was moved
    echo   Would move : %MOVED%
) else (
    echo   DONE
    echo   Moved      : %MOVED%
    echo   Removed    : %REMOVED% empty folders
)
echo   Failed     : %FAILED%
echo   Skipped    : %SKIPPED%
if "%DRY%"=="0" (
    echo.
    echo   Log  : %LOG%
    echo   Undo : %UNDO%
)
echo  ==========================================
goto :End


:: ============================================================================
::  Subroutines
:: ============================================================================

:Reg  <folder> <extensions>
for %%E in (%~2) do set "MAP%%E=%~1"
set CATDIRS="%~1" %CATDIRS%
goto :eof

:Ask  <var> <question>
choice /c YN /n /m " %~2 [Y/N] "
if errorlevel 2 (set "%~1=0") else set "%~1=1"
goto :eof

:ProcessFile
:: Delayed expansion is enabled only here, so names containing ! stay intact
setlocal EnableDelayedExpansion
if /i "!SRC!"=="!SELF!" goto :P_Skip
if /i "!NAME!"=="desktop.ini" goto :P_Skip
if /i "!NAME!"=="thumbs.db" goto :P_Skip
set "CAT="
if defined EXT for %%E in ("!EXT!") do set "CAT=!MAP%%~E!"
if "!CAT!"=="__SKIP__" goto :P_Skip
if not defined CAT set "CAT=Others"
set "DDIR=!TARGET!\!CAT!"
set "DEST=!DDIR!\!NAME!"
:: Name clash -> "photo (1).jpg", "photo (2).jpg", ...
if exist "!DEST!" (
    set "DEST="
    for /L %%N in (1,1,9999) do if not defined DEST if not exist "!DDIR!\!BASE! (%%N)!EXT!" set "DEST=!DDIR!\!BASE! (%%N)!EXT!"
)
goto :P_Move

:ProcessFolder
setlocal EnableDelayedExpansion
for %%R in (%ROOTS%) do if /i "!NAME!"=="%%~R" goto :P_Owned
set "CAT=_Folders"
set "DDIR=!TARGET!\_Folders"
set "DEST=!DDIR!\!NAME!"
if exist "!DEST!" (
    set "DEST="
    for /L %%N in (1,1,9999) do if not defined DEST if not exist "!DDIR!\!NAME! (%%N)" set "DEST=!DDIR!\!NAME! (%%N)"
)
goto :P_Move

:P_Move
if "!DRY!"=="1" (
    echo   [preview] !NAME!  --^>  !CAT!\
    endlocal & set /a MOVED+=1
    goto :eof
)
if not exist "!DDIR!\" md "!DDIR!" 2>nul
move "!SRC!" "!DEST!" >nul 2>&1 || goto :P_Fail
echo   [moved]   !NAME!  --^>  !CAT!\
>>"!LOG!"  echo MOVED   "!SRC!"  --^>  "!DEST!"
>>"!UNDO!" echo move "!DEST!" "!SRC!" ^>nul
endlocal & set /a MOVED+=1
goto :eof

:P_Fail
echo   [FAILED]  !NAME!  - in use or access denied
>>"!LOG!" echo FAILED  "!SRC!"
endlocal & set /a FAILED+=1
goto :eof

:P_Skip
endlocal & set /a SKIPPED+=1
goto :eof

:P_Owned
endlocal
goto :eof

:Usage
echo.
echo  organize_files.bat "folder" [/preview] [/folders] [/clean] [/yes]
echo.
echo    /preview  Dry run - show what would happen, move nothing
echo    /folders  Move other existing folders into "_Folders"
echo    /clean    Delete EMPTY sub-folders afterwards
echo    /yes      No questions (use only the switches given)
echo.

:End
echo.
if "%NOASK%"=="0" pause
endlocal
exit /b
