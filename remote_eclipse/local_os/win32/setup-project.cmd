@echo off
cd %REMOTE_ECLIPSE_LOC%\local_windows
bash -c './setup-project.bash %*'