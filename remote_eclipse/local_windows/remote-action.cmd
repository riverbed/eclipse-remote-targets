@echo off
set PATH=%REMOTE_ECLIPSE_LOC%\remote_unix\local_shared;%PATH%	
set PATH=%REMOTE_ECLIPSE_LOC%\local_common;%PATH%
set PATH=%REMOTE_ECLIPSE_LOC%\local_windows;%PATH%

REM sniemczyk: 2015-01-07: Eclipse inserts a tab character in the space at the
REM end of the path, so we are removing it since it messes with msysgit's
REM path translation
set PATH=%PATH:	=%

setlocal enabledelayedexpansion enableextensions
	set args=_ZXXZ_ %*
	REM Translate path to Unix, to standardize/simplify
	set args=%args:\=/%
	REM We must put quotes around arguments that use ~ for bash
	set args=%args:'=\'%
	set args=%args:_ZXXZ_ =%
endlocal & bash -c 'source bash-config.bash; remote-action.sh %args%'
